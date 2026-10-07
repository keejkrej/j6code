import 'dart:convert';
import 'dart:io';

/// Tiny persisted key/value store for UI preferences (~/.j6code/ui_settings.json),
/// the j6code stand-in for t3code's localStorage-backed UI state.
class UiSettings {
  UiSettings._();

  static Map<String, dynamic>? _cache;

  static File get _file {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    final sep = Platform.pathSeparator;
    return File('$home$sep.j6code${sep}ui_settings.json');
  }

  static Map<String, dynamic> _load() {
    if (_cache != null) return _cache!;
    try {
      final f = _file;
      if (f.existsSync()) {
        final decoded = jsonDecode(f.readAsStringSync());
        if (decoded is Map<String, dynamic>) return _cache = decoded;
      }
    } catch (_) {}
    return _cache = <String, dynamic>{};
  }

  static T? get<T>(String key) {
    final v = _load()[key];
    return v is T ? v : null;
  }

  static void set(String key, Object? value) {
    final map = _load();
    map[key] = value;
    try {
      final f = _file;
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(map));
    } catch (_) {}
  }
}
