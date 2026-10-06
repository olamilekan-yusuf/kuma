import 'package:kuma/kuma.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The fixture is trimmed from praises-ai-quick-access as of 2026-10-04 and
/// keeps every real problem kuma was built to catch.
void main() {
  test('reports exactly the known issues in the real files', () async {
    final result = await runKuma(
      const KumaConfig(),
      MemoryInputs(yohannaFixture()),
    );
    expect(summary(result), [
      'missing es Apr',
      'missing pt Apr',
      'collision - Genesis',
      'missing es donationSuccess',
      'unreachable es e.g',
      'unreachable pt e.g',
      'placeholder es referralDateFormat',
      'placeholder pt referralDateFormat',
      'placeholder es resendIn',
      'unreachable pt takesLessThanAMinute.',
    ]);
  });

  test('every real plural shape gets a signature', () async {
    final result = await runKuma(
      KumaConfig.fromMap({
        'missing_key': 'warning',
        'exclude': ['Genesis'],
      }),
      MemoryInputs(yohannaFixture()),
    );
    final errors = summary(result, Severity.error);
    // Only the cross-locale placeholder bugs remain; nothing about signatures.
    expect(
        errors,
        everyElement(
            anyOf(startsWith('placeholder'), startsWith('unreachable'))));
  });
}
