import '../config/config.dart';
import '../diagnostics/diagnostics.dart';
import '../parsing/ir.dart';
import 'naming.dart';

/// A Dart parameter and the placeholder it fills.
class Param {
  const Param(this.dartName, this.placeholder);

  final String dartName;

  /// The `{name}` it fills, or `null` for a positional `{}`.
  final String? placeholder;
}

/// How a plural's count reaches the text.
enum CountMode {
  /// The single `{}` is filled with the count (no `args` passed).
  positional,

  /// `name: '<placeholder>'` fills a named placeholder with the count.
  named,

  /// The count only selects the form. Any `{}` are explicit [Param]s.
  none,
}

/// Parameters of one generated member.
sealed class Signature {
  const Signature(this.path, this.positional, this.named);

  final String path;

  /// Explicit `{}` arguments, in order, passed via `args:`.
  final List<Param> positional;

  /// Named placeholders, passed via `namedArgs:`.
  final List<Param> named;
}

class MessageSignature extends Signature {
  const MessageSignature(super.path, super.positional, super.named);

  bool get isGetter => positional.isEmpty && named.isEmpty;
}

class PluralSignature extends Signature {
  const PluralSignature(
    super.path,
    super.positional,
    super.named, {
    required this.countMode,
    required this.countName,
    required this.countParam,
    required this.formatParam,
  });

  final CountMode countMode;

  /// The named placeholder holding the count, for [CountMode.named].
  final String? countName;

  /// Dart name of the `num` parameter.
  final String countParam;

  /// Dart name of the optional `NumberFormat` parameter, or `null` when the
  /// count is never printed.
  final String? formatParam;
}

/// Works out the generated parameters for [node], which is the base-locale
/// node. Returns `null` and reports an error if it can't.
Signature? resolveSignature(
  L10nNode node,
  KumaConfig config,
  DiagnosticSink sink,
) {
  final path = node.path;
  switch (node) {
    case NamespaceNode():
      throw ArgumentError('namespaces have no signature');
    case MessageNode(:final placeholders):
      if (placeholders.positional > 0 && !config.allowPositionalArgs) {
        sink.error(
          'positional',
          'uses {} outside a plural; enable allow_positional_args or use '
              'named placeholders',
          path: path,
        );
        return null;
      }
      final positional =
          _positionalParams(path, placeholders.positional, config, sink);
      if (positional == null) return null;
      return MessageSignature(
        path,
        positional,
        _namedParams(placeholders.named,
            taken: positional.map((p) => p.dartName)),
      );
    case PluralNode(:final placeholders):
      return _plural(path, placeholders, config, sink);
  }
}

PluralSignature? _plural(
  String path,
  Placeholders placeholders,
  KumaConfig config,
  DiagnosticSink sink,
) {
  final override = config.pluralCount[path];
  final named = placeholders.named;
  final positionalCount = placeholders.positional;

  CountMode mode;
  String? countName;
  if (override != null) {
    if (override == 'none') {
      mode = CountMode.none;
    } else if (override == '{}' || override == 'positional') {
      if (positionalCount != 1) {
        sink.error(
          'plural-count',
          'plural_count says {} but the key has $positionalCount {}',
          path: path,
        );
        return null;
      }
      mode = CountMode.positional;
    } else {
      if (!named.contains(override)) {
        sink.error(
          'plural-count',
          'plural_count names {$override}, which no form uses',
          path: path,
        );
        return null;
      }
      mode = CountMode.named;
      countName = override;
    }
  } else if (positionalCount == 1) {
    mode = CountMode.positional;
  } else if (positionalCount > 1) {
    // Passing `args` stops easy_localization from filling the count, so every
    // {} becomes an explicit argument.
    mode = CountMode.none;
  } else if (named.length == 1) {
    mode = CountMode.named;
    countName = named.single;
  } else if (named.isEmpty) {
    mode = CountMode.none;
  } else {
    sink.error(
      'plural-count',
      'cannot tell which of ${named.map((n) => '{$n}').join(', ')} is the '
          'count; set plural_count.$path',
      path: path,
    );
    return null;
  }

  final explicitPositional = mode == CountMode.positional ? 0 : positionalCount;
  if (explicitPositional > 0 && !config.allowPositionalArgs) {
    sink.error(
      'positional',
      'uses {} for values other than the count; enable allow_positional_args '
          'or use named placeholders',
      path: path,
    );
    return null;
  }
  final positional = _positionalParams(path, explicitPositional, config, sink);
  if (positional == null) return null;

  final otherNamed = named.where((n) => n != countName).toSet();
  final namedParams = _namedParams(
    otherNamed,
    taken: positional.map((p) => p.dartName),
  );
  final taken = {
    ...positional.map((p) => p.dartName),
    ...namedParams.map((p) => p.dartName),
  };
  final countParam = _free('count', taken);
  final printsCount = mode != CountMode.none;
  return PluralSignature(
    path,
    positional,
    namedParams,
    countMode: mode,
    countName: countName,
    countParam: countParam,
    formatParam: printsCount ? _free('format', {...taken, countParam}) : null,
  );
}

List<Param>? _positionalParams(
  String path,
  int count,
  KumaConfig config,
  DiagnosticSink sink,
) {
  final names = config.paramNames[path];
  if (names == null) {
    return [for (var i = 0; i < count; i++) Param('arg$i', null)];
  }
  if (names.length != count) {
    sink.error(
      'param-names',
      'param_names lists ${names.length} name(s) but the key has $count {}',
      path: path,
    );
    return null;
  }
  final seen = <String>{};
  final params = <Param>[];
  for (final name in names) {
    if (!RegExp(r'^[a-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      sink.error(
        'param-names',
        '"$name" is not a valid lowerCamelCase parameter name',
        path: path,
      );
      return null;
    }
    final dartName = safeIdentifier(name, extraTaken: seen);
    seen.add(dartName);
    params.add(Param(dartName, null));
  }
  return params;
}

List<Param> _namedParams(Set<String> placeholders,
    {required Iterable<String> taken}) {
  final used = taken.toSet();
  final params = <Param>[];
  for (final placeholder in placeholders) {
    final dartName = safeIdentifier(placeholder, extraTaken: used);
    used.add(dartName);
    params.add(Param(dartName, placeholder));
  }
  return params;
}

String _free(String name, Set<String> taken) {
  var result = name;
  var i = 2;
  while (taken.contains(result)) {
    result = '$name${i++}';
  }
  return result;
}
