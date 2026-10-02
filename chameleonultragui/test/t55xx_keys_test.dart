import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/t55xx/keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final newKey = hexToBytes("11223344");
  final oldKeys = [hexToBytes("20206666"), Uint8List(4)];

  test('old firmware: new key and old keys, no flags byte', () {
    final tail = buildT55xxKeyTail(newKey, oldKeys);

    expect(bytesToHex(tail), "112233442020666600000000");
    expect(tail.length % 4, 0);
  });

  test('no password: trailing 0x01', () {
    final tail = buildT55xxKeyTail(newKey, oldKeys, setPassword: false);

    expect(bytesToHex(tail), "11223344202066660000000001");
    expect(tail.length % 4, 1);
  });

  test('old keys on opt-in firmware: current password first, then the defaults', () {
    final keys = t55xxOldKeys("11223344", passwordOptIn: true);

    expect(keys.map(bytesToHex),
        ["11223344", "20206666", "51243648", "19920427", "00000000"]);
  });

  test('old keys on opt-in firmware without a current password', () {
    final keys = t55xxOldKeys("", passwordOptIn: true);

    expect(keys.map(bytesToHex),
        ["20206666", "51243648", "19920427", "00000000"]);
  });

  test('old keys: a current password that is also a default is tried once', () {
    final keys = t55xxOldKeys("19920427", passwordOptIn: true);

    expect(keys.map(bytesToHex),
        ["19920427", "20206666", "51243648", "00000000"]);
  });

  test("old keys on older firmware: the form's key, then the factory passwords", () {
    final keys = t55xxOldKeys("20206666", passwordOptIn: false);

    expect(keys.map(bytesToHex),
        ["20206666", "51243648", "19920427", "00000000"]);
  });

  test('request tail for a write with no password on opt-in firmware', () {
    final tail = buildT55xxKeyTail(hexToBytes(t55xxNoPasswordKey),
        t55xxOldKeys("", passwordOptIn: true),
        setPassword: false);

    expect(bytesToHex(tail),
        "0000000020206666512436481992042700000000" "01");
  });

  test('set password: trailing 0x02, any value including zero', () {
    final tail = buildT55xxKeyTail(Uint8List(4), oldKeys, setPassword: true);

    expect(bytesToHex(tail), "00000000202066660000000002");
  });
}
