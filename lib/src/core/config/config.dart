import 'package:yaml/yaml.dart';

import '../generation/naming.dart';

/// Whether the package is the app that owns `EasyLocalization`, or a library
/// whose generated code is committed and consumed by an app.
enum KumaRole { app, package }

/// Which plural forms easy_localization can select, and therefore which ones
/// the validator expects.
enum PluralRulesMode {
  /// `ignorePluralRules: true` (easy_localization's default):
  /// 0 → zero, 1 → one, 2 → two, anything else → other.
  fallback,

  /// CLDR rules per language (`ignorePluralRules: false`).
  cldr,

  /// A fixed list of required forms, see [KumaConfig.strictPluralForms].
  strict,
}

class NamespaceConfig {
  const NamespaceConfig({
    required this.name,
    required this.package,
    required this.className,
    required this.import,
  });

  /// Getter name on the root class, e.g. `core` → `context.t.core`.
  final String name;
  final String package;
  final String className;

  /// `package:` URI of the package's generated file.
  final String import;

  /// Path of the package's manifest inside its `lib/`, derived from [import].
  String get manifestPath {
    final uri = Uri.parse(import);
    final segments = uri.pathSegments.skip(1).join('/');
    return 'lib/${manifestPathFor(segments)}';
  }
}

/// A micro-app that ships its own translation files, generated into its own
/// class. Its keys join the overlap check, because easy_localization merges
/// every loader into one map.
class MicroAppConfig {
  const MicroAppConfig({required this.id, required this.config});

  final String id;

  /// Settings for this micro-app's own run: `input_dir`, `output`, ...
  final KumaConfig config;
}

class KumaConfigException implements Exception {
  final String message;

  const KumaConfigException(this.message);

  @override
  String toString() => 'kuma config: $message';
}

class KumaConfig {
  const KumaConfig({
    this.role = KumaRole.app,
    this.inputDir = 'assets/translations',
    this.baseLocale = 'en',
    this.locales,
    this.output = 'lib/l10n/translations.g.dart',
    this.className = 'Translations',
    bool? contextExtension,
    this.contextGetter = 't',
    this.keyPrefix,
    this.namespaces = const [],
    this.microApps = const [],
    this.pluralRules = PluralRulesMode.fallback,
    this.strictPluralForms = const ['one', 'other'],
    this.pluralCount = const {},
    this.paramNames = const {},
    this.allowPositionalArgs = true,
    this.missingKey = MissingKeyPolicy.error,
    this.exclude = const [],
    this.overlap = OverlapPolicy.error,
    this.allowOverlap = const [],
    this.digitPrefix = 'n',
    this.warningsAsErrors = false,
    this.source = const {},
  }) : contextExtension = contextExtension ?? role == KumaRole.app;

  final KumaRole role;
  final String inputDir;
  final String baseLocale;

  /// Expected locales. `null` means "whatever files exist".
  final List<String>? locales;
  final String output;
  final String className;
  final String contextGetter;

  /// Prepended to every key the generated code looks up: `kids` makes
  /// `kidsHome` call `tr('kids.kidsHome')`. A root object of the same name in
  /// the JSON is unwrapped first, so both `{"kids": {...}}` and a flat file
  /// give the same getters.
  final String? keyPrefix;
  final List<NamespaceConfig> namespaces;
  final List<MicroAppConfig> microApps;
  final PluralRulesMode pluralRules;
  final List<String> strictPluralForms;

  /// Per-key plural count placeholder. The value `none` means the count only
  /// selects the form and is not substituted.
  final Map<String, String> pluralCount;

  /// Per-key names for positional `{}` arguments.
  final Map<String, List<String>> paramNames;
  final bool allowPositionalArgs;
  final MissingKeyPolicy missingKey;

  /// Globs over full key paths. Excluded keys are validated but not generated.
  final List<String> exclude;

  /// What a key defined in two sources (app, packages, micro-apps) is.
  final OverlapPolicy overlap;

  /// Globs over runtime key paths that may be defined in more than one
  /// source. They are skipped by the overlap check.
  final List<String> allowOverlap;
  final String digitPrefix;
  final bool warningsAsErrors;

  /// Packages never generate a `BuildContext` extension by default, so an app
  /// importing several of them does not get ambiguous extensions.
  final bool contextExtension;

  /// The decoded options this config was built from, kept for [overlay].
  final Map<String, Object?> source;

  /// Manifest written next to [output] when [role] is [KumaRole.package].
  String get manifestOutput => manifestPathFor(output);

  /// Every file a run writes, micro-apps included.
  List<String> get outputs => [
        output,
        if (role == KumaRole.package) manifestOutput,
        for (final app in microApps) ...app.config.outputs,
      ];

  static const _knownKeys = {
    'role',
    'input_dir',
    'base_locale',
    'locales',
    'output',
    'class_name',
    'context_extension',
    'context_getter',
    'key_prefix',
    'namespaces',
    'micro_apps',
    'plural_rules',
    'strict_plural_forms',
    'plural_count',
    'param_names',
    'allow_positional_args',
    'missing_key',
    'exclude',
    'overlap',
    'allow_overlap',
    'digit_prefix',
    'warnings_as_errors',
  };

  /// Builds a config from a decoded YAML/JSON map (the `kuma:` section).
  factory KumaConfig.fromMap(Map<Object?, Object?> raw) {
    final map = <String, Object?>{
      for (final e in raw.entries) e.key.toString(): _plain(e.value),
    };
    final unknown = map.keys.where((k) => !_knownKeys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw KumaConfigException('unknown option(s): ${unknown.join(', ')}');
    }

    T? read<T>(String key) {
      final value = map[key];
      if (value == null) return null;
      if (value is! T) {
        throw KumaConfigException('`$key` must be a $T, got $value');
      }
      return value as T;
    }

    List<String>? stringList(String key) =>
        read<List<Object?>>(key)?.map((e) => e.toString()).toList();

    E? enumValue<E extends Enum>(String key, List<E> values) {
      final value = read<String>(key);
      if (value == null) return null;
      return values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw KumaConfigException(
          '`$key` must be one of ${values.map((v) => v.name).join(', ')}',
        ),
      );
    }

    final namespaces = <NamespaceConfig>[];
    final rawNamespaces = read<Map<Object?, Object?>>('namespaces') ?? {};
    for (final entry in rawNamespaces.entries) {
      final name = entry.key.toString();
      final value = entry.value;
      final String package;
      String? className;
      String? import;
      if (value is String) {
        package = value;
      } else if (value is Map) {
        package = value['package']?.toString() ??
            (throw KumaConfigException('namespace `$name` needs a `package`'));
        className = value['class']?.toString();
        import = value['import']?.toString();
      } else {
        throw KumaConfigException('namespace `$name` must be a map or string');
      }
      namespaces.add(
        NamespaceConfig(
          name: name,
          package: package,
          className: className ?? '${pascalCase(name)}Translations',
          import: import ?? 'package:$package/l10n/translations.g.dart',
        ),
      );
    }

    final microApps = <MicroAppConfig>[];
    final rawApps = read<Map<Object?, Object?>>('micro_apps') ?? {};
    for (final entry in rawApps.entries) {
      final id = entry.key.toString();
      final value = entry.value ?? const <Object?, Object?>{};
      if (value is! Map) {
        throw KumaConfigException('micro app `$id` must be a map');
      }
      final own = <String, Object?>{
        for (final e in value.entries) e.key.toString(): _plain(e.value),
      };
      for (final key in const ['role', 'namespaces', 'micro_apps']) {
        if (own.containsKey(key)) {
          throw KumaConfigException(
            'micro app `$id` can not set `$key`',
          );
        }
      }
      final name = pascalCase(id);
      try {
        microApps.add(
          MicroAppConfig(
            id: id,
            config: KumaConfig.fromMap({
              'input_dir': 'assets/translations/$id',
              'output': 'lib/micro_apps/$id/l10n/translations.g.dart',
              'class_name': '${name}Translations',
              'context_getter': 'T',
              'key_prefix': id,
              'warnings_as_errors': map['warnings_as_errors'],
              ...own,
            }),
          ),
        );
      } on KumaConfigException catch (e) {
        throw KumaConfigException('micro app `$id`: ${e.message}');
      }
    }

    final paramNames = <String, List<String>>{};
    final rawParams = read<Map<Object?, Object?>>('param_names') ?? {};
    for (final entry in rawParams.entries) {
      final value = entry.value;
      if (value is! List) {
        throw KumaConfigException(
          '`param_names.${entry.key}` must be a list of names',
        );
      }
      paramNames[entry.key.toString()] = [for (final v in value) v.toString()];
    }

    const defaults = KumaConfig();
    return KumaConfig(
      role: enumValue('role', KumaRole.values) ?? defaults.role,
      inputDir: read<String>('input_dir') ?? defaults.inputDir,
      baseLocale: read<String>('base_locale') ?? defaults.baseLocale,
      locales: stringList('locales'),
      output: read<String>('output') ?? defaults.output,
      className: read<String>('class_name') ?? defaults.className,
      contextExtension: read<bool>('context_extension'),
      contextGetter: read<String>('context_getter') ?? defaults.contextGetter,
      keyPrefix: read<String>('key_prefix'),
      namespaces: namespaces,
      microApps: microApps,
      pluralRules: enumValue('plural_rules', PluralRulesMode.values) ??
          defaults.pluralRules,
      strictPluralForms:
          stringList('strict_plural_forms') ?? defaults.strictPluralForms,
      pluralCount: {
        for (final e
            in (read<Map<Object?, Object?>>('plural_count') ?? {}).entries)
          e.key.toString(): e.value.toString(),
      },
      paramNames: paramNames,
      allowPositionalArgs:
          read<bool>('allow_positional_args') ?? defaults.allowPositionalArgs,
      missingKey: enumValue('missing_key', MissingKeyPolicy.values) ??
          defaults.missingKey,
      exclude: stringList('exclude') ?? defaults.exclude,
      overlap: enumValue('overlap', OverlapPolicy.values) ?? defaults.overlap,
      allowOverlap: stringList('allow_overlap') ?? defaults.allowOverlap,
      digitPrefix: read<String>('digit_prefix') ?? defaults.digitPrefix,
      warningsAsErrors:
          read<bool>('warnings_as_errors') ?? defaults.warningsAsErrors,
      source: map,
    );
  }

  /// Reads `kuma.yaml` content, or the `kuma:` section of a pubspec.
  static KumaConfig? fromYaml(String source, {bool isPubspec = false}) {
    final doc = loadYaml(source);
    if (doc == null) return const KumaConfig();
    if (doc is! Map) throw KumaConfigException('expected a YAML map');
    if (isPubspec) {
      final section = doc['kuma'];
      if (section == null) return null;
      if (section is! Map) {
        throw KumaConfigException('`kuma:` in pubspec.yaml must be a map');
      }
      return KumaConfig.fromMap(section);
    }
    final section = doc['kuma'];
    return KumaConfig.fromMap(section is Map ? section : doc);
  }

  /// Applies option overrides (builder options, CLI flags) on top of the
  /// options this config was read from.
  KumaConfig overlay(Map<String, Object?> overrides) {
    if (overrides.isEmpty) return this;
    return KumaConfig.fromMap({...source, ...overrides});
  }
}

enum MissingKeyPolicy { error, warning }

/// How `overlap` problems are reported. `ignore` turns the check off.
enum OverlapPolicy { error, warning, ignore }

Object? _plain(Object? value) {
  if (value is Map) {
    return {for (final e in value.entries) e.key.toString(): _plain(e.value)};
  }
  if (value is List) return [for (final v in value) _plain(v)];
  return value;
}

/// `lib/l10n/translations.g.dart` → `lib/l10n/translations.kuma.json`.
String manifestPathFor(String dartPath) =>
    '${dartPath.replaceFirst(RegExp(r'\.g\.dart$|\.dart$'), '')}.kuma.json';
