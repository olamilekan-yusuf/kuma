import 'dart:io';

import 'package:kuma/kuma.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Set `UPDATE_GOLDENS=1` to rewrite golden files.
final _update = Platform.environment['UPDATE_GOLDENS'] == '1';

const _coreJson = {
  'en': '{"retry": "Retry", "offline": "Check your connection"}',
  'pt': '{"retry": "Tentar", "offline": "Verifique sua conexão"}',
};

/// Generates praises_core as a package and returns its outputs.
Future<KumaResult> _core() => runKuma(
      KumaConfig.fromMap({
        'role': 'package',
        'class_name': 'CoreTranslations',
      }),
      MemoryInputs({
        for (final e in _coreJson.entries) '${e.key}.json': e.value,
      }),
    );

final _appConfig = KumaConfig.fromMap({
  'output': 'lib/app/l10n/translations.g.dart',
  'namespaces': {
    'core': {'package': 'praises_core', 'class': 'CoreTranslations'},
  },
  'param_names': {
    'resendIn': ['time'],
  },
});

Future<KumaResult> _app(
  Map<String, Object?> en, {
  Map<String, String>? coreManifest,
  Map<String, String>? coreJsonNow,
}) async {
  final core = await _core();
  return runKuma(
    _appConfig,
    MemoryInputs(
      jsonFiles({'en': en}),
      packageFiles: {
        'praises_core': coreManifest ??
            {
              'lib/l10n/translations.kuma.json':
                  core.outputs['lib/l10n/translations.kuma.json']!,
            },
      },
      packageJson: coreJsonNow == null ? null : {'praises_core': coreJsonNow},
    ),
  );
}

void main() {
  test('a package writes its generated file and a manifest', () async {
    final core = await _core();
    expect(core.diagnostics, isEmpty);
    expect(core.outputs.keys, [
      'lib/l10n/translations.g.dart',
      'lib/l10n/translations.kuma.json',
    ]);
    final manifest = KumaManifest.decode(
      core.outputs['lib/l10n/translations.kuma.json']!,
    );
    expect(manifest.className, 'CoreTranslations');
    expect(manifest.keys, ['retry', 'offline']);
    expect(manifest.locales, ['en', 'pt']);
  });

  test('the app exposes package namespaces through prefixed imports', () async {
    final result = await _app({'hello': 'Hello'});
    expect(result.diagnostics, isEmpty);
    final out = result.outputs['lib/app/l10n/translations.g.dart']!
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(
      out,
      contains(
        "import 'package:praises_core/l10n/translations.g.dart' as kuma_core;",
      ),
    );
    expect(
      out,
      contains(
        'kuma_core.CoreTranslations get core => '
        'kuma_core.CoreTranslations.instance;',
      ),
    );
  });

  test('a key defined in the app and a package is an error', () async {
    final result = await _app({'retry': 'Retry'});
    expect(summary(result), ['overlap - retry']);
  });

  test('a string in one source and a namespace in another is an error',
      () async {
    final result = await _app({
      'retry': {'title': 'Retry'},
    });
    expect(summary(result), contains('overlap - retry'));
  });

  test('two packages defining the same key is an error', () async {
    final core = await _core();
    final manifest = core.outputs['lib/l10n/translations.kuma.json']!;
    final result = await runKuma(
      KumaConfig.fromMap({
        'namespaces': {
          'core': {'package': 'praises_core', 'class': 'CoreTranslations'},
          'feature': {
            'package': 'praises_feature_impl',
            'class': 'CoreTranslations',
          },
        },
      }),
      MemoryInputs(
        jsonFiles({
          'en': {'hello': 'Hello'},
        }),
        packageFiles: {
          'praises_core': {'lib/l10n/translations.kuma.json': manifest},
          'praises_feature_impl': {'lib/l10n/translations.kuma.json': manifest},
        },
      ),
    );
    expect(summary(result), ['overlap - offline', 'overlap - retry']);
  });

  test('a package without a manifest is an error', () async {
    final result = await _app({'hello': 'Hello'}, coreManifest: {});
    expect(summary(result), ['namespace - -']);
  });

  test('the manifest class must match the namespace config', () async {
    final core = await runKuma(
      KumaConfig.fromMap({'role': 'package', 'class_name': 'Other'}),
      MemoryInputs({'en.json': '{"x": "X"}'}),
    );
    final result = await _app(
      {'hello': 'Hello'},
      coreManifest: {
        'lib/l10n/translations.kuma.json':
            core.outputs['lib/l10n/translations.kuma.json']!,
      },
    );
    expect(summary(result), ['namespace - -']);
  });

  group('staleness', () {
    test('passes when the package JSON matches its manifest', () async {
      final result = await _app(
        {'hello': 'Hello'},
        coreJsonNow: {
          for (final e in _coreJson.entries) '${e.key}.json': e.value,
        },
      );
      expect(result.diagnostics, isEmpty);
    });

    test('fails when the package JSON changed after generation', () async {
      final result = await _app(
        {'hello': 'Hello'},
        coreJsonNow: {
          'en.json': '{"retry": "Retry!", "offline": "x"}',
          'pt.json': _coreJson['pt']!,
        },
      );
      expect(summary(result), ['stale - -']);
    });
  });

  test('golden: representative app output', () async {
    final result = await _app({
      'hello': 'Hello',
      'greeting': 'Hello, {name}!\nWelcome back.',
      'resendIn': 'Resend in {}',
      'itemCount': {'one': '{} Item', 'two': '{} Items', 'other': '{} Items'},
      'episodeCount': {'one': '{count} Episode', 'other': '{count} Episodes'},
      'bookInProgressDescription': {
        'one': '{}% complete · Earn 1 blessing',
        'other': '{}% complete · Earn {} blessings',
      },
      'hrs': {'one': 'Hr', 'other': 'Hrs'},
      "it's": "Quote ' and \$dollar",
      'requestPrayerTargets': {
        'family': 'I want to pray for my family',
        'nested': {'deep': 'Deep {x}'},
      },
    });
    expect(result.diagnostics, isEmpty);
    _golden(
      'app.g.dart.golden',
      result.outputs['lib/app/l10n/translations.g.dart']!,
    );
  });
}

void _golden(String name, String actual) {
  final file = File('test/goldens/$name');
  if (_update || !file.existsSync()) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(actual);
  }
  expect(actual, file.readAsStringSync());
}
