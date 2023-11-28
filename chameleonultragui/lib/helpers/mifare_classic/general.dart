import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
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
  0xFC00018778F7, // PUBLIC TRANSPORT
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
  0x97F5DA640B18, // BANGKOK METRO KEY
  0xA8844B0BCA06, // METRO VALENCIA KEY
  0xE4410EF8ED2D, // ARMENIAN METRO
  0x857464D3AAD1, // HTC EINDHOVEN KEY
  0x08B386463229, // TROIKA
  0xE00000000000, // ICOPY
  0x199404281970, // NSP A
  0x199404281998, // NSP B
  0x6A1987C40A21, // SALTO
  0x7F33625BC129, // SALTO
  0x484944204953, // HID
  0x204752454154, // HID
  0x3B7E4FD575AD, // HID
  0x11496F97752A, // HID
  0x3E65E4FB65B3, // GYM
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

MifareClassicType mfClassicGetType(Uint8List atqa, int sak) {
  if ((atqa[1] == 0x44 || atqa[1] == 0x04)) {
    if ((sak == 0x08 || sak == 0x88)) {
      return MifareClassicType.m1k;
    } else if ((sak == 0x38)) {
      return MifareClassicType.m4k;
    } else if (sak == 0x09) {
      return MifareClassicType.mini;
    }
  } else if ((atqa[1] == 0x01) && (atqa[0] == 0x0F) && (sak == 0x01)) {
    //skylanders support
    return MifareClassicType.m1k;
  } else if (((atqa[1] == 0x42 || atqa[1] == 0x02) && (sak == 0x18)) ||
      ((atqa[1] == 0x02 || atqa[1] == 0x08) && (sak == 0x38))) {
    return MifareClassicType.m4k;
  }
  return MifareClassicType.m1k;
}

String mfClassicGetName(MifareClassicType type) {
  if (type == MifareClassicType.m1k) {
    return "1K";
  } else if (type == MifareClassicType.m2k) {
    return "2K";
  } else if (type == MifareClassicType.m4k) {
    return "4K";
  } else if (type == MifareClassicType.mini) {
    return "Mini";
  } else {
    return "Unknown";
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
