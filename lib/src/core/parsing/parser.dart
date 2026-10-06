import 'dart:convert';

import '../diagnostics/diagnostics.dart';
import 'ir.dart';

/// Parses one locale file into a [LocaleTree], reporting structural problems.
///
/// Returns `null` if the file is not a JSON object.
LocaleTree? parseLocale(String locale, String source, DiagnosticSink sink) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (e) {
    sink.error('json', 'invalid JSON: ${e.message}', locale: locale);
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    sink.error('json', 'top level must be a JSON object', locale: locale);
    return null;
  }
  return LocaleTree(locale, _namespace('', decoded, locale, sink));
}

NamespaceNode _namespace(
  String path,
  Map<String, Object?> map,
  String locale,
  DiagnosticSink sink,
) {
  final children = <String, L10nNode>{};
  for (final MapEntry(:key, :value) in map.entries) {
    final childPath = path.isEmpty ? key : '$path.$key';
    if (key.contains('.')) {
      // easy_localization splits keys on '.', so this entry can never be read.
      sink.error(
        'unreachable',
        'key contains "." and can never be looked up by easy_localization',
        path: childPath,
        locale: locale,
      );
      continue;
    }
    if (key.isEmpty) {
      sink.error('unreachable', 'empty key', path: childPath, locale: locale);
      continue;
    }
    final node = _node(childPath, value, locale, sink);
    if (node != null) children[key] = node;
  }
  return NamespaceNode(path, children);
}

L10nNode? _node(
    String path, Object? value, String locale, DiagnosticSink sink) {
  switch (value) {
    case String():
      return MessageNode(path, value);
    case Map<String, Object?>():
      if (value.isEmpty) {
        sink.error('structure', 'empty object', path: path, locale: locale);
        return null;
      }
      final pluralKeys = value.keys.where(pluralForms.contains).toList();
      if (pluralKeys.length == value.length) {
        return _plural(path, value, locale, sink);
      }
      if (pluralKeys.isNotEmpty) {
        sink.error(
          'structure',
          'mixes plural forms (${pluralKeys.join(', ')}) with other keys',
          path: path,
          locale: locale,
        );
        return null;
      }
      return _namespace(path, value, locale, sink);
    default:
      sink.error(
        'structure',
        'value must be a string or an object, got ${_typeName(value)}',
        path: path,
        locale: locale,
      );
      return null;
  }
}

PluralNode? _plural(
  String path,
  Map<String, Object?> value,
  String locale,
  DiagnosticSink sink,
) {
  final forms = <String, String>{};
  for (final form in pluralForms) {
    if (!value.containsKey(form)) continue;
    final text = value[form];
    if (text is! String) {
      sink.error(
        'structure',
        'plural form "$form" must be a string',
        path: path,
        locale: locale,
      );
      return null;
    }
    forms[form] = text;
  }
  return PluralNode(path, forms);
}

String _typeName(Object? value) => switch (value) {
      null => 'null',
      num() => 'number',
      bool() => 'boolean',
      List() => 'array',
      _ => value.runtimeType.toString(),
    };
