import '../config/config.dart';
import '../diagnostics/diagnostics.dart';
import '../parsing/ir.dart';
import 'naming.dart';
import 'signature.dart';

/// One generated class: the root, or a nested namespace.
class GenClass {
  GenClass(this.name, this.path);

  final String name;

  /// Key path of the namespace, empty for the root.
  final String path;
  final List<GenMember> members = [];
}

sealed class GenMember {
  const GenMember(this.dartName);
  final String dartName;
}

class GenLeaf extends GenMember {
  const GenLeaf(super.dartName, this.node, this.signature);

  /// The base-locale node, used for doc comments.
  final L10nNode node;
  final Signature signature;
}

class GenNamespace extends GenMember {
  const GenNamespace(super.dartName, this.cls);
  final GenClass cls;
}

class GenPackageNamespace extends GenMember {
  GenPackageNamespace(this.config) : super(config.name);
  final NamespaceConfig config;
}

/// Builds the class tree from the base locale. Reports naming problems.
///
/// Returns the root class, and every nested class in generation order.
({GenClass root, List<GenClass> classes}) buildModel(
  LocaleTree base,
  KumaConfig config,
  DiagnosticSink sink,
) {
  final filter = KeyFilter(config.exclude);
  final prefix = config.className.endsWith('Translations')
      ? config.className.substring(
          0,
          config.className.length - 'Translations'.length,
        )
      : config.className;

  final classes = <GenClass>[];
  final classNames = <String, String>{config.className: '(root)'};

  GenClass build(NamespaceNode namespace, String className) {
    final cls = GenClass(className, namespace.path);
    classes.add(cls);
    final memberPaths = <String, String>{};
    final isRoot = namespace.path.isEmpty;

    if (isRoot) {
      for (final ns in config.namespaces) {
        if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(ns.name) ||
            reservedWords.contains(ns.name)) {
          sink.error(
            'namespace',
            'namespace name "${ns.name}" is not a valid lowerCamelCase getter',
          );
          continue;
        }
        memberPaths[ns.name] = 'namespace ${ns.name}';
        cls.members.add(GenPackageNamespace(ns));
      }
    }

    for (final child in namespace.children.values) {
      if (filter.excludes(child.path)) continue;
      final name = memberName(child.key, digitPrefix: config.digitPrefix);
      final dartName = safeIdentifier(
        name,
        extraTaken: occupiedMembers.contains(name) ? {name} : const {},
      );
      final clash = memberPaths[dartName];
      if (clash != null) {
        sink.error(
          'collision',
          'becomes "$dartName", which is already used by $clash',
          path: child.path,
        );
        continue;
      }
      memberPaths[dartName] = '"${child.path}"';

      switch (child) {
        case NamespaceNode():
          final nestedName =
              '$prefix${_classSuffix(child.path, config)}Translations';
          final owner = classNames[nestedName];
          if (owner != null) {
            sink.error(
              'collision',
              'class name $nestedName is already used by $owner',
              path: child.path,
            );
            continue;
          }
          classNames[nestedName] = '"${child.path}"';
          cls.members.add(GenNamespace(dartName, build(child, nestedName)));
        case MessageNode() || PluralNode():
          final signature = resolveSignature(child, config, sink);
          if (signature != null) {
            cls.members.add(GenLeaf(dartName, child, signature));
          }
      }
    }
    return cls;
  }

  final root = build(base.root, config.className);
  return (root: root, classes: classes);
}

String _classSuffix(String path, KumaConfig config) => path
    .split('.')
    .map((s) => pascalCase(memberName(s, digitPrefix: config.digitPrefix)))
    .join();
