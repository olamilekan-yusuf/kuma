/// Plural forms easy_localization understands, in display order.
const pluralForms = ['zero', 'one', 'two', 'few', 'many', 'other'];

/// A node in one locale's translation tree.
sealed class L10nNode {
  const L10nNode(this.path);

  /// Full key exactly as passed to easy_localization, e.g. `home.title`.
  final String path;

  /// Last segment of [path].
  String get key => path.split('.').last;

  /// Human-readable kind, used in diagnostics.
  String get kind;
}

class NamespaceNode extends L10nNode {
  const NamespaceNode(super.path, this.children);

  /// Children in source order.
  final Map<String, L10nNode> children;

  @override
  String get kind => 'namespace';
}

/// Placeholders used by a string, or by all forms of a plural.
class Placeholders {
  const Placeholders({this.named = const {}, this.positional = 0});

  /// `{name}` placeholders, in first-seen order.
  final Set<String> named;

  /// Number of `{}`. For plurals, the maximum over all forms.
  final int positional;

  static final _named = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

  static Placeholders of(Iterable<String> texts) {
    final named = <String>{};
    var positional = 0;
    for (final text in texts) {
      named.addAll(_named.allMatches(text).map((m) => m[1]!));
      final count = '{}'.allMatches(text).length;
      if (count > positional) positional = count;
    }
    return Placeholders(named: named, positional: positional);
  }

  bool sameAs(Placeholders other) =>
      positional == other.positional &&
      named.length == other.named.length &&
      named.containsAll(other.named);

  String describe() {
    final parts = [
      if (positional > 0) '{}×$positional',
      ...named.map((n) => '{$n}'),
    ];
    return parts.isEmpty ? '(none)' : parts.join(' ');
  }
}

class MessageNode extends L10nNode {
  MessageNode(super.path, this.text) : placeholders = Placeholders.of([text]);

  final String text;
  final Placeholders placeholders;

  /// easy_localization's `@:key` / `@.modifier:key` link syntax.
  static final linkPattern = RegExp(
    r'(?:@(?:\.[a-z]+)?:(?:[\w\-_|.]+|\([\w\-_|.]+\)))',
  );

  bool get hasLinks => linkPattern.hasMatch(text);

  @override
  String get kind => 'string';
}

class PluralNode extends L10nNode {
  PluralNode(super.path, this.forms)
      : placeholders = Placeholders.of(forms.values);

  /// Form name (`one`, `other`…) → text, in [pluralForms] order.
  final Map<String, String> forms;
  final Placeholders placeholders;

  @override
  String get kind => 'plural';
}

/// One locale's parsed file.
class LocaleTree {
  const LocaleTree(this.locale, this.root);

  final String locale;
  final NamespaceNode root;

  /// Every node except the root, keyed by path, in source order.
  Map<String, L10nNode> flatten() {
    final out = <String, L10nNode>{};
    void walk(NamespaceNode node) {
      for (final child in node.children.values) {
        out[child.path] = child;
        if (child is NamespaceNode) walk(child);
      }
    }

    walk(root);
    return out;
  }
}
