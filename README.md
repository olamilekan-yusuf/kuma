# kuma

Type-safe accessors and cross-locale validation for [easy_localization](https://pub.dev/packages/easy_localization) JSON files.

easy_localization stays the runtime: it still loads the JSON, switches locales and resolves plurals. kuma reads the same files, checks them against each other, and generates a thin typed layer over `tr()` and `plural()`:

```dart
Text(context.t.retry);                       // was context.localize('retry')
Text(context.t.episodeCount(n));             // was plural('episodeCount', n, namedArgs: {'count': '$n'})
Text(context.t.resendIn('0:30'));            // was 'resendIn'.tr(args: ['0:30'])
Text(context.t.core.pleaseCheckYourInternetConnectionAndTryAgain);  // a package's keys

final label = Translations.instance.itemCount(3);   // outside widgets
```

## Setup

```yaml
# pubspec.yaml
dev_dependencies:
  kuma:
    git:
      url: git@github.com:Yohanna-Foundation/kuma.git
```

Add a `kuma.yaml` next to `pubspec.yaml`, or a `kuma:` section in `pubspec.yaml`. Every option has a default, so an empty config works.

Then do either of the following:

- **build_runner.** `dart run build_runner build` (or `watch`). The builder applies to the root package automatically, and `assets/**` is a default build source, so no `build.yaml` is needed.
- **CLI.** `dart run kuma generate` to validate and write, or `dart run kuma check` to validate only.

Both run the same pipeline. Errors stop generation: the CLI exits with `1`, and the builder fails the build.

```
read JSON → parse → validate across locales → check namespace packages → generate
```

## What it checks

| Severity | Code | Meaning |
|---|---|---|
| error | `missing` | Key absent in a locale. The key set is the union over all locales. |
| error | `kind` | Key is a string in one locale and a plural or namespace in another |
| error | `placeholder` | `{name}`s, or the number of `{}`, differ between locales |
| error | `plural` | Plural without `other` |
| error | `unreachable` | Key contains `.`, which easy_localization splits on |
| error | `collision` | Two keys map to the same Dart name (`genesis` / `Genesis`) |
| error | `plural-count` | kuma can't tell which placeholder is the count; set `plural_count` |
| error | `overlap` | Same key in this package and a namespace package, or in two packages |
| error | `namespace` / `stale` | Namespace package manifest missing, wrong class, or older than its JSON |
| error | `stale-output` | `check` with `role: package`: committed output is out of date |
| warning | `plural` | A form the plural rules expect is missing, e.g. `one` |
| warning | `mixed-args` | `{}` and `{name}` in one string |
| warning | `link` | `@:` links aren't resolved, so linked placeholders aren't typed |
| warning | `locale` | A file exists for a locale not in `locales` |
| info | `plural` | Forms that can never be selected under the configured rules |

## Generated signatures

| JSON | Dart |
|---|---|
| `"Retry"` | `String get retry` |
| `"Hello {name}"` | `String greeting({required String name})` |
| `"Resend in {}"` | `String resendIn(String arg0)`. Name it via `param_names`. |
| plural with one `{}` | `String itemCount(num count, {NumberFormat? format})`. The count fills `{}`. |
| plural with one `{name}` | `String episodeCount(num count, {NumberFormat? format})`. Passes `name: 'count'`. |
| plural with 2+ `{}` | `String x(num count, String arg0, String arg1)`. easy_localization stops auto-filling the count once `args` is passed. |
| plural with no placeholders | `String hrs(num count)` |
| nested map | `HomeTranslations get home` |

Key strings passed to `tr()` are always the original JSON paths. kuma never passes `args: []`, because easy_localization treats an empty list as "args given" and leaves `{}` unfilled.

## Packages and namespaces

A library that ships translations sets `role: package`. It then generates its class with a `static const instance` but no `BuildContext` extension, plus a manifest (`translations.kuma.json`) listing its keys and a fingerprint of its JSON. The generated file and the manifest must reach consumers, either committed or added by the release tag.

The app maps each package to a namespace:

```yaml
namespaces:
  core: { package: praises_core, class: CoreTranslations }
```

That generates `context.t.core`. The app reads each manifest from the package's `lib/`, which both build_runner and the CLI can read. It fails when the app and a package define the same key, because easy_localization merges all loaders into one map and one source would silently win. `kuma check` also compares the manifest fingerprint with the package's JSON. build_runner can't read another package's assets, so the builder skips that comparison.

### Example: a package with its own strings

[`example/`](example/) is a working pair: `demo_haptics` is a package that ships translations, and `demo_app` consumes it. A package like `yohanna_haptics` needs this only if it owns UI text. One without translation files needs nothing.

```
example/
  demo_haptics/                  # role: package
    kuma.yaml                    #   role: package, class_name: HapticsTranslations
    assets/translations/{en,es}.json
    lib/l10n/translations.g.dart #   generated, committed
    lib/l10n/translations.kuma.json
  demo_app/                      # role: app
    kuma.yaml                    #   namespaces: { haptics: { package: demo_haptics, class: HapticsTranslations } }
    assets/translations/{en,es}.json
    lib/l10n/translations.g.dart #   generated; context.t.haptics.* forwards to the package
```

Run order, from the repo root:

```bash
cd example/demo_haptics && dart pub get && dart run kuma generate   # 1. package first, then commit lib/l10n/
cd ../demo_app          && dart pub get && dart run kuma generate   # 2. app reads the package's manifest
```

In the app:

```dart
Text(context.t.settings);                         // app key
Text(context.t.haptics.hapticsEnabled);           // package key
Text(context.t.haptics.intensity(level: 'High')); // package key with a placeholder
Text(context.t.haptics.patternCount(3));          // package plural
Translations.instance.haptics.hapticsEnabled;     // outside widgets
```

What `dart run kuma check` catches in the app:

| You do | Result |
|---|---|
| Edit the package's JSON and don't regenerate it | `stale` in the app, `stale-output` in the package |
| Define `hapticsEnabled` in the app's JSON too | `overlap` |
| Change the package's `class_name` | `namespace` (the app expects `HapticsTranslations`) |

The example's generated code needs `easy_localization` and Flutter to compile. The example pubspecs only contain what kuma needs to run, and the folder is excluded from analysis.

### Allowing overlap

easy_localization merges every loader into one map, so a key defined in the app and a package (or in two packages, or a micro-app) silently resolves to whichever loads last. kuma reports that as an `overlap` error. To permit known cases, list them:

```yaml
allow_overlap:
  - somethingWentWrongPleaseTryAgain
  - "unauthorized*"
```

Only the listed keys are skipped, so new overlaps are still caught. For a migration period, `overlap: warning` reports every overlap as a warning instead (an error again with `warnings_as_errors`), and `overlap: ignore` turns the check off. Both options can be combined: listed keys are skipped, the rest follow `overlap`. Which definition wins at runtime is still decided by loader order, so prefer removing the duplicate.

## Micro-apps

A micro-app that ships its own translation files gets its own generated class. List it under `micro_apps`, keyed by its id:

```yaml
micro_apps:
  kids:
    locales: [en]
```

Defaults for the id `kids`:

| Option | Default |
|---|---|
| `input_dir` | `assets/translations/kids` |
| `output` | `lib/micro_apps/kids/l10n/translations.g.dart` |
| `class_name` | `KidsTranslations` |
| `context_getter` | `T` |
| `key_prefix` | `kids` |

Any option except `role`, `namespaces` and `micro_apps` can be set per micro-app. `warnings_as_errors` is inherited.

Each micro-app is read, validated and generated on its own, so its locales don't have to match the app's. easy_localization merges every loader into one map, so the generated code prefixes each key with `key_prefix`: `String get kidsHome => tr('kids.kidsHome')`, used as `context.T.kidsHome`. That is the same key a scoped `context.localize('kidsHome')` resolves to. A root object named like the prefix (`{"kids": {"kidsHome": "…"}}`) is unwrapped first, so a nested and a flat file give the same getters. `exclude`, `param_names` and `plural_count` use the key without the prefix. The app's `input_dir` is not read recursively, so `kids/en.json` is never mistaken for a second `en` locale of the app.

The micro-app's keys join the overlap check: an `overlap` error is raised if the app (or a package) defines a key the micro-app also defines. Diagnostics from a micro-app are prefixed with `[kids]`.

## Config

| Option | Default | |
|---|---|---|
| `role` | `app` | `app` or `package` |
| `input_dir` | `assets/translations` | |
| `base_locale` | `en` | Source of doc comments and signatures |
| `locales` | all files | Expected locales. Extra files warn and are skipped. |
| `output` | `lib/l10n/translations.g.dart` | |
| `class_name` | `Translations` | |
| `context_extension` | `true` for apps | Generates `context.<context_getter>` |
| `context_getter` | `t` | |
| `key_prefix` | none (the id for micro-apps) | Prepended to every key the generated code looks up. A same-named root object in the JSON is unwrapped. |
| `namespaces` | `{}` | `name: {package, class, import}` |
| `micro_apps` | `{}` | `id: {…options}`. See [Micro-apps](#micro-apps). |
| `plural_rules` | `fallback` | `fallback` (easy_localization's default `ignorePluralRules: true`: 0/1/2/other), `cldr`, `strict` |
| `strict_plural_forms` | `[one, other]` | For `strict` |
| `plural_count` | `{}` | Per-key count placeholder, or `none` |
| `param_names` | `{}` | Per-key names for `{}` arguments |
| `allow_positional_args` | `true` | |
| `missing_key` | `error` | or `warning` |
| `exclude` | `[]` | Globs over key paths (`*`, `?`, `[...]`). Validated but not generated. |
| `overlap` | `error` | How a key defined in two sources is reported: `error`, `warning` or `ignore` (check off). |
| `allow_overlap` | `[]` | Globs over runtime key paths that may be defined in more than one source. Skipped by the check. |
| `digit_prefix` | `n` | `1Samuel` → `n1Samuel` |
| `warnings_as_errors` | `false` | Also `--warnings-as-errors` |

### Every option

```yaml
# kuma.yaml (or a `kuma:` section in pubspec.yaml)
role: app                          # app | package
input_dir: assets/translations     # *.json, one file per locale; not recursive
base_locale: en                    # source of doc comments and signatures
locales: [en, es, pt]              # omit to use every file found
output: lib/l10n/translations.g.dart
class_name: Translations
context_extension: true            # default: true for app, false for package
context_getter: t                  # context.t
key_prefix: kids                   # prepended to looked-up keys; see Micro-apps

namespaces:                        # other packages' generated classes
  core: { package: praises_core, class: CoreTranslations }
  feature:
    package: praises_feature_impl
    class: FeatureTranslations
    import: package:praises_feature_impl/l10n/translations.g.dart

micro_apps:                        # same options as above, minus role,
  kids:                            # namespaces and micro_apps
    input_dir: assets/translations/kids
    output: lib/micro_apps/kids/l10n/translations.g.dart
    class_name: KidsTranslations
    context_getter: T
    key_prefix: kids
    locales: [en]

plural_rules: fallback             # fallback | cldr | strict
strict_plural_forms: [one, other]  # for strict
plural_count:                      # per-key count placeholder, or none
  itemCount: count
  hrs: none
param_names:                       # names for positional {} arguments
  resendIn: [time]
allow_positional_args: true
missing_key: error                 # error | warning
exclude:                           # globs over key paths, validated only
  - Genesis
  - "[1-3]*"
overlap: error                     # error | warning | ignore
allow_overlap:                     # keys that may exist in two sources
  - somethingWentWrongPleaseTryAgain
  - "unauthorized*"
digit_prefix: n                    # 1Samuel -> n1Samuel
warnings_as_errors: false
```

The CLI also accepts `--config <file>`, `--root <dir>`, `--format text|json`, `--warnings-as-errors` and `--verbose`.

Builder options in `build.yaml` override the file. `config: path.yaml` points at another config file.

Example configs for the Yohanna apps are in [`presets/`](presets/).

## Development

```bash
dart test
```

To refresh golden files, run `UPDATE_GOLDENS=1 dart test`. `test/fixtures/yohanna/` is trimmed from the real app files and keeps every issue kuma was built to catch.
