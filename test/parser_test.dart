import 'package:kuma/src/core/diagnostics/diagnostics.dart';
import 'package:kuma/src/core/parsing/ir.dart';
import 'package:kuma/src/core/parsing/parser.dart';
import 'package:test/test.dart';

LocaleTree parse(String json, [DiagnosticSink? sink]) =>
    parseLocale('en', json, sink ?? DiagnosticSink())!;

void main() {
  group('classification', () {
    test('strings become messages with placeholders', () {
      final node = parse('{"greeting": "Hi {name}, you have {} new"}')
          .flatten()['greeting'] as MessageNode;
      expect(node.placeholders.named, {'name'});
      expect(node.placeholders.positional, 1);
    });

    test('maps of plural forms become plurals', () {
      final node = parse('{"items": {"one": "{} item", "other": "{} items"}}')
          .flatten()['items'];
      expect(node, isA<PluralNode>());
      expect((node as PluralNode).forms.keys, ['one', 'other']);
    });

    test('plural placeholders are the union, positional the max', () {
      final node = parse(
        '{"x": {"one": "Earn 1", "other": "{}% done, earn {} {unit}"}}',
      ).flatten()['x'] as PluralNode;
      expect(node.placeholders.positional, 2);
      expect(node.placeholders.named, {'unit'});
    });

    test('other maps become namespaces with full paths', () {
      final flat =
          parse('{"home": {"title": "Home", "tabs": {"a": "A"}}}').flatten();
      expect(flat.keys, ['home', 'home.title', 'home.tabs', 'home.tabs.a']);
      expect(flat['home'], isA<NamespaceNode>());
    });
  });

  group('structural errors', () {
    test('mixing plural forms and other keys', () {
      final sink = DiagnosticSink();
      parse('{"x": {"one": "a", "label": "b"}}', sink);
      expect(sink.items.single.code, 'structure');
    });

    test('keys containing "." are unreachable', () {
      final sink = DiagnosticSink();
      final flat = parse('{"e.g": "e.g.", "ok": "ok"}', sink).flatten();
      expect(sink.items.single.code, 'unreachable');
      expect(flat.keys, ['ok']);
    });

    test('non-string leaves', () {
      final sink = DiagnosticSink();
      parse('{"n": 3, "list": [], "nil": null}', sink);
      expect(sink.items.map((d) => d.code), everyElement('structure'));
      expect(sink.items, hasLength(3));
    });

    test('invalid JSON', () {
      final sink = DiagnosticSink();
      expect(parseLocale('en', '{', sink), isNull);
      expect(sink.items.single.code, 'json');
    });
  });
}
