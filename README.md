# kuma

kuma turns your [easy_localization](https://pub.dev/packages/easy_localization) JSON files into typed Dart getters and fails the build when the files disagree with each other.

easy_localization keeps doing the runtime work. It loads the JSON, switches locales and picks plural forms. kuma reads the same files, checks them, and writes a small class that calls `tr()` and `plural()` for you.

```dart
// before
Text(context.localize('retry'));
Text(plural('episodeCount', n, namedArgs: {'count': '$n'}));
Text('resendIn'.tr(args: ['0:30']));

// after
Text(context.t.retry);
Text(context.t.episodeCount(n));
Text(context.t.resendIn('0:30'));
Text(context.t.core.pleaseCheckYourInternetConnectionAndTryAgain); // key from another package

final label = Translations.instance.itemCount(3); // outside the widget tree
```

A typo in a key, a missing argument or a Spanish file that lacks a key now breaks the build instead of showing a raw key string to a user.

## Quick start

Add kuma as a dev dependency:

```yaml
# pubspec.yaml
dev_dependencies:
  kuma:
    git:
      url: git@github.com:Yohanna-Foundation/kuma.git
```

Put a `kuma.yaml` next to `pubspec.yaml`, or a `kuma:` section inside `pubspec.yaml`. Every option has a default, so an empty file works. Then generate with either tool:

```bash
dart run build_runner build   # or `watch`
dart run kuma generate        # validate, then write
dart run kuma check           # validate only
```

Both run the same steps and stop on the first failed one:

```
read JSON → parse → validate across locales → check namespace packages → generate
```

With errors, the CLI exits with `1` and build_runner fails the build. build_runner needs no `build.yaml`, because the builder applies to the root package and `assets/**` is already a build source.

To call `kuma` without `dart run`, activate it once. Edits to a local checkout apply on the next run.

```bash
dart pub global activate --source path ~/projects/kuma
export PATH="$PATH:$HOME/.pub-cache/bin"
```

## What gets generated

| JSON | Dart |
|---|---|
| `"Retry"` | `String get retry` |
| `"Hello {name}"` | `String greeting({required String name})` |
| `"Resend in {}"` | `String resendIn(String arg0)`. Name the argument with `param_names`. |
| plural with one `{}` | `String itemCount(num count, {NumberFormat? format})`. The count fills `{}`. |
| plural with one `{name}` | `String episodeCount(num count, {NumberFormat? format})`. Passes `name: 'count'`. |
| plural with two or more `{}` | `String x(num count, String arg0, String arg1)`. easy_localization stops filling in the count once `args` is passed. |
| plural with no placeholder | `String hrs(num count)` |
| nested map | `HomeTranslations get home` |

The strings passed to `tr()` are the original JSON paths. kuma never passes `args: []`, because easy_localization treats an empty list as "args given" and leaves `{}` unfilled.

## What it checks

| Severity | Code | Meaning |
|---|---|---|
| error | `missing` | A key is absent in a locale. The key set is the union over all locales. |
| error | `kind` | A key is a string in one locale and a plural or namespace in another. |
| error | `placeholder` | The `{name}`s, or the number of `{}`, differ between locales. |
| error | `plural` | A plural has no `other`. |
| error | `unreachable` | A key contains `.`, which easy_localization splits on. |
| error | `collision` | Two keys map to the same Dart name, like `genesis` and `Genesis`. |
| error | `plural-count` | kuma can't tell which placeholder is the count. Set `plural_count`. |
| error | `overlap` | The same key exists in two sources. See [Overlapping keys](#overlapping-keys). |
| error | `namespace`, `stale` | A package manifest is missing, names the wrong class, or is older than its JSON. |
| error | `stale-output` | With `role: package`, `check` found committed output that is out of date. |
| error | `config` | Two runs write to the same output file. |
| warning | `plural` | A form the plural rules expect is missing, like `one`. |
| warning | `mixed-args` | One string uses both `{}` and `{name}`. |
| warning | `link` | An `@:` link isn't resolved, so the linked placeholders aren't typed. |
| warning | `locale` | A file exists for a locale that isn't in `locales`. |
| info | `plural` | A form can never be selected under the configured rules. |

## Packages and namespaces

A library that ships its own strings sets `role: package`. kuma then writes two files into the library:

- a class with a `static const instance`, and no `BuildContext` extension
- `translations.kuma.json`, the manifest, with the library's key list and a fingerprint of its JSON

Commit the generated file and the manifest, or add them in the release tag. Consumers read both from the package's `lib/`.

The app maps each package to a name:

```yaml
namespaces:
  core: { package: praises_core, class: CoreTranslations }
```

kuma then adds `context.t.core`. For each namespace it also does the following:

1. Finds the package through `.dart_tool/package_config.json`.
2. Reads the manifest and checks that its class name matches `class`.
3. Compares the manifest's keys with the app's keys.
4. With the CLI, compares the manifest fingerprint with the package's current JSON. build_runner can only read another package's `lib/`, so the builder skips this step. Run `kuma check` in CI to cover it.

A package that has no translation files, like a native plugin, needs none of this.

### Example

[`example/`](example/) holds a package that owns strings (`demo_haptics`) and an app that uses it (`demo_app`).

```
example/
  demo_haptics/                    role: package
    kuma.yaml                      role: package, class_name: HapticsTranslations
    assets/translations/{en,es}.json
    lib/l10n/translations.g.dart   generated, committed
    lib/l10n/translations.kuma.json
  demo_app/                        role: app
    kuma.yaml                      namespaces: { haptics: { package: demo_haptics, class: HapticsTranslations } }
    assets/translations/{en,es}.json
    lib/l10n/translations.g.dart   generated, forwards context.t.haptics to the package
```

Generate the package first and commit its output. The app reads the manifest, so it goes second:

```bash
cd example/demo_haptics && dart pub get && dart run kuma generate
cd ../demo_app          && dart pub get && dart run kuma generate
```

In the app:

```dart
Text(context.t.settings);                         // the app's own key
Text(context.t.haptics.hapticsEnabled);           // a package key
Text(context.t.haptics.intensity(level: 'High')); // with a placeholder
Text(context.t.haptics.patternCount(3));          // a plural
Translations.instance.haptics.hapticsEnabled;     // outside widgets
```

What `kuma check` reports in the app when you break something:

| You do this | kuma reports |
|---|---|
| Edit the package's JSON and skip `generate` | `stale` in the app, `stale-output` in the package |
| Define `hapticsEnabled` in the app's JSON too | `overlap` |
| Rename the package's `class_name` | `namespace`, because the app expects `HapticsTranslations` |

The generated example code needs Flutter and `easy_localization` to compile. The example pubspecs hold only what kuma needs, and `analysis_options.yaml` skips the folder.

## Micro-apps

A micro-app that ships its own files under `assets/translations/<id>/` gets its own class. List it under `micro_apps`, keyed by id:

```yaml
micro_apps:
  kids:
    locales: [en]
```

For the id `kids`, the defaults are:

| Option | Default |
|---|---|
| `input_dir` | `assets/translations/kids` |
| `output` | `lib/micro_apps/kids/l10n/translations.g.dart` |
| `class_name` | `KidsTranslations` |
| `context_getter` | `T` |
| `key_prefix` | `kids` |

Set any option except `role`, `namespaces` and `micro_apps` per micro-app. `warnings_as_errors` carries over from the app.

easy_localization merges every loader into one map, so kuma prefixes each key with `key_prefix`:

```dart
String get kidsHome => el.tr('kids.kidsHome');   // generated
Text(context.T.kidsHome);                        // your code
```

That is the key a scoped `context.localize('kidsHome')` resolves to. If the JSON has a single root object with the same name as the prefix, kuma unwraps it, so `{"kids": {"kidsHome": "Kids mode"}}` and `{"kidsHome": "Kids mode"}` give the same getter.

Each micro-app is read, validated and generated by itself, so its locales don't have to match the app's. The app's `input_dir` is not read recursively, so `kids/en.json` is never taken for a second `en` locale of the app. Options like `exclude`, `param_names` and `plural_count` use the key without the prefix. Diagnostics from a micro-app start with `[kids]`.

## Overlapping keys

easy_localization merges all loaders into one map. If the app, a package or a micro-app define the same key, the loader that runs last wins and nothing tells you. kuma reports every such key as an `overlap` error, including the case where one source has a string and another has a namespace under the same name.

To allow known cases, list them:

```yaml
allow_overlap:
  - somethingWentWrongPleaseTryAgain
  - "unauthorized*"
```

Only the listed keys are skipped, so new overlaps still fail. During a migration you can also set `overlap: warning`, which reports each overlap as a warning, or `overlap: ignore`, which turns the check off. Combined with `allow_overlap`, listed keys are skipped and the rest follow `overlap`. Loader order still decides which value shows at runtime, so remove the duplicate when you can.

## Configuration

kuma reads `kuma.yaml`, then the `kuma:` section of `pubspec.yaml`, then falls back to defaults. This file sets everything:

```yaml
role: app                          # app | package
input_dir: assets/translations     # *.json, one file per locale, not recursive
base_locale: en                    # source of doc comments and signatures
locales: [en, es, pt]              # omit to use every file found
output: lib/l10n/translations.g.dart
class_name: Translations
context_extension: true            # default true for app, false for package
context_getter: t                  # context.t
key_prefix: kids                   # prepended to looked-up keys, see Micro-apps

namespaces:                        # generated classes from other packages
  core: { package: praises_core, class: CoreTranslations }
  feature:
    package: praises_feature_impl
    class: FeatureTranslations
    import: package:praises_feature_impl/l10n/translations.g.dart

micro_apps:                        # same options, minus role, namespaces, micro_apps
  kids:
    input_dir: assets/translations/kids
    output: lib/micro_apps/kids/l10n/translations.g.dart
    class_name: KidsTranslations
    context_getter: T
    key_prefix: kids
    locales: [en]

plural_rules: fallback             # fallback | cldr | strict
strict_plural_forms: [one, other]  # used by strict
plural_count:                      # per-key count placeholder, or none
  itemCount: count
  hrs: none
param_names:                       # names for positional {} arguments
  resendIn: [time]
allow_positional_args: true
missing_key: error                 # error | warning
exclude:                           # globs over key paths, validated but not generated
  - Genesis
  - "[1-3]*"
overlap: error                     # error | warning | ignore
allow_overlap:                     # keys that may exist in two sources
  - somethingWentWrongPleaseTryAgain
  - "unauthorized*"
digit_prefix: n                    # 1Samuel becomes n1Samuel
warnings_as_errors: false
```

| Option | Default | Notes |
|---|---|---|
| `role` | `app` | `app` or `package` |
| `input_dir` | `assets/translations` | |
| `base_locale` | `en` | Source of doc comments and signatures |
| `locales` | every file found | Extra files warn and are skipped |
| `output` | `lib/l10n/translations.g.dart` | |
| `class_name` | `Translations` | |
| `context_extension` | `true` for apps | Generates `context.<context_getter>` |
| `context_getter` | `t` | `T` for micro-apps |
| `key_prefix` | none | The id for micro-apps. Prepended to every key the generated code looks up. |
| `namespaces` | `{}` | `name: {package, class, import}` |
| `micro_apps` | `{}` | `id: {options}` |
| `plural_rules` | `fallback` | `fallback` matches easy_localization's default `ignorePluralRules: true` and knows 0, 1, 2 and other. `cldr` uses per-language rules. `strict` requires `strict_plural_forms`. |
| `strict_plural_forms` | `[one, other]` | Used by `strict` |
| `plural_count` | `{}` | Per-key count placeholder, or `none` |
| `param_names` | `{}` | Per-key names for `{}` arguments |
| `allow_positional_args` | `true` | |
| `missing_key` | `error` | `error` or `warning` |
| `exclude` | `[]` | Globs over key paths with `*`, `?` and `[...]` |
| `overlap` | `error` | `error`, `warning` or `ignore` |
| `allow_overlap` | `[]` | Globs over runtime key paths |
| `digit_prefix` | `n` | Prefix for names that start with a digit |
| `warnings_as_errors` | `false` | Same as `--warnings-as-errors` |

`exclude` is for keys you look up with a variable, like Bible book names. They keep the `context.localize(key)` call, and kuma still validates them.

Options in `build.yaml` override the file, and `config: path.yaml` points the builder at another file. The CLI takes `--config <file>`, `--root <dir>`, `--format text|json`, `--warnings-as-errors` and `--verbose`. Ready-made configs for the Yohanna apps and packages are in [`presets/`](presets/).

## Development

```bash
dart test
```

Run `UPDATE_GOLDENS=1 dart test` to rewrite the golden files. `test/fixtures/yohanna/` holds trimmed copies of the real app files and keeps every problem kuma was built to catch.
