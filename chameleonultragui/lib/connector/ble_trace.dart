import 'dart:io';

/// Asynchronous, timestamped BLE trace written to %TEMP%\chameleon_ble.log.
///
/// The sink buffers writes, so callers never block the UI isolate on disk I/O.
class BleTrace {
  BleTrace._();

  static final BleTrace instance = BleTrace._();

  static String _mode = 'robust';
  static int? _cycle;

  static const int _maxBytes = 1024 * 1024;
  IOSink? _sink;
  String? _path;
  int _bytes = 0;

  String get path => _path ??=
      '${Directory.systemTemp.path}${Platform.pathSeparator}chameleon_ble.log';

  static void setMode(String mode) => _mode = mode;

  static void setCycle(int? cycle) => _cycle = cycle;

  void reset() {
    try {
      _sink?.close();
    } catch (_) {}
    _sink = null;
    try {
      File(path).writeAsStringSync('');
      _sink = File(path).openWrite(mode: FileMode.append);
      _bytes = 0;
    } catch (_) {}
  }

  void _truncate() {
    try {
      _sink?.close();
    } catch (_) {}
    _sink = null;
    try {
      File(path).writeAsStringSync('');
      _sink = File(path).openWrite(mode: FileMode.append);
      _bytes = 0;
    } catch (_) {}
  }

  void log(String stage, String message) {
    var sink = _sink;
    if (sink == null) {
      try {
        sink = File(path).openWrite(mode: FileMode.append);
        _sink = sink;
        _bytes = File(path).lengthSync();
      } catch (_) {
        return;
      }
    }
    final cycle = _cycle;
    final line =
        '${DateTime.now().toIso8601String()} '
        'mode=$_mode${cycle != null ? ' cycle=$cycle' : ''} '
        'stage=$stage $message';
    if (_bytes + line.length + 1 > _maxBytes) {
      _truncate();
      sink = _sink;
      if (sink == null) {
        return;
      }
    }
    sink.writeln(line);
    _bytes += line.length + 1;
  }

  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  Future<void> close() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    _bytes = 0;
  }
}
