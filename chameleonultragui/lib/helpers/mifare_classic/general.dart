import 'dart:isolate';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Mifare Classic keys from Proxmark3
final gMifareClassicKeysList = {
  0xFFFFFFFFFFFF, // DEFAULT KEY (FIRST KEY USED BY PROGRAM IF NO USER DEFINED KEY)
  0xA0A1A2A3A4A5, // NFCFORUM MAD KEY
  0xD3F7D3F7D3F7, // NDEF PUBLIC KEY
  0x4B791BEA7BCC, // MFC EV1 SIGNATURE 17 B
  0x5C8FF9990DA2, // MFC EV1 SIGNATURE 16 A
  0xD01AFEEB890A, // MFC EV1 SIGNATURE 16 B
  0x75CCB59C9BED, // MFC EV1 SIGNATURE 17 A
  0x6471A5EF2D1A, // SIMONSVOSS
  0x4E3552426B32, // ID06
  0xEF1232AB18A0, // SCHLAGE
  0xB7BF0C13066E, // GALLAGHER
  0x135B88A94B8B, // SAFLOK
  0x2A2C13CC242A, // DORMA KABA
  0x5A7A52D5E20D, // BOSCH
  0x314B49474956, // VIGIK1 A
  0x564C505F4D41, // VIGIK1 B
  0x021209197591, // BTCINO
  0x484558414354, // INTRATONE
  0xEC0A9B1A9E06, // VINGCARD
  0x66B31E64CA4B, // VINGCARD
  0xE00000000000, // ICOPY
  0x199404281970, // NSP A
  0x199404281998, // NSP B
  0x6A1987C40A21, // SALTO
  0x7F33625BC129, // SALTO
  0x484944204953, // HID
  0x204752454154, // HID
  0x3B7E4FD575AD, // HID
  0x11496F97752A, // HID
  0x000000000000, // BLANK KEY
  0xB0B1B2B3B4B5,
  0xAABBCCDDEEFF,
  0x1A2B3C4D5E6F,
  0x123456789ABC,
  0x010203040506,
  0x123456ABCDEF,
  0xABCDEF123456,
  0x4D3A99C351DD,
  0x1A982C7E459A,
  0x714C5C886E97,
  0x587EE5F9350F,
  0xA0478CC39091,
  0x533CB6C723F6,
  0x8FD0A4F256E9,
  0x0000014B5C31,
  0xB578F38A5C61,
  0x96A301BCE267,
};

// https://eprint.iacr.org/2024/1275
final gMifareClassicBackdoorKeysList = {
  0xA396EFA4E24F,
  0xA31667A8CEC1,
  0x518B3354E760,
  0x73B9836CF168,
};

enum MifareClassicType {
  none,
  mini,
  m1k,
  m2k,
  m4k
} // can't start with number...

final gMifareClassicKeys = gMifareClassicKeysList
    .map((key) => Uint8List.fromList([
          (key >> 40) & 0xFF,
          (key >> 32) & 0xFF,
          (key >> 24) & 0xFF,
          (key >> 16) & 0xFF,
          (key >> 8) & 0xFF,
          key & 0xFF,
        ]))
    .toList();

final gMifareClassicBackdoorKeys = gMifareClassicBackdoorKeysList
    .map((key) => Uint8List.fromList([
          (key >> 40) & 0xFF,
          (key >> 32) & 0xFF,
          (key >> 24) & 0xFF,
          (key >> 16) & 0xFF,
          (key >> 8) & 0xFF,
          key & 0xFF,
        ]))
    .toList();

Future<MifareClassicType> mfClassicGetType(
    ChameleonCommunicator communicator) async {
  if ((await communicator.send14ARaw(Uint8List.fromList([0x60, 255]),
              checkResponseCrc: false))
          .length ==
      4) {
    return MifareClassicType.m4k;
  }

  if ((await communicator.send14ARaw(Uint8List.fromList([0x60, 80]),
              checkResponseCrc: false))
          .length ==
      4) {
    return MifareClassicType.m2k;
  }

  if ((await communicator.send14ARaw(Uint8List.fromList([0x60, 63]),
              checkResponseCrc: false))
          .length ==
      4) {
    return MifareClassicType.m1k;
  }

  return MifareClassicType.mini;
}

Future<bool> mfClassicHasBackdoor(ChameleonCommunicator communicator) async {
  Uint8List data = await communicator.send14ARaw(
      Uint8List.fromList([0x64, 0x00]),
      autoSelect: true,
      checkResponseCrc: false);

  if (data.length != 4) {
    return false;
  }

  (int, NestedNonces, NestedNonces, Uint8List)? response =
      await communicator.getMf1StaticEncryptedNestedAcquire(sectorCount: 1);

  return response != null;
}

String mfClassicGetPrngType(NTLevel ntLevel, AppLocalizations localizations) {
  if (ntLevel == NTLevel.hard) {
    return localizations.prng_type_hard;
  } else if (ntLevel == NTLevel.weak) {
    return localizations.prng_type_weak;
  } else if (ntLevel == NTLevel.static) {
    return localizations.prng_type_static;
  }

  return localizations.unknown;
}

Future<bool> mfClassicIsStaticEncrypted(ChameleonCommunicator communicator,
    int block, int keyType, Uint8List knownKey) async {
  NestedNonces nonces = NestedNonces(nonces: []);
  var collectedNonces = await communicator.getMf1NestedNonces(
      block, 0x60 + keyType, knownKey, 3, 0x61,
      level: NTLevel.hard);
  nonces.nonces.addAll(collectedNonces.nonces);
  return nonces.getNoncesInfo()[1] == 1;
}

List<Uint8List> mfClassicConvertKeys(List<int> keys) {
  List<Uint8List> out = [];

  for (var key in keys) {
    out.add(u64ToBytes(key).sublist(2, 8));
  }

  return out;
}

String mfClassicGetName(
    MifareClassicType type, AppLocalizations localizations) {
  if (type == MifareClassicType.m1k) {
    return "1K";
  } else if (type == MifareClassicType.m2k) {
    return "2K";
  } else if (type == MifareClassicType.m4k) {
    return "4K";
  } else if (type == MifareClassicType.mini) {
    return "Mini";
  } else {
    return localizations.unknown;
  }
}

int mfClassicGetSectorCount(MifareClassicType type, {bool isEV1 = false}) {
  if (type == MifareClassicType.m1k) {
    return (isEV1) ? 18 : 16;
  } else if (type == MifareClassicType.m2k) {
    return 32;
  } else if (type == MifareClassicType.m4k) {
    return 40;
  } else if (type == MifareClassicType.mini) {
    return 5;
  } else {
    return 0;
  }
}

int mfClassicGetBlockCount(MifareClassicType type, {bool isEV1 = false}) {
  if (type == MifareClassicType.m1k) {
    return (isEV1) ? 72 : 64;
  } else if (type == MifareClassicType.m2k) {
    return 128;
  } else if (type == MifareClassicType.m4k) {
    return 256;
  } else if (type == MifareClassicType.mini) {
    return 20;
  } else {
    return 0;
  }
}

MifareClassicType mfClassicGetCardTypeByBlockCount(int blockCount) {
  if (blockCount == 64 || blockCount == 72) {
    return MifareClassicType.m1k;
  } else if (blockCount == 128) {
    return MifareClassicType.m2k;
  } else if (blockCount == 256) {
    return MifareClassicType.m4k;
  } else if (blockCount == 20) {
    return MifareClassicType.mini;
  } else {
    return MifareClassicType.none;
  }
}

int mfClassicGetSectorTrailerBlockBySector(int sector) {
  if (sector < 32) {
    return sector * 4 + 3;
  } else {
    return 32 * 4 + (sector - 32) * 16 + 15;
  }
}

int mfClassicGetSectorTrailerBlockInSector(int sector) {
  return sector < 32 ? 3 : 15;
}

int mfClassicGetBlockCountBySector(int sector) {
  return sector < 32 ? 4 : 16;
}

int mfClassicGetFirstBlockCountBySector(int sector) {
  if (sector < 32) {
    return sector * 4;
  } else {
    return 32 * 4 + (sector - 32) * 16;
  }
}

int mfClassicGetSectorByBlock(int block) {
  if (block < 128) {
    return block ~/ 4;
  } else {
    return 32 + (block - 128) ~/ 16;
  }
}

TagType mfClassicGetChameleonTagType(MifareClassicType type) {
  if (type == MifareClassicType.m1k) {
    return TagType.mifare1K;
  } else if (type == MifareClassicType.m2k) {
    return TagType.mifare2K;
  } else if (type == MifareClassicType.m4k) {
    return TagType.mifare4K;
  } else if (type == MifareClassicType.mini) {
    return TagType.mifareMini;
  } else {
    return TagType.unknown;
  }
}

MifareClassicType chameleonTagTypeGetMfClassicType(TagType type) {
  if (type == TagType.mifare1K) {
    return MifareClassicType.m1k;
  } else if (type == TagType.mifare2K) {
    return MifareClassicType.m2k;
  } else if (type == TagType.mifare4K) {
    return MifareClassicType.m4k;
  } else if (type == TagType.mifareMini) {
    return MifareClassicType.mini;
  } else {
    return MifareClassicType.none;
  }
}

bool chameleonTagSaveCheckForMifareClassicEV1(CardSave tag) {
  return tag.tag == TagType.mifare1K &&
      tag.data.length >= 71 &&
      tag.data[71].isNotEmpty;
}

bool isMifareClassic(TagType type) {
  return [
    TagType.mifare1K,
    TagType.mifare2K,
    TagType.mifare4K,
    TagType.mifareMini
  ].contains(type);
}

List<Uint8List> mfClassicGetKeysFromDump(List<Uint8List> dump) {
  List<Uint8List> keys = [];

  for (var sector = 0; sector < 40; sector++) {
    var block = mfClassicGetSectorTrailerBlockBySector(sector);
    if (dump.length > block && dump[block].isNotEmpty) {
      keys.add(dump[block].sublist(0, 6));
      keys.add(dump[block].sublist(10, 16));
    }
  }

  return keys;
}

typedef FilterResult = (List<int>, List<int>);

class _FilterKeysParams {
  final SendPort sendPort;
  final List<int> keys1;
  final List<int> keys2;
  final int nt1;
  final int nt2;
  _FilterKeysParams(
    this.sendPort,
    this.keys1,
    this.keys2,
    this.nt1,
    this.nt2,
  );
}

class _FindParams {
  final SendPort sendPort;
  final int nt1;
  final int key1;
  final int nt2;
  final List<int> keys2;
  _FindParams(
    this.sendPort,
    this.nt1,
    this.key1,
    this.nt2,
    this.keys2,
  );
}

class StaticEncryptedKeysFilter {
  static final List<int> _iLfsr16 = List<int>.filled(1 << 16, 0);
  static final List<int> _sLfsr16 = List<int>.filled(1 << 16, 0);
  static bool _initialized = false;

  static void _initLfsr16Table() {
    if (_initialized) return;

    int x = 1;
    for (int i = 1; i <= 0xFFFF; i++) {
      int index = ((x & 0xFF) << 8) | (x >> 8);
      _iLfsr16[index] = i;
      _sLfsr16[i] = index;
      x = (x >> 1) | (((x ^ (x >> 2) ^ (x >> 3) ^ (x >> 5)) & 1) << 15);
    }
    _initialized = true;
  }

  static int _prevLfsr16(int nonce) {
    int i = _iLfsr16[nonce & 0xFFFF];
    if (i == 0 || i == 1) {
      i = 0xFFFF;
    } else {
      i--;
    }
    return _sLfsr16[i];
  }

  static int _computeSeednt16Nt32(int nt32, int key) {
    const List<int> a = [0, 8, 9, 4, 6, 11, 1, 15, 12, 5, 2, 13, 10, 14, 3, 7];
    const List<int> b = [0, 13, 1, 14, 4, 10, 15, 7, 5, 3, 8, 6, 9, 2, 12, 11];

    int nt = (nt32 >> 16) & 0xFFFF;
    int prev = 14;

    for (int i = 0; i < prev; i++) {
      nt = _prevLfsr16(nt);
    }

    int prevoff = 8;
    bool odd = true;

    for (int i = 0; i < 48; i += 8) {
      if (odd) {
        nt ^= a[(key >> i) & 0xF];
        nt ^= (b[(key >> (i + 4)) & 0xF] << 4);
      } else {
        nt ^= b[(key >> i) & 0xF];
        nt ^= (a[(key >> (i + 4)) & 0xF] << 4);
      }
      odd = !odd;
      prev += prevoff;
      for (int j = 0; j < prevoff; j++) {
        nt = _prevLfsr16(nt);
      }
      nt &= 0xFFFF;
    }

    return nt;
  }

  // Rewritten from staticnested_2x1nt_rf08s by Doegox
  // https://github.com/RfidResearchGroup/proxmark3/blob/master/tools/mfc/card_only/staticnested_2x1nt_rf08s.c
  static (List<int>, List<int>) filterKeys(
      List<int> keys1, List<int> keys2, int nt1, int nt2) {
    _initLfsr16Table();

    final List<int> seednt1 = [];
    final List<bool> filterKeys1 = List<bool>.filled(keys1.length, false);
    final List<bool> filterKeys2 = List<bool>.filled(keys2.length, false);

    for (int i = 0; i < keys1.length; i++) {
      seednt1.add(_computeSeednt16Nt32(nt1, keys1[i]));
    }

    for (int j = 0; j < keys2.length; j++) {
      int seednt2 = _computeSeednt16Nt32(nt2, keys2[j]);
      for (int i = 0; i < keys1.length; i++) {
        if (seednt2 == seednt1[i]) {
          filterKeys1[i] = true;
          filterKeys2[j] = true;
        }
      }
    }

    final List<int> filteredKeys1 = [];
    final List<int> filteredKeys2 = [];

    for (int i = 0; i < keys1.length; i++) {
      if (filterKeys1[i]) {
        filteredKeys1.add(keys1[i]);
      }
    }

    for (int j = 0; j < keys2.length; j++) {
      if (filterKeys2[j]) {
        filteredKeys2.add(keys2[j]);
      }
    }

    return (filteredKeys1, filteredKeys2);
  }

  // Rewritten from staticnested_2x1nt_rf08s_1key by Doegox
  // https://github.com/RfidResearchGroup/proxmark3/blob/master/tools/mfc/card_only/staticnested_2x1nt_rf08s_1key.c
  static List<int> findMatchingKeys(
      int nt1, int key1, int nt2, List<int> keys2) {
    _initLfsr16Table();

    final List<int> matchingKeys = [];
    int seednt1 = _computeSeednt16Nt32(nt1, key1);

    for (int i = 0; i < keys2.length; i++) {
      if (seednt1 == _computeSeednt16Nt32(nt2, keys2[i])) {
        matchingKeys.add(keys2[i]);
      }
    }

    return matchingKeys;
  }
}

extension StaticEncryptedKeysFilterAsync on StaticEncryptedKeysFilter {
  static Future<FilterResult> filterKeys(
    List<int> keys1,
    List<int> keys2,
    int nt1,
    int nt2,
  ) async {
    final receivePort = ReceivePort();
    await Isolate.spawn<_FilterKeysParams>(
      _filterKeysEntry,
      _FilterKeysParams(
        receivePort.sendPort,
        keys1,
        keys2,
        nt1,
        nt2,
      ),
    );
    final result = await receivePort.first as FilterResult;
    receivePort.close();
    return result;
  }

  static void _filterKeysEntry(_FilterKeysParams params) {
    final r = StaticEncryptedKeysFilter.filterKeys(
      params.keys1,
      params.keys2,
      params.nt1,
      params.nt2,
    );
    params.sendPort.send(r);
  }

  static Future<List<int>> findMatchingKeys(
    int nt1,
    int key1,
    int nt2,
    List<int> keys2,
  ) async {
    final receivePort = ReceivePort();
    await Isolate.spawn<_FindParams>(
      _findEntry,
      _FindParams(
        receivePort.sendPort,
        nt1,
        key1,
        nt2,
        keys2,
      ),
    );
    final result = await receivePort.first as List<int>;
    receivePort.close();
    return result;
  }

  static void _findEntry(_FindParams params) {
    final r = StaticEncryptedKeysFilter.findMatchingKeys(
      params.nt1,
      params.key1,
      params.nt2,
      params.keys2,
    );
    params.sendPort.send(r);
  }
}

Uint8List mfClassicGenerateFirstBlock(Uint8List uid, int sak, Uint8List atqa) {
  final block0 = Uint8List(16);
  if (uid.length == 4) {
    block0.setAll(0, uid);
    block0[4] = calculateBcc(uid);
    block0[5] = sak + 0x80;
    block0.setAll(6, atqa);
    block0.setAll(8, [0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69]);
  } else if (uid.length == 7) {
    block0.setAll(0, uid);
    block0[7] = sak + 0x80;
    block0.setAll(8, atqa);
    block0.setAll(10, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
  }
  return block0;
}
