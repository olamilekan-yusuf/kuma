import '../config/config.dart';

/// Which plural forms matter for a locale under a [PluralRulesMode].
class PluralExpectations {
  const PluralExpectations({required this.expected, required this.reachable});

  /// Forms a translation should provide. `other` is always among them.
  final Set<String> expected;

  /// Forms easy_localization can ever select. Others are dead text.
  final Set<String> reachable;
}

PluralExpectations pluralExpectations(String locale, KumaConfig config) {
  switch (config.pluralRules) {
    case PluralRulesMode.fallback:
      // easy_localization's `_pluralCaseFallback`: 0, 1, 2, other.
      return const PluralExpectations(
        expected: {'one', 'other'},
        reachable: {'zero', 'one', 'two', 'other'},
      );
    case PluralRulesMode.cldr:
      final forms = _cldr[_language(locale)] ?? const {'one', 'other'};
      return PluralExpectations(expected: forms, reachable: {'zero', ...forms});
    case PluralRulesMode.strict:
      return PluralExpectations(
        expected: {...config.strictPluralForms, 'other'},
        reachable: const {'zero', 'one', 'two', 'few', 'many', 'other'},
      );
  }
}

String _language(String locale) => locale.split(RegExp('[-_]')).first;

/// Cardinal plural categories per language (CLDR 44), for common languages.
/// Unlisted languages default to `one, other`.
const _cldr = <String, Set<String>>{
  'ar': {'zero', 'one', 'two', 'few', 'many', 'other'},
  'cs': {'one', 'few', 'many', 'other'},
  'cy': {'zero', 'one', 'two', 'few', 'many', 'other'},
  'es': {'one', 'many', 'other'},
  'fr': {'one', 'many', 'other'},
  'he': {'one', 'two', 'other'},
  'id': {'other'},
  'it': {'one', 'many', 'other'},
  'ja': {'other'},
  'ko': {'other'},
  'lt': {'one', 'few', 'many', 'other'},
  'pl': {'one', 'few', 'many', 'other'},
  'pt': {'one', 'many', 'other'},
  'ru': {'one', 'few', 'many', 'other'},
  'sk': {'one', 'few', 'many', 'other'},
  'th': {'other'},
  'uk': {'one', 'few', 'many', 'other'},
  'vi': {'other'},
  'zh': {'other'},
};
