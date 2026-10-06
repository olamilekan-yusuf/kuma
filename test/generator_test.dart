import 'package:kuma/kuma.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<String> generate(
  Map<String, Object?> en, {
  Map<String, Object?> config = const {},
}) async {
  final result = await run({'en': en}, config: KumaConfig.fromMap(config));
  expect(
    result.diagnostics.where((d) => d.severity == Severity.error),
    isEmpty,
  );
  // Collapse whitespace so assertions don't depend on line wrapping.
  return result.outputs['lib/l10n/translations.g.dart']!
      .replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  group('messages', () {
    test('plain strings are getters', () async {
      expect(
        await generate({'retry': 'Retry'}),
        contains("String get retry => el.tr('retry');"),
      );
    });

    test('named placeholders are required named params', () async {
      expect(
        await generate({'hi': 'Hi {name}'}),
        contains(
          "String hi({required String name}) => "
          "el.tr('hi', namedArgs: {'name': name});",
        ),
      );
    });

    test('positional placeholders are argN, or param_names', () async {
      expect(
        await generate({'words': '{} / {} words'}),
        contains("el.tr('words', args: [arg0, arg1])"),
      );
      expect(
        await generate(
          {'resendIn': 'Resend in {}'},
          config: {
            'param_names': {
              'resendIn': ['time'],
            },
          },
        ),
        contains(
          "String resendIn(String time) => el.tr('resendIn', args: [time]);",
        ),
      );
    });

    test('reserved-word placeholders are renamed, keys are not', () async {
      expect(
        await generate({'k': 'In {class}'}),
        contains("namedArgs: {'class': class_}"),
      );
    });
  });

  group('plural count detection', () {
    Future<String> plural(Map<String, String> forms,
            {Map<String, Object?> config = const {}}) =>
        generate({'p': forms}, config: config);

    test('single {} is the count, and args is never passed', () async {
      final out = await plural({'one': '{} Item', 'other': '{} Items'});
      expect(out, contains('String p(num count, {el.NumberFormat? format})'));
      expect(out, contains("el.plural('p', count, format: format)"));
      expect(out, isNot(contains('args:')));
    });

    test('single named placeholder is the count via name:', () async {
      final out =
          await plural({'one': '{number} sec', 'other': '{number} secs'});
      expect(out,
          contains("el.plural('p', count, name: 'number', format: format)"));
    });

    test('several {} become explicit args and the count is not printed',
        () async {
      final out = await plural({
        'one': '{}% complete · Earn 1 blessing',
        'other': '{}% complete · Earn {} blessings',
      });
      expect(out, contains('String p(num count, String arg0, String arg1)'));
      expect(out, contains("el.plural('p', count, args: [arg0, arg1])"));
    });

    test('no placeholders: the count only selects the form', () async {
      final out = await plural({'one': 'Hr', 'other': 'Hrs'});
      expect(out, contains("String p(num count) => el.plural('p', count);"));
    });

    test('a {} count plus other named placeholders', () async {
      final out = await plural(
          {'one': '{user}: {} message', 'other': '{user}: {} messages'});
      expect(
        out,
        contains(
            "el.plural('p', count, namedArgs: {'user': user}, format: format)"),
      );
    });

    test('several named placeholders need plural_count', () async {
      final result = await run({
        'en': {
          'p': {'one': '{a} {b}', 'other': '{a} {b}s'},
        },
      });
      expect(summary(result), ['plural-count - p']);

      final out = await plural(
        {'one': '{a} {b}', 'other': '{a} {b}s'},
        config: {
          'plural_count': {'p': 'b'},
        },
      );
      expect(out, contains("name: 'b', namedArgs: {'a': a}"));
    });

    test('a placeholder called count does not clash with the count param',
        () async {
      final out =
          await plural({'one': '{} of {count}', 'other': '{} of {count}'});
      expect(out, contains('String p(num count2, {required String count'));
    });
  });

  group('naming', () {
    test('collisions are errors', () async {
      final result = await run({
        'en': {'genesis': 'g', 'Genesis': 'G'},
      });
      expect(summary(result), ['collision - Genesis']);
    });

    test('excluded keys are validated but not generated', () async {
      final out = await generate(
        {'1Samuel': '1 Samuel', 'retry': 'Retry'},
        config: {
          'exclude': ['[1-3]*'],
        },
      );
      expect(out, isNot(contains('Samuel')));
      expect(out, contains('retry'));
    });

    test('digit-leading keys get the prefix but keep their key', () async {
      expect(
        await generate({'1Samuel': '1 Samuel'}),
        contains("String get n1Samuel => el.tr('1Samuel');"),
      );
    });

    test('generated member names are protected', () async {
      expect(
        await generate({'instance': 'x', 'toString': 'y'}),
        allOf(contains('get instance_'), contains('get toString_')),
      );
    });
  });

  test('context extension only for apps', () async {
    expect(
      await generate({'a': 'A'}),
      contains('extension TranslationsContextX on BuildContext'),
    );
    final pkg = await generate(
      {'a': 'A'},
      config: {'role': 'package', 'class_name': 'CoreTranslations'},
    );
    expect(pkg, isNot(contains('BuildContext')));
    expect(pkg, isNot(contains('flutter/widgets.dart')));
    expect(pkg, contains('static const instance = CoreTranslations._();'));
  });
}
