import 'dart:io';

/// Asynchronous, timestamped BLE trace written to %TEMP%\chameleon_ble.log.
///
/// The sink buffers writes, so callers never block the UI isolate on disk I/O.
class BleTrace {
  BleTrace._();

  static final BleTrace instance = BleTrace._();

  static String _mode = 'robust';
  static int? _cycle;

  IOSink? _sink;
  String? _path;

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
    } catch (_) {}
  }

  void log(String stage, String message) {
    var sink = _sink;
    if (sink == null) {
      try {
        sink = File(path).openWrite(mode: FileMode.append);
        _sink = sink;
      } catch (_) {
        return;
      }
    }
    final cycle = _cycle;
    sink.writeln('${DateTime.now().toIso8601String()} '
        'mode=$_mode${cycle != null ? ' cycle=$cycle' : ''} '
        'stage=$stage $message');
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
  }
}
