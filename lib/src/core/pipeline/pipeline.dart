import 'dart:convert';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../diagnostics/diagnostics.dart';
import '../generation/generator.dart';
import '../parsing/ir.dart';
import 'manifest.dart';
import '../generation/model.dart';
import '../generation/naming.dart';
import '../parsing/parser.dart';
import '../validation/validator.dart';

/// Where the pipeline reads from. The CLI reads the file system; the builder
/// reads build_runner assets.
abstract interface class KumaInputs {
  /// Files in [inputDir] of this package, keyed by file name (`en.json`).
  /// Not recursive: a micro-app's subdirectory is read by its own run.
  Future<Map<String, String>> localeFiles(String inputDir);

  /// A file inside another package (used for namespace manifests), or `null`.
  Future<String?> readPackageFile(String package, String path);

  /// Locale files of another package, keyed by file name, or `null` when the
  /// package's assets can't be read (build_runner can't read them).
  Future<Map<String, String>?> packageLocaleFiles(
    String package,
    String inputDir,
  );
}

class KumaResult {
  const KumaResult(
    this.diagnostics,
    this.outputs, {
    this.ownKeys = const [],
  });

  /// Leaf key paths of the base locale, for overlap checks against other
  /// sources.
  final List<String> ownKeys;

  /// Sorted by severity, path and locale.
  final List<Diagnostic> diagnostics;

  /// Output path (relative to the package root) → content. Empty on errors.
  final Map<String, String> outputs;

  bool get hasErrors => diagnostics.any((d) => d.severity == Severity.error);
}

/// read → parse → validate → check namespaces → build model → generate.
Future<KumaResult> runKuma(KumaConfig config, KumaInputs inputs) async {
  final sink = DiagnosticSink();

  // Micro-apps run first so their keys take part in the overlap check.
  final appKeys = <String, List<String>>{};
  final appOutputs = <String, String>{};
  for (final app in config.microApps) {
    final result = await runKuma(app.config, inputs);
    for (final d in result.diagnostics) {
      sink.add(
        Diagnostic(
          d.severity,
          d.code,
          '[${app.id}] ${d.message}',
          path: d.path,
          locale: d.locale,
        ),
      );
    }
    appKeys['micro-app:${app.id}'] = result.ownKeys;
    appOutputs.addAll(result.outputs);
  }
  final seen = <String>{};
  for (final path in config.outputs) {
    if (!seen.add(path)) {
      sink.error('config', '$path is the output of more than one run');
    }
  }

  final files = await inputs.localeFiles(config.inputDir);
  final byLocale = _filesByLocale(files, config, sink);

  final trees = <String, LocaleTree>{};
  for (final MapEntry(key: locale, value: source) in byLocale.entries) {
    final tree = parseLocale(
      locale,
      _unwrapPrefix(source, config.keyPrefix),
      sink,
    );
    if (tree != null) trees[locale] = tree;
  }

  validateLocales(trees, config, sink);

  final base = trees[config.baseLocale];
  final ownKeys = base == null ? <String>[] : _leafPaths(base);
  final prefix = config.keyPrefix;
  final runtimeKeys = [
    for (final key in ownKeys) prefix == null ? key : '$prefix.$key',
  ];
  await _checkNamespaces(config, inputs, runtimeKeys, sink, appKeys);

  final model = base == null ? null : buildModel(base, config, sink);

  final diagnostics = [
    for (final d in sink.items)
      config.warningsAsErrors && d.severity == Severity.warning
          ? d.asError()
          : d,
  ]..sort();

  final failed = KumaResult(diagnostics, const {}, ownKeys: runtimeKeys);
  if (model == null || failed.hasErrors) return failed;

  final hash = fingerprint(byLocale);
  return KumaResult(
      diagnostics,
      {
        ...appOutputs,
        config.output: generateDart(
          root: model.root,
          classes: model.classes,
          config: config,
          fingerprint: hash,
        ),
        if (config.role == KumaRole.package)
          config.manifestOutput: KumaManifest(
            className: config.className,
            fingerprint: hash,
            inputDir: config.inputDir,
            locales: byLocale.keys.toList()..sort(),
            keys: ownKeys,
          ).encode(),
      },
      ownKeys: runtimeKeys);
}

/// `{"kids": {...}}` → `{...}` when [prefix] is the only root key, so the
/// generated getters don't repeat it. Anything else is returned unchanged.
String _unwrapPrefix(String source, String? prefix) {
  if (prefix == null) return source;
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map && decoded.length == 1 && decoded[prefix] is Map) {
      return jsonEncode(decoded[prefix]);
    }
  } on FormatException {
    // Left for parseLocale to report.
  }
  return source;
}

/// Keeps `*.json` files and keys them by locale, in locale-name order.
Map<String, String> _localesFromFiles(Map<String, String> files) {
  final names = files.keys.where((n) => p.extension(n) == '.json').toList()
    ..sort();
  return {
    for (final name in names)
      p.basenameWithoutExtension(name).replaceAll('_', '-'): files[name]!,
  };
}

/// File name → locale (`en.json` → `en`, `pt_BR.json` → `pt-BR`), keeping
/// only configured locales.
Map<String, String> _filesByLocale(
  Map<String, String> files,
  KumaConfig config,
  DiagnosticSink sink,
) {
  final found = _localesFromFiles(files);

  if (found.isEmpty) {
    sink.error(
      'locale',
      'no *.json files found in "${config.inputDir}"',
    );
    return found;
  }

  final expected = config.locales;
  if (expected == null) return found;
  for (final locale in expected) {
    if (!found.containsKey(locale)) {
      sink.error('locale', 'no file for configured locale', locale: locale);
    }
  }
  for (final locale in found.keys.toList()) {
    if (!expected.contains(locale)) {
      sink.warning(
        'locale',
        'file is not in `locales`; it was not validated',
        locale: locale,
      );
      found.remove(locale);
    }
  }
  return found;
}

List<String> _leafPaths(LocaleTree tree) => [
      for (final node in tree.flatten().values)
        if (node is! NamespaceNode) node.path,
    ];

Future<void> _checkNamespaces(
  KumaConfig config,
  KumaInputs inputs,
  List<String> ownKeys,
  DiagnosticSink sink,
  Map<String, List<String>> microAppKeys,
) async {
  final keysBySource = <String, List<String>>{
    'this package': ownKeys,
    ...microAppKeys,
  };

  for (final ns in config.namespaces) {
    final source = await inputs.readPackageFile(ns.package, ns.manifestPath);
    if (source == null) {
      sink.error(
        'namespace',
        'package:${ns.package} has no kuma manifest at ${ns.manifestPath}. '
            'Run `dart run kuma generate` in that package with `role: package` '
            'and commit the output.',
      );
      continue;
    }
    final KumaManifest manifest;
    try {
      manifest = KumaManifest.decode(source);
    } on Object catch (e) {
      sink.error(
        'namespace',
        'package:${ns.package} manifest is unreadable: $e',
      );
      continue;
    }
    if (manifest.className != ns.className) {
      sink.error(
        'namespace',
        'package:${ns.package} generates ${manifest.className}, but the '
            'namespace "${ns.name}" expects ${ns.className}',
      );
    }

    final files =
        await inputs.packageLocaleFiles(ns.package, manifest.inputDir);
    if (files != null) {
      final current = fingerprint(_localesFromFiles(files));
      if (current != manifest.fingerprint) {
        sink.error(
          'stale',
          'package:${ns.package} generated code is out of date with its JSON. '
              'Run `dart run kuma generate` in that package and commit it.',
        );
      }
    }

    keysBySource['package:${ns.package}'] = manifest.keys;
  }

  _checkOverlaps(keysBySource, config, sink);
}

/// easy_localization merges loaders into one map, so the same key defined in
/// two sources silently resolves to whichever loads last.
void _checkOverlaps(
  Map<String, List<String>> keysBySource,
  KumaConfig config,
  DiagnosticSink sink,
) {
  if (config.overlap == OverlapPolicy.ignore) return;
  final allowed = KeyFilter(config.allowOverlap);
  void report(String message, String path) {
    if (allowed.excludes(path)) return;
    if (config.overlap == OverlapPolicy.warning) {
      sink.warning('overlap', message, path: path);
    } else {
      sink.error('overlap', message, path: path);
    }
  }

  final leafOwner = <String, String>{};
  keysBySource.forEach((source, keys) {
    for (final key in keys) {
      final owner = leafOwner[key];
      if (owner != null && owner != source) {
        report(
          'defined in both $owner and $source; at runtime one silently '
          'overrides the other',
          key,
        );
      } else {
        leafOwner[key] = source;
      }
    }
  });

  // A string in one source and a namespace over it in another.
  keysBySource.forEach((source, keys) {
    for (final key in keys) {
      final segments = key.split('.');
      for (var i = 1; i < segments.length; i++) {
        final prefix = segments.take(i).join('.');
        final owner = leafOwner[prefix];
        if (owner != null && owner != source) {
          report('is a string in $owner but a namespace in $source', prefix);
          break;
        }
      }
    }
  });
}
