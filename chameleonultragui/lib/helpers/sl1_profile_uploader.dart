import 'dart:typed_data';

import 'sl1_profile.dart';

/// Transport is injectable so transaction safety is testable without hardware.
typedef Sl1Send = Future<Uint8List> Function(int command, Uint8List payload);

class Sl1Uploader {
  final Sl1Send send;
  final Future<List<int>> Function() capabilities;
  final Future<void> Function()? preparePersistence;
  Sl1Uploader(this.send, this.capabilities, {this.preparePersistence});
  Future<Uint8List> status(int slot) async =>
      _status(await _control(4045, slot), slot);
  Uint8List _status(Uint8List payload, int slot) {
    if (payload.length != 14 || payload[0] != 1 || payload[1] != slot) {
      throw const FormatException('Malformed SL1 profile status');
    }
    return payload;
  }

  /// A status-only completeness check cannot establish RF acceptance.
  static bool hasCompleteStage(Uint8List status) {
    if (status.length != 14 || status[0] != 1 || status[2] & 8 == 0) {
      return false;
    }
    final type = (status[3] << 8) | status[4];
    final expected = (status[10] << 8) | status[11];
    final received = (status[8] << 8) | status[9];
    const counts = {1000: 20, 1001: 64, 1002: 128, 1003: 256};
    return counts[type] == expected && received == expected;
  }

  /// Explicitly commits an existing complete stage; never retries a failure.
  Future<Uint8List> save(int slot) async {
    if (slot < 0 || slot > 7) throw ArgumentError('Invalid slot');
    final caps = await capabilities();
    if (![4045, 4048].every(caps.contains)) {
      throw UnsupportedError('Firmware does not support staged profile save');
    }
    final state = _status(
      await send(4045, Uint8List.fromList([1, slot])),
      slot,
    );
    if (!hasCompleteStage(state)) {
      throw StateError('There is no complete staged profile for this slot');
    }
    await preparePersistence?.call();
    return send(4048, Uint8List.fromList([1, slot]));
  }

  Future<Uint8List> cancel(int slot) => _control(4049, slot);
  Future<Uint8List> clear(int slot) => _control(4050, slot);
  Future<Uint8List> setEnabled(int slot, bool enabled) =>
      _control(4051, slot, [enabled ? 1 : 0]);
  Future<Uint8List> _control(
    int command,
    int slot, [
    List<int> tail = const [],
  ]) async {
    if (slot < 0 || slot > 7) throw ArgumentError('Invalid slot');
    if (!(await capabilities()).contains(command)) {
      throw UnsupportedError('Firmware does not support SL1 profiles');
    }
    if ([4050, 4051].contains(command)) {
      await preparePersistence?.call();
    }
    return send(command, Uint8List.fromList([1, slot, ...tail]));
  }

  Future<void> upload(Sl1Profile profile, int slot) async {
    if (slot < 0 || slot > 7) throw ArgumentError('Invalid slot');
    // Complete validation and capability discovery precede the first mutation.
    final p = Sl1Profile.fromJson(profile.json);
    final image = p.image();
    final caps = await capabilities();
    if ([
      4045,
      4046,
      4047,
      4048,
      4049,
      4050,
      4051,
    ].any((c) => !caps.contains(c))) {
      throw UnsupportedError(
        'Firmware does not support the complete SL1 profile transaction',
      );
    }
    final h = p.json['hf14a'];
    final a = p.json['cardAuth'];
    final uid = Sl1Profile.bytes(h['uid']);
    final ats = h['ats'] == null ? <int>[] : Sl1Profile.bytes(h['ats']);
    final type =
        1000 + ['mini', '1k', '2k', '4k'].indexOf(p.json['classic']['type']);
    final begin = <int>[
      1,
      slot,
      type >> 8,
      type & 255,
      uid.length,
      ...uid,
      ...List.filled(7 - uid.length, 0),
      ...Sl1Profile.bytes(h['atqa']),
      ...Sl1Profile.bytes(h['sak']),
      ats.length,
      a == null ? 0 : 1,
      a != null && a['enabled'] ? 1 : 0,
      a == null ? 0 : 0x90,
      a == null ? 0 : 4,
      ...(a == null ? List.filled(16, 0) : Sl1Profile.bytes(a['key'])),
      ...ats,
    ];
    _status(await send(4045, Uint8List.fromList([1, slot])), slot);
    await preparePersistence?.call();
    await send(4046, Uint8List.fromList(begin));
    // Never retry or hide a failed SAVE: the device's stage/status is evidence.
    for (var i = 0; i < image.length; i += 8) {
      await send(
        4047,
        Uint8List.fromList([
          1,
          slot,
          i >> 8,
          i & 255,
          ...image.skip(i).take(8).expand((b) => b),
        ]),
      );
    }
    await send(4048, Uint8List.fromList([1, slot]));
  }
}
