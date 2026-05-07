import 'dart:typed_data';

import 'package:chameleonultragui/helpers/hf_sniff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseHf14aSniffFrames strips parity bits and preserves direction', () {
    final raw = Uint8List.fromList([
      ..._packFrame(Uint8List.fromList([0x26]), isTx: false, rawBitLength: 7),
      ..._packFrame(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]), isTx: true),
    ]);

    final frames = parseHf14aSniffFrames(raw);

    expect(frames, hasLength(2));
    expect(frames.first.rawBitLength, 7);
    expect(frames.first.bitLength, 7);
    expect(frames.first.isReaderToCard, isTrue);
    expect(frames.first.data, [0x26]);
    expect(frames.last.bitLength, 32);
    expect(frames.last.isCardToReader, isTrue);
    expect(frames.last.data, [0xDE, 0xAD, 0xBE, 0xEF]);
  });

  test('summarizeHf14aSniff extracts uid, protocol, aid, and auth requests',
      () {
    final raw = Uint8List.fromList([
      ..._packFrame(Uint8List.fromList([0x93, 0x70, 0x11, 0x22, 0x33, 0x44]),
          isTx: false),
      ..._packFrame(Uint8List.fromList([0xE0, 0x80]), isTx: false),
      ..._packFrame(
          Uint8List.fromList([
            0x00,
            0xA4,
            0x04,
            0x00,
            0x07,
            0xA0,
            0x00,
            0x00,
            0x00,
            0x04,
            0x10,
            0x10,
          ]),
          isTx: false),
      ..._packFrame(Uint8List.fromList([0x60, 0x04]), isTx: false),
    ]);

    final capture = HfSniffCapture.fromRawBytes(raw);

    expect(capture.summary.uid, '11 22 33 44');
    expect(capture.summary.ratsSeen, isTrue);
    expect(capture.summary.aids.single, contains('Mastercard'));
    expect(capture.summary.authRequests, hasLength(1));
    expect(capture.summary.authRequests.single.keyType, 'KeyA');
    expect(capture.summary.authRequests.single.block, 0x04);
  });

  test('extractHf14aSniffNonces groups paired exchanges for recovery', () {
    final raw = Uint8List.fromList([
      ..._packFrame(Uint8List.fromList([0x93, 0x70, 0x11, 0x22, 0x33, 0x44]),
          isTx: false),
      ..._packFrame(Uint8List.fromList([0x60, 0x04]), isTx: false),
      ..._packFrame(Uint8List.fromList([0x01, 0x02, 0x03, 0x04]), isTx: true),
      ..._packFrame(
          Uint8List.fromList([0x10, 0x11, 0x12, 0x13, 0x20, 0x21, 0x22, 0x23]),
          isTx: false),
      ..._packFrame(Uint8List.fromList([0x60, 0x04]), isTx: false),
      ..._packFrame(Uint8List.fromList([0x05, 0x06, 0x07, 0x08]), isTx: true),
      ..._packFrame(
          Uint8List.fromList([0x30, 0x31, 0x32, 0x33, 0x40, 0x41, 0x42, 0x43]),
          isTx: false),
    ]);

    final capture = HfSniffCapture.fromRawBytes(raw);

    expect(capture.nonces, hasLength(2));
    expect(capture.nonceGroups, hasLength(1));
    expect(capture.nonceGroups.single.canRecover, isTrue);
    expect(capture.nonceGroups.single.uid, '11223344');
    expect(capture.nonceGroups.single.block, 0x04);
    expect(buildMfkey64Command(capture.nonceGroups.single),
        'mfkey64 11223344 01020304 10111213 20212223 05060708');
    expect(buildMfkey32Command(capture.nonceGroups.single),
        'mfkey32v2 11223344 01020304 10111213 20212223 05060708 30313233 40414243');
  });
}

List<int> _packFrame(Uint8List data, {required bool isTx, int? rawBitLength}) {
  final bitLength = rawBitLength ?? (data.length * 9);
  final bytes = rawBitLength == null ? _packParityBytes(data) : data;
  final header = bitLength | (isTx ? 0x8000 : 0x0000);

  return <int>[
    (header >> 8) & 0xFF,
    header & 0xFF,
    ...bytes,
  ];
}

List<int> _packParityBytes(Uint8List data) {
  final bits = <int>[];
  for (final byte in data) {
    for (int bit = 0; bit < 8; bit++) {
      bits.add((byte >> bit) & 1);
    }
    bits.add(0);
  }

  final output = <int>[];
  for (int index = 0; index < bits.length; index += 8) {
    final end = (index + 8) < bits.length ? index + 8 : bits.length;
    int value = 0;
    for (int bit = index; bit < end; bit++) {
      value |= bits[bit] << (bit - index);
    }
    output.add(value);
  }
  return output;
}
