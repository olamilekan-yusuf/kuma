import 'package:kuma/kuma.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('valid files produce no diagnostics and an output', () async {
    final result = await run({
      'en': {
        'hi': 'Hi {name}',
        'items': {'one': '{} item', 'other': '{} items'}
      },
      'pt': {
        'hi': 'Olá {name}',
        'items': {'one': '{} item', 'other': '{} itens'}
      },
    });
    expect(result.diagnostics, isEmpty);
    expect(result.outputs.keys, ['lib/l10n/translations.g.dart']);
  });

  group('missing keys', () {
    test('are checked against the union of all locales', () async {
      final result = await run({
        'en': {'a': 'A'},
        'pt': {'a': 'A', 'b': 'B'},
        'es': {'b': 'B'},
      });
      expect(summary(result), ['missing es a', 'missing en b']);
      expect(result.hasErrors, isTrue);
      expect(result.outputs, isEmpty);
    });

    test('only the highest missing ancestor is reported', () async {
      final result = await run({
        'en': {
          'home': {'title': 'T', 'body': 'B'}
        },
        'pt': {},
      });
      expect(summary(result), ['missing pt home']);
    });

    test('can be downgraded to warnings', () async {
      final result = await run(
        {
          'en': {'a': 'A'},
          'pt': {}
        },
        config: KumaConfig.fromMap({'missing_key': 'warning'}),
      );
      expect(summary(result, Severity.warning), ['missing pt a']);
      expect(result.hasErrors, isFalse);
    });
  });

  test('kind mismatch', () async {
    final result = await run({
      'en': {
        'items': {'one': '1', 'other': 'n'}
      },
      'pt': {'items': 'itens'},
    });
    expect(summary(result), ['kind pt items']);
  });

  group('placeholders', () {
    test('named mismatch', () async {
      final result = await run({
        'en': {'date': '{dayOrdinal} {monthYear}'},
        'pt': {'date': '{day} {monthYear}'},
      });
      expect(summary(result), ['placeholder pt date']);
      expect(
        result.diagnostics.single.message,
        'en={dayOrdinal} {monthYear}  pt={day} {monthYear}',
      );
    });

    test('positional count mismatch', () async {
      final result = await run({
        'en': {'resendIn': 'Resend in {}'},
        'es': {'resendIn': 'Reenviar'},
      });
      expect(summary(result), ['placeholder es resendIn']);
    });

    test('plurals compare the max {} over forms', () async {
      final result = await run({
        'en': {
          'x': {'one': '1 blessing', 'other': '{}% · {} blessings'}
        },
        'pt': {
          'x': {'one': '{}% · 1', 'other': '{}% · {}'}
        },
      });
      expect(result.diagnostics, isEmpty);
    });
  });

  group('plural forms (fallback rules)', () {
    test('missing other is an error', () async {
      final result = await run({
        'en': {
          'x': {'one': 'one'}
        },
      });
      expect(summary(result, Severity.error), ['plural en x']);
    });

    test('missing one is a warning', () async {
      final result = await run({
        'en': {
          'x': {'zero': 'none', 'other': 'n'}
        },
      });
      expect(summary(result, Severity.warning), ['plural en x']);
    });

    test('few and many are never selected', () async {
      final result = await run({
        'en': {
          'x': {'one': '1', 'many': 'lots', 'other': 'n'}
        },
      });
      expect(summary(result, Severity.info), ['plural en x']);
    });

    test('cldr mode expects language forms', () async {
      final result = await run(
        {
          'en': {
            'x': {'one': '1', 'other': 'n'}
          },
          'pt': {
            'x': {'one': '1', 'other': 'n'}
          },
        },
        config: KumaConfig.fromMap({'plural_rules': 'cldr'}),
      );
      expect(summary(result, Severity.warning), ['plural pt x']);
    });
  });

  group('locales', () {
    test('base locale must exist', () async {
      final result = await run({
        'pt': {'a': 'A'}
      });
      expect(summary(result), ['locale en -']);
    });

    test('configured locales must exist; extras are skipped', () async {
      final result = await run(
        {
          'en': {'a': 'A'},
          'fr': {'b': 'B'},
        },
        config: KumaConfig.fromMap({
          'locales': ['en', 'pt'],
        }),
      );
      expect(summary(result), ['locale pt -', 'locale fr -']);
    });

    test('file names map to locales', () async {
      final result = await runKuma(
        const KumaConfig(baseLocale: 'pt-BR'),
        MemoryInputs({'pt_BR.json': '{"a": "A"}', 'notes.txt': ''}),
      );
      expect(result.diagnostics, isEmpty);
    });
  });

  test('warnings_as_errors promotes warnings', () async {
    final result = await run(
      {
        'en': {'x': '{} and {name}'},
      },
      config: KumaConfig.fromMap({'warnings_as_errors': true}),
    );
    expect(summary(result, Severity.error), ['mixed-args en x']);
  });

  test('links are reported', () async {
    final result = await run({
      'en': {'a': 'A', 'b': '@:a'},
    });
    expect(summary(result), ['link en b']);
  });
}
