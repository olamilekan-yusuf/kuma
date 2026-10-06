import '../config/config.dart';
import '../diagnostics/diagnostics.dart';
import '../parsing/ir.dart';
import 'plural_rules.dart';

/// Cross-checks every locale against the others.
///
/// The key universe is the union over all locales, so a key that exists only
/// in `es` is reported as missing from `en` and `pt`.
void validateLocales(
  Map<String, LocaleTree> trees,
  KumaConfig config,
  DiagnosticSink sink,
) {
  final base = config.baseLocale;
  if (!trees.containsKey(base)) {
    sink.error('locale', 'no file for base locale "$base"', locale: base);
    return;
  }

  // Base locale first so references and output order follow the base file.
  final locales = [base, ...trees.keys.where((l) => l != base)];
  final flat = {for (final l in locales) l: trees[l]!.flatten()};

  final universe = <String>{};
  for (final locale in locales) {
    universe.addAll(flat[locale]!.keys);
  }

  for (final path in universe) {
    final reference = _reference(path, locales, flat);

    for (final locale in locales) {
      final node = flat[locale]![path];
      if (node == null) {
        if (_parentMissingOrLeaf(path, flat[locale]!)) continue;
        final message =
            'missing (present in ${_presentIn(path, locales, flat)})';
        if (config.missingKey == MissingKeyPolicy.error) {
          sink.error('missing', message, path: path, locale: locale);
        } else {
          sink.warning('missing', message, path: path, locale: locale);
        }
        continue;
      }

      if (node.kind != reference.node.kind) {
        sink.error(
          'kind',
          'is a ${node.kind} here but a ${reference.node.kind} in '
              '${reference.locale}',
          path: path,
          locale: locale,
        );
        continue;
      }

      _checkPlaceholders(node, locale, reference, sink);
      _checkSelf(node, locale, config, sink);
    }
  }
}

typedef _Ref = ({String locale, L10nNode node});

/// The node every other locale is compared with: the base locale's, or the
/// first locale that has the key.
_Ref _reference(
  String path,
  List<String> locales,
  Map<String, Map<String, L10nNode>> flat,
) {
  for (final locale in locales) {
    final node = flat[locale]![path];
    if (node != null) return (locale: locale, node: node);
  }
  throw StateError('$path is in the universe but in no locale');
}

/// Only the highest missing ancestor is reported. If an ancestor is a leaf,
/// the kind mismatch on that ancestor is reported instead.
bool _parentMissingOrLeaf(String path, Map<String, L10nNode> nodes) {
  final segments = path.split('.');
  for (var i = segments.length - 1; i > 0; i--) {
    final parent = nodes[segments.take(i).join('.')];
    if (parent == null) return true;
    if (parent is! NamespaceNode) return true;
  }
  return false;
}

String _presentIn(
  String path,
  List<String> locales,
  Map<String, Map<String, L10nNode>> flat,
) =>
    locales.where((l) => flat[l]![path] != null).join(', ');

void _checkPlaceholders(
  L10nNode node,
  String locale,
  _Ref reference,
  DiagnosticSink sink,
) {
  if (locale == reference.locale) return;
  final mine = _placeholders(node);
  final theirs = _placeholders(reference.node);
  if (mine == null || theirs == null || mine.sameAs(theirs)) return;
  sink.error(
    'placeholder',
    '${reference.locale}=${theirs.describe()}  $locale=${mine.describe()}',
    path: node.path,
    locale: locale,
  );
}

Placeholders? _placeholders(L10nNode node) => switch (node) {
      MessageNode(:final placeholders) => placeholders,
      PluralNode(:final placeholders) => placeholders,
      NamespaceNode() => null,
    };

void _checkSelf(
  L10nNode node,
  String locale,
  KumaConfig config,
  DiagnosticSink sink,
) {
  final placeholders = _placeholders(node);
  if (placeholders != null &&
      placeholders.positional > 0 &&
      placeholders.named.isNotEmpty) {
    sink.warning(
      'mixed-args',
      'mixes {} and named placeholders (${placeholders.describe()})',
      path: node.path,
      locale: locale,
    );
  }

  switch (node) {
    case MessageNode():
      if (node.hasLinks) {
        sink.warning(
          'link',
          'uses @: links, which kuma does not resolve; placeholders of the '
              'linked key are not part of the generated signature',
          path: node.path,
          locale: locale,
        );
      }
    case PluralNode(:final forms):
      if (!forms.containsKey('other')) {
        sink.error(
          'plural',
          'has no "other" form',
          path: node.path,
          locale: locale,
        );
      }
      final expectations = pluralExpectations(locale, config);
      final missing = expectations.expected
          .where((f) => f != 'other' && !forms.containsKey(f))
          .toList();
      if (missing.isNotEmpty) {
        sink.warning(
          'plural',
          'missing forms: ${missing.join(', ')}',
          path: node.path,
          locale: locale,
        );
      }
      final unreachable =
          forms.keys.where((f) => !expectations.reachable.contains(f)).toList();
      if (unreachable.isNotEmpty) {
        sink.info(
          'plural',
          'forms never selected under ${config.pluralRules.name} rules: '
              '${unreachable.join(', ')}',
          path: node.path,
          locale: locale,
        );
      }
    case NamespaceNode():
      break;
  }
}
