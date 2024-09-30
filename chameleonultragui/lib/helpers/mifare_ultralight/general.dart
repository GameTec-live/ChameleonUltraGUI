import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/services.dart';

bool isMifareUltralight(TagType type) {
  return [
    TagType.ntag210,
    TagType.ntag212,
    TagType.ntag213,
    TagType.ntag215,
    TagType.ntag216,
    TagType.ultralight,
    TagType.ultralightC,
    TagType.ultralight11,
    TagType.ultralight21
  ].contains(type);
}

Future<Uint8List> mfUltralightGetVersion(
    ChameleonCommunicator communicator) async {
  return await communicator.send14ARaw(Uint8List.fromList([0x60]));
}

Future<Uint8List> mfUltralightGetSignature(
    ChameleonCommunicator communicator) async {
  Uint8List signature =
      await communicator.send14ARaw(Uint8List.fromList([0x3C, 0x00]));
  if (bytesToHex(signature) == bytesToHex(Uint8List(32))) {
    return Uint8List(0);
  }
  return signature;
}

TagType mfUltralightGetType(Uint8List version) {
  // TODO: detect ultralightC/ntag210/ntag212
  if (version[6] == 0x0B || version[6] == 0x00) {
    return TagType.ultralight11;
  } else if (version[6] == 0x0E) {
    return TagType.ultralight21;
  } else if (version[6] == 0x0F) {
    return TagType.ntag213;
  } else if (version[6] == 0x11) {
    return TagType.ntag215;
  } else if (version[6] == 0x13) {
    return TagType.ntag216;
  }

  return TagType.ultralight;
}

// https://www.nxp.com/docs/en/data-sheet/MF0ICU2.pdf
// https://www.nxp.com/docs/en/data-sheet/MF0ULX1.pdf
// https://www.nxp.com/docs/en/data-sheet/NTAG210_212.pdf
// https://www.nxp.com/docs/en/data-sheet/NTAG213_215_216.pdf

int mfUltralightGetPagesCount(TagType type) {
  if (type == TagType.ultralight) {
    return 16;
  } else if (type == TagType.ultralightC) {
    return 48;
  } else if (type == TagType.ultralight11) {
    return 20;
  } else if (type == TagType.ultralight21) {
    return 41;
  } else if (type == TagType.ntag210) {
    return 20;
  } else if (type == TagType.ntag212) {
    return 41;
  } else if (type == TagType.ntag213) {
    return 45;
  } else if (type == TagType.ntag215) {
    return 135;
  } else if (type == TagType.ntag216) {
    return 231;
  }
  return 0;
}

int mfUltralightGetPasswordPage(TagType type) {
  if (type == TagType.ultralight) {
    return 0; // Don't have password support
  } else if (type == TagType.ultralightC) {
    return 0; // 44 to 47, custom logic required for Ultralight C
  } else if (type == TagType.ultralight11) {
    return 18;
  } else if (type == TagType.ultralight21) {
    return 39;
  } else if (type == TagType.ntag210) {
    return 18;
  } else if (type == TagType.ntag212) {
    return 39;
  } else if (type == TagType.ntag213) {
    return 43;
  } else if (type == TagType.ntag215) {
    return 133;
  } else if (type == TagType.ntag216) {
    return 229;
  }
  return 0;
}
