import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Mifare Classic keys of all types
final gMifareClassicKeysList = {
  0xFFFFFFFFFFFF, 
  0xA0A1A2A3A4A5, 
  0xD3F7D3F7D3F7, 
  0x4B791BEA7BCC, 
  0x5C8FF9990DA2, 
  0xD01AFEEB890A, 
  0x75CCB59C9BED, 
  0xFC00018778F7, 
  0x6471A5EF2D1A, 
  0x4E3552426B32, 
  0xEF1232AB18A0, 
  0xB7BF0C13066E, 
  0x135B88A94B8B, 
  0x2A2C13CC242A, 
  0x5A7A52D5E20D, 
  0x314B49474956, 
  0x564C505F4D41, 
  0x021209197591, 
  0x484558414354, 
  0xEC0A9B1A9E06, 
  0x66B31E64CA4B, 
  0x97F5DA640B18, 
  0xA8844B0BCA06, 
  0xE4410EF8ED2D, 
  0x857464D3AAD1, 
  0x08B386463229, 
  0xE00000000000, 
  0x199404281970, 
  0x199404281998, 
  0x6A1987C40A21, 
  0x7F33625BC129, 
  0x484944204953, 
  0x204752454154, 
  0x3B7E4FD575AD, 
  0x11496F97752A, 
  0x3E65E4FB65B3, 
  0x000000000000, 
  0xF00000000000, 
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
  0xA64598A77478,
  0x26940B21FF5D,
  0xFC00018778F7,
  0x00000FFE2488,
  0x5C598C9C58B5,
  0xE4D2770A89BE,
  0x434F4D4D4F41,
  0x434F4D4D4F42,
  0x47524F555041,
  0x47524F555042,
  0x505249564141,
  0x505249564142,
  0x0297927C0F77,
  0xEE0042F88840,
  0x722BFCC5375F,
  0xF1D83F964314,
  0x54726176656C,
  0x776974687573,
  0x4AF9D7ADEBE4,
  0x2BA9621E0A36,
  0x000000000001,
  0x123456789ABC,
  0xB127C6F41436,
  0x12F2EE3478C1,
  0x34D1DF9934C5,
  0x55F5A5DD38C9,
  0xF1A97341A9FC,
  0x33F974B42769,
  0x14D446E33363,
  0xC934FE34D934,
  0x1999A3554A55,
  0x27DD91F1FCF1,
  0xA94133013401,
  0x99C636334433,
  0x43AB19EF5C31,
  0xA053A292A4AF,
  0x505249565441,
  0x505249565442,
  0xBD493A3962B6,
  0x010203040506,
  0x111111111111,
  0x222222222222,
  0x333333333333,
  0x444444444444,
  0x555555555555,
  0x666666666666,
  0x777777777777,
  0x888888888888,
  0x999999999999,
  0xAAAAAAAAAAAA,
  0xBBBBBBBBBBBB,
  0xCCCCCCCCCCCC,
  0xDDDDDDDDDDDD,
  0xEEEEEEEEEEEE,
  0x0123456789AB,
  0x000000000002,
  0x00000000000A,
  0x00000000000B,
  0x100000000000,
  0x200000000000,
  0xA00000000000,
  0xB00000000000,
  0x2900AAC52BC3,
  0xA58AB5619631,
  0xD23C1CB1216E,
  0x4BB29463DC29,
  0x3E173F64C01C,
  0x6A0D531DA1A7,
  0x03F9067646AE,
  0x707B11FC1481,
  0xF3A524B7A7B3,
  0x09074A146605,
  0xB6803136F5AF,
  0x035C70558D7B,
  0x0A1B6C50E04E,
  0x6C273F431564,
  0x8FD6D76742DC,
  0x12AB4C37BB8B,
  0x76E450094393,
  0x216024C49EDF,
  0x316B8FAA12EF,
  0xE9AE90885C39,
  0xA514B797B373,
  0x7C9FB8474242,
  0xD44CFC178460,
  0x453857395635,
  0x81CC25EBBB6A,
  0xD213B093B79A,
  0x1352C68F7A56,
  0x05C301C8795A,
  0xC2A0105EB028,
  0x9A677289564D,
  0x0000FFFFFFFF,
  0x593367486137,
  0xFFF011223358,
  0x4663ACD2FFFF,
  0x6BE9314930D8,
  0xF0FE56621A42,
  0xA1670589B2AF,
  0xF4CE4AF888AE,
  0x5AF445D2B87A,
  0x8C187E78EE9C,
  0xEDC317193709,
  0xFF9F11223358,
  0x307448829EBC,
  0x75FAB77E2E5B,
  0x32F093536677,
  0x3351916B5A77,
  0xDDDAA35A9749,
  0xFE2A42E85CA8,
  0x186C59E6AFC9,
  0x34635A313344,
  0x336E34CC2177,
  0x353038383134,
  0x97D77FAE77D3,
  0x9D0D0A829F49,
  0x16901CB400BC,
  0x6A6C80423226,
  0x2E0F00700000,
  0xBB7923232725,
  0xA95BD5BB4FC5,
  0xB099335628DF,
  0xA34DA4FAC6C8,
  0xAD7C2A07114B,
  0x53864975068A,
  0x549945110B6C,
  0xB6303CD5B2C6,
  0xB0B1B2B3B4B5,
  0xAFE444C4BCAA,
  0xB80CC6DE9A03,
  0xA833FE5A4B55,
  0xB533CCD5F6BF,
  0xB7513BFF587C,
  0xB6DF25353654,
  0x9128A4EF4C05,
  0xA9D4B933B07A,
  0xA000D42D2445,
  0xAA5B6C7D88B4,
  0xB5ADEFCA46C4,
  0xBF3FE47637EC,
  0xB290401B0CAD,
  0xAD11006B0601,
  0xA0A1A2A8A4A5,
  0x0D6057E8133B,
  0xD3F3B958B8A3,
  0x6A68A7D83E11,
  0x7C469FE86855,
  0xE4410EF8ED2D,
  0x3E120568A35C,
  0xCE99FBC8BD26,
  0x2196FAD8115B,
  0x009FB42D98ED,
  0x002E626E2820,
  0x038B5F9B5A2A,
  0x04DC35277635,
  0x0C420A20E056,
  0x152FD0C420A7,
  0x296FC317A513,
  0x29C35FA068FB,
  0x31BEC3D9E510,
  0x462225CD34CF,
  0x4B7CB25354D3,
  0x5583698DF085,
  0x578A9ADA41E3,
  0x6F95887A4FD3,
  0x7600E889ADF9,
  0x86120E488ABF,
  0x8818A9C5D406,
  0x8C90C70CFF4A,
  0x8E65B3AF7D22,
  0x9764FEC3154A,
  0x9BA241DB3F56,
  0xAD2BDC097023,
  0xB0A2AAF3A1BA,
  0xB69D40D1A439,
  0xC956C3B80DA3,
  0xCA96A487DE0B,
  0xD0A4131FB290,
  0xD27058C6E2C7,
  0xE19504C39461,
  0xFA1FBB3F0F1F,
  0xFF16014FEFC7,
  0x000131b93f28,
  0xFF75AFDA5A3C,
  0x558AAD64EB5B,
  0x518108E061E2,
  0xFCDDF7767C10,
  0xA6B3F6C8F1D4,
  0xB1C4A8F7F6E3,
  0x001122334455,
  0x6CA761AB6CA7,
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