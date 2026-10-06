import 'package:kuma/src/core/generation/naming.dart';
import 'package:test/test.dart';

void main() {
  String name(String key) => memberName(key, digitPrefix: 'n');

  test('camelCase keys are kept', () {
    expect(name('donationSuccess'), 'donationSuccess');
  });

  test('snake and kebab case are joined', () {
    expect(name('button_type_two'), 'buttonTypeTwo');
    expect(name('sign-in'), 'signIn');
  });

  test('leading capitals are lowered', () {
    expect(name('Genesis'), 'genesis');
    expect(name('URL'), 'url');
    expect(name('URLPath'), 'urlPath');
    expect(name('allPartneredNGOs'), 'allPartneredNGOs');
  });

  test('leading digits get the prefix', () {
    expect(name('1Samuel'), 'n1Samuel');
  });

  test('punctuation is dropped', () {
    expect(name('howAreYouFeeling?'), 'howAreYouFeeling');
  });

  test('reserved words get a suffix', () {
    expect(safeIdentifier('class'), 'class_');
    expect(safeIdentifier('name', extraTaken: {'name'}), 'name_');
  });

  group('KeyFilter', () {
    final filter = KeyFilter(['[1-3]*', 'Genesis', 'months.*', 'day?']);

    test('matches globs over the full path', () {
      expect(filter.excludes('1Samuel'), isTrue);
      expect(filter.excludes('Genesis'), isTrue);
      expect(filter.excludes('genesis'), isFalse);
      expect(filter.excludes('months.jan'), isTrue);
      expect(filter.excludes('days'), isTrue);
      expect(filter.excludes('day'), isFalse);
    });

    test('excluding a namespace excludes its children', () {
      expect(KeyFilter(['home']).excludes('home.title'), isTrue);
    });
  });
}
