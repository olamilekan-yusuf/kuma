import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import '../core/config/config.dart';
import '../core/pipeline/pipeline.dart';

/// Loads config for the package at [root]: [configPath] if given, else
/// `kuma.yaml`, else the `kuma:` section of `pubspec.yaml`, else defaults.
KumaConfig loadConfig(String root, {String? configPath}) {
  if (configPath != null) {
    final file =
        File(p.isAbsolute(configPath) ? configPath : p.join(root, configPath));
    if (!file.existsSync()) {
      throw KumaConfigException('config file not found: ${file.path}');
    }
    return KumaConfig.fromYaml(file.readAsStringSync())!;
  }
  final kumaYaml = File(p.join(root, 'kuma.yaml'));
  if (kumaYaml.existsSync()) {
    return KumaConfig.fromYaml(kumaYaml.readAsStringSync())!;
  }
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  if (pubspec.existsSync()) {
    final fromPubspec = KumaConfig.fromYaml(
      pubspec.readAsStringSync(),
      isPubspec: true,
    );
    if (fromPubspec != null) return fromPubspec;
  }
  return const KumaConfig();
}

/// Reads inputs from disk, resolving other packages via
/// `.dart_tool/package_config.json`.
class IoInputs implements KumaInputs {
  IoInputs(this.root, this.config);

  final String root;
  final KumaConfig config;
  PackageConfig? _packages;
  bool _packagesLoaded = false;

  @override
  Future<Map<String, String>> localeFiles(String inputDir) async =>
      _jsonFiles(Directory(p.join(root, inputDir)));

  @override
  Future<String?> readPackageFile(String package, String path) async {
    final dir = await _packageRoot(package);
    if (dir == null) return null;
    final file = File(p.join(dir, path));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  Future<Map<String, String>?> packageLocaleFiles(
    String package,
    String inputDir,
  ) async {
    final dir = await _packageRoot(package);
    if (dir == null) return null;
    final assets = Directory(p.join(dir, inputDir));
    if (!assets.existsSync()) return null;
    return _jsonFiles(assets);
  }

  Future<String?> _packageRoot(String package) async {
    if (!_packagesLoaded) {
      _packages = await findPackageConfig(Directory(root));
      _packagesLoaded = true;
    }
    final entry = _packages?[package];
    if (entry == null) return null;
    return entry.root.toFilePath();
  }

  static Map<String, String> _jsonFiles(Directory dir) {
    if (!dir.existsSync()) return {};
    return {
      for (final file in dir.listSync().whereType<File>())
        if (p.extension(file.path) == '.json')
          p.basename(file.path): file.readAsStringSync(),
    };
  }
}
