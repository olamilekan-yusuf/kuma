import 'package:kuma/kuma.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The app redefines both keys of a package that has `retry` and `offline`.
Future<KumaResult> _app(Map<String, Object?> options) async {
  final core = await runKuma(
    KumaConfig.fromMap({'role': 'package', 'class_name': 'CoreTranslations'}),
    MemoryInputs(
      jsonFiles({
        'en': {'retry': 'Retry', 'offline': 'Offline'},
      }),
    ),
  );
  return runKuma(
    KumaConfig.fromMap({
      'namespaces': {
        'core': {'package': 'praises_core', 'class': 'CoreTranslations'},
      },
      ...options,
    }),
    MemoryInputs(
      jsonFiles({
        'en': {'retry': 'Retry', 'offline': 'Offline', 'own': 'Own'},
      }),
      packageFiles: {
        'praises_core': {
          'lib/l10n/translations.kuma.json':
              core.outputs['lib/l10n/translations.kuma.json']!,
        },
      },
    ),
  );
}

void main() {
  test('overlap is an error by default', () async {
    final result = await _app({});
    expect(summary(result, Severity.error), [
      'overlap - offline',
      'overlap - retry',
    ]);
    expect(result.outputs, isEmpty);
  });

  test('overlap: warning reports warnings and still generates', () async {
    final result = await _app({'overlap': 'warning'});
    expect(summary(result, Severity.error), isEmpty);
    expect(summary(result, Severity.warning), [
      'overlap - offline',
      'overlap - retry',
    ]);
    expect(result.outputs, isNotEmpty);
  });

  test('overlap: warning fails with warnings_as_errors', () async {
    final result =
        await _app({'overlap': 'warning', 'warnings_as_errors': true});
    expect(result.hasErrors, isTrue);
  });

  test('overlap: ignore turns the check off', () async {
    final result = await _app({'overlap': 'ignore'});
    expect(result.diagnostics, isEmpty);
    expect(result.outputs, isNotEmpty);
  });

  test('allow_overlap skips only the listed keys', () async {
    final result = await _app({
      'allow_overlap': ['retry'],
    });
    expect(summary(result, Severity.error), ['overlap - offline']);
  });

  test('allow_overlap takes globs', () async {
    final result = await _app({
      'allow_overlap': ['re*', 'offline'],
    });
    expect(result.diagnostics, isEmpty);
    expect(result.outputs, isNotEmpty);
  });

  test('allow_overlap combines with overlap: warning', () async {
    final result = await _app({
      'overlap': 'warning',
      'allow_overlap': ['retry'],
    });
    expect(summary(result), ['overlap - offline']);
    expect(result.diagnostics.single.severity, Severity.warning);
  });

  test('overlap must be a known value', () {
    expect(
      () => KumaConfig.fromMap({'overlap': 'nope'}),
      throwsA(isA<KumaConfigException>()),
    );
  });
}
