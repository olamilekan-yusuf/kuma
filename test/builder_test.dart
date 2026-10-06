import 'package:build_test/build_test.dart';
import 'package:kuma/builder.dart';
import 'package:kuma/kuma.dart';
import 'package:test/test.dart';

void main() {
  test('generates from assets in the input dir', () async {
    final result = await testBuilder(
      KumaBuilder(const KumaConfig()),
      {
        'app|assets/translations/en.json': '{"hello": "Hello {name}"}',
        'app|assets/translations/pt.json': '{"hello": "Olá {name}"}',
      },
      rootPackage: 'app',
      outputs: {
        'app|lib/l10n/translations.g.dart': decodedMatches(
          contains('String hello({required String name})'),
        ),
      },
    );
    expect(result.succeeded, isTrue);
  });

  test('fails the build on translation errors', () async {
    final logs = <String>[];
    final result = await testBuilder(
      KumaBuilder(const KumaConfig()),
      {
        'app|assets/translations/en.json': '{"a": "A"}',
        'app|assets/translations/pt.json': '{}',
      },
      rootPackage: 'app',
      onLog: (r) => logs.add(r.message),
    );
    expect(result.succeeded, isFalse);
    expect(logs, contains(contains('missing pt a')));
  });

  test('reads namespace manifests from dependency packages', () async {
    final manifest = KumaManifest(
      className: 'CoreTranslations',
      fingerprint: 'x',
      inputDir: 'assets/translations',
      locales: ['en'],
      keys: ['retry'],
    ).encode();

    final logs = <String>[];
    final result = await testBuilder(
      KumaBuilder(KumaConfig.fromMap({
        'namespaces': {
          'core': {'package': 'praises_core', 'class': 'CoreTranslations'},
        },
      })),
      {
        'app|assets/translations/en.json': '{"retry": "Retry"}',
        'praises_core|lib/l10n/translations.kuma.json': manifest,
      },
      rootPackage: 'app',
      onLog: (r) => logs.add(r.message),
    );
    expect(result.succeeded, isFalse);
    expect(logs, contains(contains('overlap - retry')));
  });
}
