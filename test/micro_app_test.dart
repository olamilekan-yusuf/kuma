import 'package:build_test/build_test.dart';
import 'package:kuma/builder.dart';
import 'package:kuma/kuma.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _adult = {
  'en.json': '{"retry": "Retry", "hello": "Hello {name}"}',
};
const _kids = {
  'en.json': '{"kids": {"kidsHome": "Kids mode"}}',
};

KumaConfig _config([Map<String, Object?> kids = const {}]) =>
    KumaConfig.fromMap({
      'micro_apps': {'kids': kids},
    });

MemoryInputs _inputs({
  Map<String, String> adult = _adult,
  Map<String, String> kids = _kids,
}) =>
    MemoryInputs(
      adult,
      dirFiles: {'assets/translations/kids': kids},
    );

void main() {
  group('config', () {
    test('defaults follow the PR layout', () {
      final app = _config().microApps.single;
      expect(app.id, 'kids');
      expect(app.config.inputDir, 'assets/translations/kids');
      expect(app.config.output, 'lib/micro_apps/kids/l10n/translations.g.dart');
      expect(app.config.className, 'KidsTranslations');
      expect(app.config.contextGetter, 'T');
      expect(app.config.keyPrefix, 'kids');
      expect(_config().outputs, [
        'lib/l10n/translations.g.dart',
        'lib/micro_apps/kids/l10n/translations.g.dart',
      ]);
    });

    test('options override the defaults', () {
      final app = _config({
        'output': 'lib/k.g.dart',
        'class_name': 'K',
        'locales': ['en', 'es'],
      }).microApps.single.config;
      expect(app.output, 'lib/k.g.dart');
      expect(app.className, 'K');
      expect(app.locales, ['en', 'es']);
    });

    test('rejects options a micro-app cannot have', () {
      expect(
        () => _config({'namespaces': {}}),
        throwsA(isA<KumaConfigException>()
            .having((e) => e.message, 'message', contains('micro app `kids`'))),
      );
    });

    test('reports unknown options with the app id', () {
      expect(
        () => _config({'bogus': 1}),
        throwsA(isA<KumaConfigException>()
            .having((e) => e.message, 'message', contains('micro app `kids`'))),
      );
    });
  });

  group('pipeline', () {
    test('generates one file per micro-app, keyed to the full path', () async {
      final result = await runKuma(_config(), _inputs());
      expect(result.hasErrors, isFalse);
      expect(result.outputs.keys, [
        'lib/micro_apps/kids/l10n/translations.g.dart',
        'lib/l10n/translations.g.dart',
      ]);
      final kids =
          result.outputs['lib/micro_apps/kids/l10n/translations.g.dart']!;
      expect(kids, contains("String get kidsHome => el.tr('kids.kidsHome');"));
      expect(kids, contains('KidsTranslations get T'));
      expect(kids, isNot(contains('KidsKids')));
      expect(result.outputs['lib/l10n/translations.g.dart'],
          isNot(contains('kidsHome')));
    });

    test('a flat file gets the same prefix', () async {
      final result = await runKuma(
        _config(),
        _inputs(kids: {'en.json': '{"kidsHome": "Kids mode"}'}),
      );
      expect(
        result.outputs['lib/micro_apps/kids/l10n/translations.g.dart'],
        contains("String get kidsHome => el.tr('kids.kidsHome');"),
      );
    });

    test('validates micro-app locales on their own', () async {
      final result = await runKuma(
        _config({
          'locales': ['en', 'es']
        }),
        _inputs(),
      );
      expect(result.hasErrors, isTrue);
      final error = result.diagnostics.single;
      expect(error.code, 'locale');
      expect(error.message, startsWith('[kids] '));
      expect(result.outputs, isEmpty);
    });

    test('an adult error stops micro-app output too', () async {
      final result = await runKuma(
        _config(),
        _inputs(adult: {'en.json': '{"a": "A"}', 'pt.json': '{}'}),
      );
      expect(result.hasErrors, isTrue);
      expect(result.outputs, isEmpty);
    });

    test('errors when adult redefines a micro-app key', () async {
      final result = await runKuma(
        _config(),
        _inputs(adult: {'en.json': '{"kids": {"kidsHome": "Other"}}'}),
      );
      expect(summary(result, Severity.error), ['overlap - kids.kidsHome']);
      expect(result.diagnostics.single.message, contains('micro-app:kids'));
    });

    test('errors when adult has a string where kids has a namespace', () async {
      final result = await runKuma(
        _config(),
        _inputs(adult: {'en.json': '{"kids": "Kids"}'}),
      );
      expect(summary(result, Severity.error), ['overlap - kids']);
    });

    test('two micro-apps can not share an output', () async {
      final config = KumaConfig.fromMap({
        'micro_apps': {
          'kids': {'output': 'lib/x.g.dart'},
          'teens': {'output': 'lib/x.g.dart'},
        },
      });
      final result = await runKuma(
        config,
        MemoryInputs(_adult, dirFiles: {
          'assets/translations/kids': _kids,
          'assets/translations/teens': {
            'en.json': '{"teens": {"home": "Home"}}',
          },
        }),
      );
      expect(summary(result, Severity.error), ['config - -']);
    });

    test('adult ignores files in a micro-app subdirectory', () async {
      // The root run reads `assets/translations` only; `kids/en.json` is not
      // handed to it, so it is not validated as a second `en` locale.
      final result = await runKuma(const KumaConfig(), _inputs());
      expect(result.hasErrors, isFalse);
      expect(result.outputs.keys, ['lib/l10n/translations.g.dart']);
    });
  });

  group('builder', () {
    test('writes every micro-app output', () async {
      final result = await testBuilder(
        KumaBuilder(_config()),
        {
          'app|assets/translations/en.json': '{"retry": "Retry"}',
          'app|assets/translations/kids/en.json':
              '{"kids": {"kidsHome": "Kids mode"}}',
        },
        rootPackage: 'app',
        outputs: {
          'app|lib/l10n/translations.g.dart': decodedMatches(contains('retry')),
          'app|lib/micro_apps/kids/l10n/translations.g.dart':
              decodedMatches(contains("el.tr('kids.kidsHome')")),
        },
      );
      expect(result.succeeded, isTrue);
    });
  });
}
