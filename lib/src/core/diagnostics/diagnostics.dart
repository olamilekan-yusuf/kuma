enum Severity { error, warning, info }

/// One problem found while reading, validating or generating.
class Diagnostic implements Comparable<Diagnostic> {
  const Diagnostic(
    this.severity,
    this.code,
    this.message, {
    this.path,
    this.locale,
  });

  final Severity severity;

  /// Short machine-readable category, e.g. `missing`, `placeholder`.
  final String code;
  final String message;

  /// Key path the diagnostic refers to, if any.
  final String? path;
  final String? locale;

  Diagnostic asError() => Diagnostic(
        Severity.error,
        code,
        message,
        path: path,
        locale: locale,
      );

  Map<String, Object?> toJson() => {
        'severity': severity.name,
        'code': code,
        'message': message,
        if (path != null) 'path': path,
        if (locale != null) 'locale': locale,
      };

  @override
  int compareTo(Diagnostic other) {
    final bySeverity = severity.index.compareTo(other.severity.index);
    if (bySeverity != 0) return bySeverity;
    final byPath = (path ?? '').compareTo(other.path ?? '');
    if (byPath != 0) return byPath;
    final byLocale = (locale ?? '').compareTo(other.locale ?? '');
    if (byLocale != 0) return byLocale;
    return code.compareTo(other.code);
  }

  @override
  String toString() =>
      '${severity.name} $code ${locale ?? '-'} ${path ?? '-'}: $message';
}

/// Collects diagnostics in the order they are found.
class DiagnosticSink {
  final List<Diagnostic> _items = [];

  List<Diagnostic> get items => List.unmodifiable(_items);
  bool get hasErrors => _items.any((d) => d.severity == Severity.error);

  void add(Diagnostic diagnostic) => _items.add(diagnostic);

  void error(String code, String message, {String? path, String? locale}) =>
      add(Diagnostic(Severity.error, code, message,
          path: path, locale: locale));

  void warning(String code, String message, {String? path, String? locale}) =>
      add(
        Diagnostic(Severity.warning, code, message, path: path, locale: locale),
      );

  void info(String code, String message, {String? path, String? locale}) =>
      add(Diagnostic(Severity.info, code, message, path: path, locale: locale));
}
