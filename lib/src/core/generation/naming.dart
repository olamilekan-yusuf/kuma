/// Dart reserved words, which can't be used as member or parameter names.
const reservedWords = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
  'await', 'yield',
};

/// Members every generated class already has, or that kuma generates itself.
const occupiedMembers = {
  'hashCode', 'runtimeType', 'toString', 'noSuchMethod', 'instance', //
};

/// Turns a key segment into a lowerCamelCase identifier.
///
/// Already-camelCase keys are kept as they are (`donationSuccess`).
/// `snake_case` and `kebab-case` are joined (`button_type` → `buttonType`).
/// A leading digit gets [digitPrefix] (`1Samuel` → `n1Samuel`).
String memberName(String segment, {required String digitPrefix}) {
  final words = segment
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '${digitPrefix}_';
  final buffer = StringBuffer(_lowerFirstWord(words.first));
  for (final word in words.skip(1)) {
    buffer.write(word[0].toUpperCase());
    buffer.write(word.substring(1));
  }
  var name = buffer.toString();
  if (RegExp(r'^[0-9]').hasMatch(name)) name = '$digitPrefix$name';
  return name;
}

/// Makes [name] usable as a member or parameter by adding `_` to clashes.
String safeIdentifier(String name, {Set<String> extraTaken = const {}}) {
  var result = name;
  while (reservedWords.contains(result) || extraTaken.contains(result)) {
    result = '${result}_';
  }
  return result;
}

String pascalCase(String identifier) => identifier.isEmpty
    ? identifier
    : identifier[0].toUpperCase() + identifier.substring(1);

/// `URL` → `url`, `URLPath` → `urlPath`, `Genesis` → `genesis`.
String _lowerFirstWord(String word) {
  if (word == word.toUpperCase()) return word.toLowerCase();
  final leadingCaps = RegExp(r'^[A-Z]+').firstMatch(word)?[0] ?? '';
  if (leadingCaps.length > 1) {
    final keep = leadingCaps.length - 1;
    return word.substring(0, keep).toLowerCase() + word.substring(keep);
  }
  return word[0].toLowerCase() + word.substring(1);
}

/// Matches key paths against simple globs: `*` (any run of characters,
/// including `.`), `?` (one character) and `[...]` classes.
class KeyFilter {
  KeyFilter(Iterable<String> globs)
      : _patterns = [for (final g in globs) _toRegExp(g)];

  final List<RegExp> _patterns;

  /// Whether [path], or any namespace it sits under, is excluded.
  bool excludes(String path) {
    final segments = path.split('.');
    for (var i = 1; i <= segments.length; i++) {
      final prefix = segments.take(i).join('.');
      if (_patterns.any((p) => p.hasMatch(prefix))) return true;
    }
    return false;
  }

  static RegExp _toRegExp(String glob) {
    final buffer = StringBuffer('^');
    var inClass = false;
    for (final char in glob.split('')) {
      if (inClass) {
        buffer.write(char);
        if (char == ']') inClass = false;
        continue;
      }
      switch (char) {
        case '*':
          buffer.write('.*');
        case '?':
          buffer.write('.');
        case '[':
          inClass = true;
          buffer.write('[');
        default:
          buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }
}
