import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen1.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen2.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';

import 'sl1_profile_test.dart' show fixture;
import 'sl1_routes_test.dart' show ProfileRouteDevice, acquisition;

class Gen1Writes extends MifareClassicGen1WriteHelper {
  Gen1Writes(super.communicator, {required super.recovery});
  final blocks = <int, Uint8List>{};

  @override
  Future<bool> writeBlock(int block, Uint8List data) async {
    blocks[block] = Uint8List.fromList(data);
    return true;
  }
}

class Gen2Writes extends MifareClassicGen2WriteHelper {
  Gen2Writes(super.communicator, {required super.recovery});
  final blocks = <int, Uint8List>{};

  @override
  Future<bool> writeBlockModifier(
    dynamic card,
    int block,
    Uint8List data, {
    bool tryBothKeys = false,
    bool useGenericKey = false,
  }) async {
    blocks[block] = Uint8List.fromList(data);
    return true;
  }
}

void main() {
  for (final gen2 in [false, true]) {
    test(
      'physical writer fills observed trailer masks with known keys, gen2=$gen2',
      () async {
        final device = ProfileRouteDevice();
        final (recovery, _) = await acquisition(device);
        final profile = fixture();
        for (var block = 3; block < 20; block += 4) {
          profile.json['classic']['blocks'][block]['data'] =
              '${'??' * 6}FF078069${'??' * 6}';
        }
        final card = sl1ToCard(profile);
        expect(card.data[3], isEmpty);
        final first = Gen1Writes(device, recovery: recovery)
          ..type = MifareClassicType.mini;
        final second = Gen2Writes(device, recovery: recovery)
          ..type = MifareClassicType.mini;
        final writer = gen2 ? second : first;
        expect(await writer.writeData(card, (_) {}), isTrue);
        final writes = gen2 ? second.blocks : first.blocks;
        for (var block = 3; block < 20; block += 4) {
          expect(writes[block], profile.image()[block]);
        }
        expect(card.data[3], isEmpty);
        expect(profile.json['classic']['blocks'][3]['data'], startsWith('??'));
      },
    );

    test(
      'incomplete profile is rejected before any device command, gen2=$gen2',
      () async {
        final device = ProfileRouteDevice();
        final (recovery, _) = await acquisition(device);
        final profile = fixture();
        profile.json['classic']['blocks'][1]['data'] = '??' * 16;
        profile.json['classic']['blocks'][1]['status'] = 'unread';
        final card = sl1ToCard(profile);
        final first = Gen1Writes(device, recovery: recovery);
        final second = Gen2Writes(device, recovery: recovery);
        final writer = gen2 ? second : first;
        device.calls.clear();
        expect(await writer.writeData(card, (_) {}), isFalse);
        expect(device.calls, isEmpty);
        expect(first.blocks, isEmpty);
        expect(second.blocks, isEmpty);
      },
    );
  }
}
