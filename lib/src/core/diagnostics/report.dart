import 'dart:convert';

import 'diagnostics.dart';

enum ReportFormat { text, json }

/// Formats diagnostics. Info entries are counted but only listed when
/// [verbose] is set.
String formatReport(
  List<Diagnostic> diagnostics, {
  ReportFormat format = ReportFormat.text,
  bool verbose = false,
}) {
  if (format == ReportFormat.json) {
    return const JsonEncoder.withIndent('  ').convert({
      'errors': _count(diagnostics, Severity.error),
      'warnings': _count(diagnostics, Severity.warning),
      'infos': _count(diagnostics, Severity.info),
      'diagnostics': [
        for (final d in diagnostics)
          if (verbose || d.severity != Severity.info) d.toJson(),
      ],
    });
  }

  final errors = _count(diagnostics, Severity.error);
  final warnings = _count(diagnostics, Severity.warning);
  final infos = _count(diagnostics, Severity.info);
  final out = StringBuffer(
    'kuma: ${_plural(errors, 'error')}, ${_plural(warnings, 'warning')}',
  );
  if (infos > 0) out.write(', ${_plural(infos, 'info')}');
  out.writeln();

  final shown = [
    for (final d in diagnostics)
      if (verbose || d.severity != Severity.info) d,
  ];
  final codeWidth = _width(shown.map((d) => d.code));
  final localeWidth = _width(shown.map((d) => d.locale ?? '-'));
  final pathWidth = _width(shown.map((d) => d.path ?? '-'), max: 48);

  for (final severity in Severity.values) {
    final group = shown.where((d) => d.severity == severity).toList();
    if (group.isEmpty) continue;
    out
      ..writeln()
      ..writeln('${severity.name.toUpperCase()}S');
    for (final d in group) {
      out.writeln(
        '  ${d.code.padRight(codeWidth)}  '
        '${(d.locale ?? '-').padRight(localeWidth)}  '
        '${(d.path ?? '-').padRight(pathWidth)}  '
        '${d.message}',
      );
    }
  }
  return out.toString();
}

int _count(List<Diagnostic> items, Severity severity) =>
    items.where((d) => d.severity == severity).length;

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

int _width(Iterable<String> values, {int max = 1 << 30}) {
  var width = 0;
  for (final v in values) {
    if (v.length > width) width = v.length;
  }
  return width > max ? max : width;
}
