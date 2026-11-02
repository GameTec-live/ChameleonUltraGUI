import 'dart:typed_data';

import 'package:chameleonultragui/helpers/mifare_classic/gen4.dart';
import 'package:flutter_test/flutter_test.dart';

const factoryConfig =
    '00000000000002000978009102DABC191010111213141516040008006B02';

void main() {
  test('PACK page follows CC revision and requires a choice for malformed versions', () {
    expect(gen4PackPage(gen4ParseHex('00000006A0')), 0x13);
    expect(gen4PackPage(gen4ParseHex('00000066661234')), 0x13);
    expect(gen4PackPage(gen4ParseHex('00000003ABE731')), 0xE6);
    expect(gen4PackPage(gen4ParseHex('3F')), isNull);
    expect(gen4PackPage(gen4ParseHex('6300')), isNull);
    expect(gen4PackPage(gen4ParseHex('90000003AB')), isNull);
  });

  test('accepts a recorded 34-byte configuration frame', () {
    // Raw response from RfidResearchGroup/proxmark3#1822, including RF CRC.
    final response = gen4ParseHex(
      '00000000000002090978009102BDAC191310111213141516040008026B004F6BF441',
    );
    final config = Gen4Configuration.fromResponse(response);
    expect(
      gen4Hex(config.bytes),
      '00000000000002090978009102BDAC191310111213141516040008026B00',
    );
  });

  test('decodes every configuration field, retaining unused ATS bytes', () {
    final bytes = gen4ParseHex(factoryConfig);
    expect(bytes, hasLength(30));
    final config = Gen4Configuration.fromResponse(
      Uint8List.fromList([...bytes, 0x4F, 0x6B]),
    );
    expect(config.protocol, 0);
    expect(config.uidLength, 4);
    expect(config.password, [0, 0, 0, 0]);
    expect(config.shadowMode, 2);
    expect(config.ats, isEmpty);
    final withAts = Gen4Configuration(Uint8List.fromList(bytes)..[7] = 9);
    expect(gen4Hex(withAts.ats), '0978009102DABC1910');
    expect(config.atqa, [0, 4]);
    expect(config.sak, 8);
    expect(config.ultralightMode, 0);
    expect(config.maxBlock, 0x6B);
    expect(config.block0Mode, 2);
    expect(gen4Hex(config.bytes), factoryConfig);
    expect(
      () => Gen4Configuration.fromResponse(Uint8List(2)),
      throwsFormatException,
    );
    bytes[7] = 17;
    expect(() => Gen4Configuration(bytes), throwsFormatException);
  });

  test(
    'F0 updates the credential only after success; F1 is explicit',
    () async {
      final commands = <Uint8List>[];
      var reject = true;
      final client = Gen4Client((command) async {
        commands.add(command);
        return gen4ParseHex(reject ? '6300' : '9000FD07');
      }, gen4ParseHex('00000000'));
      final data = gen4ParseHex(factoryConfig)
        ..setRange(2, 6, [0xAA, 0xBB, 0xCC, 0xDD]);
      final config = Gen4Configuration(data);
      await expectLater(client.writeConfiguration(config), throwsStateError);
      reject = false;
      await client.writeConfiguration(config);
      await client.writeConfiguration(config, permanent: true);
      expect(gen4Hex(commands[0].sublist(0, 6)), 'CF00000000F0');
      expect(gen4Hex(commands[1].sublist(0, 6)), 'CF00000000F0');
      expect(gen4Hex(commands[2]), 'CFAABBCCDDF1${gen4Hex(data)}');
    },
  );

  test(
    'UID writes preserve manufacturer bytes and reject mismatched lengths',
    () async {
      final original = Uint8List.fromList(List.generate(16, (i) => i));
      Uint8List? written;
      final client = Gen4Client((command) async {
        if (command[5] == 0xCE) return original;
        written = command;
        return gen4ParseHex('9000');
      }, Uint8List(4));
      final config = Gen4Configuration(gen4ParseHex(factoryConfig));
      await expectLater(
        client.writeUid(config, Uint8List(7)),
        throwsArgumentError,
      );
      expect(written, isNull);
      await client.writeUid(config, gen4ParseHex('11223344'));
      expect(written!.sublist(0, 7), [0xCF, 0, 0, 0, 0, 0xCD, 0]);
      expect(written!.sublist(7, 12), [0x11, 0x22, 0x33, 0x44, 0x44]);
      expect(written!.sublist(12), original.sublist(5));
    },
  );

  test(
    'Ultralight UID updates BCC without overwriting lock or OTP bytes',
    () async {
      final memory = [
        for (var i = 0; i < 3; i++)
          Uint8List.fromList(List.filled(16, 0xA0 + i)),
      ];
      final client = Gen4Client((command) async {
        final block = command[6];
        if (command[5] == 0xCE) return memory[block];
        memory[block] = command.sublist(7);
        return gen4ParseHex('9000');
      }, Uint8List(4));
      final config = Gen4Configuration(
        gen4ParseHex(factoryConfig)
          ..[0] = 1
          ..[1] = 1,
      );
      await client.writeUid(config, gen4ParseHex('04112233445566'));
      expect(memory[0].sublist(0, 4), [4, 0x11, 0x22, 0xBF]);
      expect(memory[1].sublist(0, 4), [0x33, 0x44, 0x55, 0x66]);
      expect(memory[2][0], 0x44);
      expect(memory[2].sublist(1), List.filled(15, 0xA2));
    },
  );

  test(
    'memory-backed settings preserve bytes outside the requested value',
    () async {
      final memory = {
        0x13: Uint8List.fromList(List.filled(16, 0xAA)),
        0xFA: Uint8List.fromList(List.filled(16, 0xBB)),
        0xFB: Uint8List.fromList(List.filled(16, 0xCC)),
      };
      final client = Gen4Client((command) async {
        final address = command[6];
        if (command[5] == 0xCE) return memory[address]!;
        memory[address] = command.sublist(7);
        return gen4ParseHex('9000');
      }, Uint8List(4));
      await client.writeMemory(0x13, gen4ParseHex('8080'), 4);
      expect(memory[0x13]!.sublist(0, 2), [0x80, 0x80]);
      expect(memory[0x13]!.sublist(2), List.filled(14, 0xAA));
      final version = gen4ParseHex('0004040201000F03');
      await client.writeMemory(0xFA, version, 4);
      expect(await client.readMemory(0xFA, 8, 4), version);
      expect(memory[0xFA]!.sublist(4), List.filled(12, 0xBB));
      expect(memory[0xFB]!.sublist(4), List.filled(12, 0xCC));
    },
  );

  test('strict hex and block parsing rejects input before transport', () async {
    var calls = 0;
    final client = Gen4Client((_) async {
      calls++;
      return Uint8List(0);
    }, Uint8List(4));
    for (final input in ['0', 'zz', '000']) {
      expect(() => gen4ParseHex(input), throwsFormatException);
    }
    expect(gen4ParseHex('ab cd'), [0xAB, 0xCD]);
    await expectLater(client.readBlock(256), throwsRangeError);
    await expectLater(client.writeBlock(0, [1]), throwsArgumentError);
    expect(calls, 0);
  });
}
