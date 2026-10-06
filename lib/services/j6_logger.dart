import 'dart:io';

class J6Logger {
  static final String _homeDir = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      'C:\\Users\\ctyja';
  static final String _logDir = '$_homeDir\\.j6code';
  static final String _logFile = '$_logDir\\j6code.log';
  static File? _file;

  static void init() {
    try {
      final dir = Directory(_logDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _file = File(_logFile);
      info('=== J6Code Logger Initialized ===');
    } catch (e) {
      // Ignore fallback
    }
  }

  static void _write(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] [$level] $message\n';
    try {
      if (_file == null) {
        init();
      }
      _file?.writeAsStringSync(logLine, mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  static void info(String message) => _write('INFO', message);
  static void warn(String message) => _write('WARN', message);
  static void error(String message, [dynamic err, StackTrace? stack]) {
    final extra = err != null ? ' Error: $err\nStack: $stack' : '';
    _write('ERROR', '$message$extra');
  }
}
