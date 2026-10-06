import 'dart:io';

import 'package:args/args.dart';
import 'package:kuma/kuma.dart';
import 'package:kuma/src/io/io_inputs.dart';
import 'package:path/path.dart' as p;

const _usage = '''
Usage: dart run kuma <command> [options]

Commands:
  generate   Validate translations, then write the generated files.
  check      Validate only. With `role: package`, also fails if the committed
             generated files are out of date.
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('config',
        help: 'Config file (default: kuma.yaml, then pubspec.yaml `kuma:`).')
    ..addOption('root', help: 'Package root.', defaultsTo: '.')
    ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
    ..addFlag('warnings-as-errors', negatable: false)
    ..addFlag('verbose',
        abbr: 'v', negatable: false, help: 'Also list info diagnostics.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage${parser.usage}');
    exit(64);
  }

  if (args.flag('help') || args.rest.length != 1) {
    stdout.writeln('$_usage\n${parser.usage}');
    exit(args.flag('help') ? 0 : 64);
  }

  final command = args.rest.single;
  if (command != 'generate' && command != 'check') {
    stderr.writeln('Unknown command "$command".\n\n$_usage');
    exit(64);
  }

  final root = p.normalize(p.absolute(args.option('root')!));
  KumaConfig config;
  try {
    config = loadConfig(root, configPath: args.option('config'));
  } on KumaConfigException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
  if (args.flag('warnings-as-errors')) {
    config = config.overlay({'warnings_as_errors': true});
  }

  final result = await runKuma(config, IoInputs(root, config));
  var diagnostics = result.diagnostics;

  if (command == 'check' &&
      config.role == KumaRole.package &&
      !result.hasErrors) {
    final stale = _staleOutputs(root, result.outputs);
    diagnostics = [
      ...diagnostics,
      for (final path in stale)
        Diagnostic(
          Severity.error,
          'stale-output',
          '$path is out of date; run `dart run kuma generate` and commit it',
        ),
    ]..sort();
  }

  final format =
      args.option('format') == 'json' ? ReportFormat.json : ReportFormat.text;
  stdout.write(
      formatReport(diagnostics, format: format, verbose: args.flag('verbose')));
  final failed = diagnostics.any((d) => d.severity == Severity.error);

  if (failed) {
    if (format == ReportFormat.text) {
      stdout.writeln(
          '\n✖ ${command == 'generate' ? 'Generation aborted' : 'Check failed'}. Fix the errors above.');
    }
    exit(1);
  }

  if (command == 'generate') {
    for (final MapEntry(key: path, value: content) in result.outputs.entries) {
      final file = File(p.join(root, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
      if (format == ReportFormat.text) stdout.writeln('wrote $path');
    }
  } else if (format == ReportFormat.text) {
    stdout.writeln('✔ Translations are valid.');
  }
}

List<String> _staleOutputs(String root, Map<String, String> outputs) => [
      for (final MapEntry(key: path, value: content) in outputs.entries)
        if (!File(p.join(root, path)).existsSync() ||
            File(p.join(root, path)).readAsStringSync() != content)
          path,
    ];
