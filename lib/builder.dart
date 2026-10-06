import 'dart:io';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'src/core/config/config.dart';
import 'src/core/diagnostics/diagnostics.dart';
import 'src/core/pipeline/pipeline.dart';
import 'src/io/io_inputs.dart';

/// build_runner entry point.
///
/// Config comes from `kuma.yaml` / pubspec `kuma:` in the package being built,
/// with builder `options` from `build.yaml` applied on top. The option
/// `config: path/to/file.yaml` points at a different config file.
Builder kumaBuilder(BuilderOptions options) {
  final overrides = Map<String, Object?>.of(options.config);
  final configPath = overrides.remove('config') as String?;
  final config = loadConfig(
    Directory.current.path,
    configPath: configPath,
  ).overlay(overrides);
  return KumaBuilder(config);
}

class KumaBuilder implements Builder {
  KumaBuilder(this.config);

  final KumaConfig config;

  @override
  Map<String, List<String>> get buildExtensions => {
        r'$package$': config.outputs,
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final result = await runKuma(config, _BuildInputs(buildStep, config));

    for (final d in result.diagnostics) {
      final line =
          '${d.code} ${d.locale ?? '-'} ${d.path ?? '-'}: ${d.message}';
      switch (d.severity) {
        case Severity.error:
          log.severe(line);
        case Severity.warning:
          log.warning(line);
        case Severity.info:
          log.fine(line);
      }
    }
    if (result.hasErrors) {
      final errors =
          result.diagnostics.where((d) => d.severity == Severity.error).length;
      throw KumaBuildException(
        '$errors translation error(s); see the log above or run '
        '`dart run kuma check`.',
      );
    }

    for (final MapEntry(key: path, value: content) in result.outputs.entries) {
      await buildStep.writeAsString(
        AssetId(package, p.posix.normalize(path)),
        content,
      );
    }
  }
}

class KumaBuildException implements Exception {
  KumaBuildException(this.message);
  final String message;
  @override
  String toString() => 'kuma: $message';
}

class _BuildInputs implements KumaInputs {
  _BuildInputs(this.step, this.config);

  final BuildStep step;
  final KumaConfig config;

  @override
  Future<Map<String, String>> localeFiles(String inputDir) async {
    final files = <String, String>{};
    final dir = p.posix.normalize(inputDir);
    await for (final id in step.findAssets(Glob('$dir/*.json'))) {
      files[p.posix.basename(id.path)] = await step.readAsString(id);
    }
    if (files.isEmpty) {
      log.warning(
        'kuma: no JSON found under $dir. build_runner only sees files listed '
        'in the target\'s `sources`; add "$dir/**" to build.yaml.',
      );
    }
    return files;
  }

  @override
  Future<String?> readPackageFile(String package, String path) async {
    final id = AssetId(package, path);
    if (!await step.canRead(id)) return null;
    return step.readAsString(id);
  }

  /// build_runner can only read another package's `lib/`, so freshness of
  /// namespace packages is checked by `kuma check`, not here.
  @override
  Future<Map<String, String>?> packageLocaleFiles(
    String package,
    String inputDir,
  ) async =>
      null;
}
