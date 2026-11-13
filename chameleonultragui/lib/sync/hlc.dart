/// Hybrid logical clock. Timestamps are strings that sort lexicographically:
/// `<ms, 15 digits>-<counter, 6 digits>-<node>`. They follow wall-clock time
/// but stay monotonic and causally ordered even when device clocks disagree.
class Hlc {
  /// Sorts before every real timestamp. Used for data that existed before
  /// sync was enabled, so the vault's version wins on first contact.
  static const zero = '000000000000000-000000-';

  final String node;
  int _ms = 0;
  int _counter = 0;
  final int Function() _now;

  Hlc(this.node, {int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  String _format() =>
      '${_ms.toString().padLeft(15, '0')}-${_counter.toString().padLeft(6, '0')}-$node';

  /// A timestamp greater than every one issued or observed before.
  String next() {
    final wall = _now();
    if (wall > _ms) {
      _ms = wall;
      _counter = 0;
    } else {
      _counter++;
    }
    return _format();
  }

  /// Merges a remote timestamp so later local edits sort after it.
  void observe(String timestamp) {
    final parts = timestamp.split('-');
    if (parts.length < 3) return;
    final ms = int.tryParse(parts[0]) ?? 0;
    final counter = int.tryParse(parts[1]) ?? 0;
    if (ms > _ms || (ms == _ms && counter > _counter)) {
      _ms = ms;
      _counter = counter;
    }
  }

  /// Wall-clock time of a timestamp, for display.
  static DateTime? time(String timestamp) {
    final ms = int.tryParse(timestamp.split('-').first) ?? 0;
    return ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
