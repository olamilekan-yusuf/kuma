import 'package:kuma/kuma.dart';
import 'package:test/test.dart';

void main() {
  test('defaults', () {
    const config = KumaConfig();
    expect(config.inputDir, 'assets/translations');
    expect(config.pluralRules, PluralRulesMode.fallback);
    expect(config.contextExtension, isTrue);
    expect(config.missingKey, MissingKeyPolicy.error);
  });

  test('packages default to no context extension', () {
    final config = KumaConfig.fromMap({'role': 'package'});
    expect(config.contextExtension, isFalse);
    expect(config.manifestOutput, 'lib/l10n/translations.kuma.json');
  });

  test('reads kuma.yaml and the pubspec section', () {
    final yaml = KumaConfig.fromYaml('''
output: lib/app/l10n/translations.g.dart
exclude: ["[1-3]*"]
param_names:
  resendIn: [time]
namespaces:
  core: { package: praises_core, class: CoreTranslations }
  feature: praises_feature_impl
''')!;
    expect(yaml.output, 'lib/app/l10n/translations.g.dart');
    expect(yaml.paramNames, {
      'resendIn': ['time'],
    });
    expect(yaml.namespaces.first.import,
        'package:praises_core/l10n/translations.g.dart');
    expect(
        yaml.namespaces.first.manifestPath, 'lib/l10n/translations.kuma.json');
    expect(yaml.namespaces.last.className, 'FeatureTranslations');

    final pubspec = KumaConfig.fromYaml(
      'name: app\nkuma:\n  base_locale: pt\n',
      isPubspec: true,
    )!;
    expect(pubspec.baseLocale, 'pt');
    expect(KumaConfig.fromYaml('name: app\n', isPubspec: true), isNull);
  });

  test('unknown options and bad values are rejected', () {
    expect(() => KumaConfig.fromMap({'outptu': 'x'}),
        throwsA(isA<KumaConfigException>()));
    expect(() => KumaConfig.fromMap({'plural_rules': 'nope'}),
        throwsA(isA<KumaConfigException>()));
    expect(() => KumaConfig.fromMap({'exclude': 'x'}),
        throwsA(isA<KumaConfigException>()));
  });

  test('overlay applies builder options', () {
    final config = const KumaConfig().overlay({'warnings_as_errors': true});
    expect(config.warningsAsErrors, isTrue);
  });
}
