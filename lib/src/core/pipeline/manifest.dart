import 'dart:convert';

import 'package:crypto/crypto.dart';

/// sha256 over the locale files, independent of file order and line endings.
String fingerprint(Map<String, String> filesByLocale) {
  final locales = filesByLocale.keys.toList()..sort();
  final buffer = StringBuffer();
  for (final locale in locales) {
    buffer
      ..write(locale)
      ..write('\u0000')
      ..write(filesByLocale[locale]!.replaceAll('\r\n', '\n'))
      ..write('\u0000');
  }
  return sha256.convert(utf8.encode(buffer.toString())).toString();
}

/// Written next to a package's generated file so apps can read its key set
/// and freshness without access to the package's assets.
class KumaManifest {
  const KumaManifest({
    required this.className,
    required this.fingerprint,
    required this.inputDir,
    required this.locales,
    required this.keys,
  });

  static const version = 1;

  final String className;
  final String fingerprint;
  final String inputDir;
  final List<String> locales;

  /// Every leaf key path the package's JSON defines, including excluded keys.
  final List<String> keys;

  String encode() => '${const JsonEncoder.withIndent('  ').convert({
            'kuma': version,
            'class': className,
            'fingerprint': fingerprint,
            'input_dir': inputDir,
            'locales': locales,
            'keys': keys,
          })}\n';

  static KumaManifest decode(String source) {
    final json = jsonDecode(source);
    if (json is! Map<String, Object?> || json['kuma'] != version) {
      throw const FormatException('not a kuma manifest (version 1)');
    }
    return KumaManifest(
      className: json['class'] as String,
      fingerprint: json['fingerprint'] as String,
      inputDir: json['input_dir'] as String,
      locales: [for (final l in json['locales'] as List) l as String],
      keys: [for (final k in json['keys'] as List) k as String],
    );
  }
}
