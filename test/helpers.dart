import 'dart:convert';
import 'dart:io';

import 'package:kuma/kuma.dart';
import 'package:path/path.dart' as p;

/// In-memory [KumaInputs].
class MemoryInputs implements KumaInputs {
  MemoryInputs(
    this.files, {
    this.packageFiles = const {},
    this.packageJson,
    this.dirFiles = const {},
  });

  /// `input_dir` → files, for micro-apps. Other dirs get [files].
  final Map<String, Map<String, String>> dirFiles;

  /// File name → content for this package.
  final Map<String, String> files;

  /// package → (path → content), for manifests.
  final Map<String, Map<String, String>> packageFiles;

  /// package → (file name → content), or null to simulate build_runner.
  final Map<String, Map<String, String>>? packageJson;

  @override
  Future<Map<String, String>> localeFiles(String inputDir) async =>
      dirFiles[inputDir] ?? files;

  @override
  Future<String?> readPackageFile(String package, String path) async =>
      packageFiles[package]?[path];

  @override
  Future<Map<String, String>?> packageLocaleFiles(
    String package,
    String inputDir,
  ) async =>
      packageJson?[package];
}

/// Encodes locale maps as files: `{'en': {...}}` → `{'en.json': '...'}`.
Map<String, String> jsonFiles(Map<String, Map<String, Object?>> locales) => {
      for (final e in locales.entries) '${e.key}.json': jsonEncode(e.value),
    };

Future<KumaResult> run(
  Map<String, Map<String, Object?>> locales, {
  KumaConfig config = const KumaConfig(),
}) =>
    runKuma(config, MemoryInputs(jsonFiles(locales)));

/// Real translation files trimmed from praises-ai-quick-access.
Map<String, String> yohannaFixture() => {
      for (final l in ['en', 'pt', 'es'])
        '$l.json': File(p.join('test', 'fixtures', 'yohanna', '$l.json'))
            .readAsStringSync(),
    };

/// `code locale path` for each diagnostic of [severity], for compact asserts.
List<String> summary(KumaResult result, [Severity? severity]) => [
      for (final d in result.diagnostics)
        if (severity == null || d.severity == severity)
          '${d.code} ${d.locale ?? '-'} ${d.path ?? '-'}',
    ];
