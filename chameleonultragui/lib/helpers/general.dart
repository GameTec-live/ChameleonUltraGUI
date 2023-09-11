import 'dart:io';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

Future<void> asyncSleep(int milliseconds) async {
  await Future.delayed(Duration(milliseconds: milliseconds));
}

String bytesToHex(Uint8List bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
}

String bytesToHexSpace(Uint8List bytes) {
  return bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join(' ')
      .toUpperCase();
}

Uint8List hexToBytes(String hex) {
  List<int> bytes = [];
  for (int i = 0; i < hex.length; i += 2) {
    int byte = int.parse(hex.substring(i, i + 2), radix: 16);
    bytes.add(byte);
  }
  return Uint8List.fromList(bytes);
}

int bytesToU32(Uint8List byteArray) {
  return byteArray.buffer.asByteData().getUint32(0, Endian.big);
}

int bytesToU64(Uint8List byteArray) {
  return byteArray.buffer.asByteData().getUint64(0, Endian.big);
}

Uint8List u8ToBytes(int u8) {
  final ByteData byteData = ByteData(1)..setUint8(0, u8);
  return byteData.buffer.asUint8List();
}

Uint8List u64ToBytes(int u64) {
  final ByteData byteData = ByteData(8)..setUint64(0, u64, Endian.big);
  return byteData.buffer.asUint8List();
}

bool isValidHexString(String hexString) {
  final hexPattern = RegExp(r'^[A-Fa-f0-9]+$');
  return hexPattern.hasMatch(hexString);
}

int calculateCRC32(List<int> toTransmit, int crc) {
  Uint32List crcTable = Uint32List(256);

  for (int i = 0; i < 256; i++) {
    var c = i;
    for (var j = 0; j < 8; j++) {
      if ((c & 1) != 0) {
        c = 0xEDB88320 ^ (c >> 1);
      } else {
        c = c >> 1;
      }
    }
    crcTable[i] = c;
  }

  crc = 0xFFFFFFFF - crc;

  for (var byte in toTransmit) {
    crc = (crc >> 8) ^ crcTable[(crc ^ byte) & 0xFF];
  }

  crc = crc ^ 0xFFFFFFFF;

  return crc;
}

String chameleonTagToString(TagType tag) {
  if (tag == TagType.mifareMini) {
    return "Mifare Mini";
  } else if (tag == TagType.mifare1K) {
    return "Mifare Classic 1K";
  } else if (tag == TagType.mifare2K) {
    return "Mifare Classic 2K";
  } else if (tag == TagType.mifare4K) {
    return "Mifare Classic 4K";
  } else if (tag == TagType.em410X) {
    return "EM410X";
  } else if (tag == TagType.ntag213) {
    return "NTAG213";
  } else if (tag == TagType.ntag215) {
    return "NTAG215";
  } else if (tag == TagType.ntag216) {
    return "NTAG216";
  } else {
    return "Unknown";
  }
}

TagType numberToChameleonTag(int type) {
  if (type == TagType.mifareMini.value) {
    return TagType.mifareMini;
  } else if (type == TagType.mifare1K.value) {
    return TagType.mifare1K;
  } else if (type == TagType.mifare2K.value) {
    return TagType.mifare2K;
  } else if (type == TagType.mifare4K.value) {
    return TagType.mifare4K;
  } else if (type == TagType.em410X.value) {
    return TagType.em410X;
  } else if (type == TagType.ntag213.value) {
    return TagType.ntag213;
  } else if (type == TagType.ntag215.value) {
    return TagType.ntag215;
  } else if (type == TagType.ntag216.value) {
    return TagType.ntag216;
  } else {
    return TagType.unknown;
  }
}

TagType getTagTypeByValue(int value) {
  return TagType.values.firstWhere((element) => element.value == value,
      orElse: () => TagType.unknown);
}

String colorToHex(Color color) {
  return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
}

Color hexToColor(String hex) {
  return Color(int.parse(hex.substring(1, 7), radix: 16) + 0xFF000000);
}

String platformToPath() {
  if (Platform.isAndroid) {
    return "android";
  } else if (Platform.isIOS) {
    return "ios";
  } else if (Platform.isLinux) {
    return "linux";
  } else if (Platform.isMacOS) {
    return "macos";
  } else if (Platform.isWindows) {
    return "windows";
  } else {
    return "../";
  }
}

String numToVerCode(int versionCode) {
  int major = (versionCode >> 8) & 0xFF;
  int minor = versionCode & 0xFF;
  return '$major.$minor';
}

TagFrequency chameleonTagToFrequency(TagType tag) {
  if (tag == TagType.em410X) {
    return TagFrequency.lf;
  } else {
    return TagFrequency.hf;
  }
}

class SharedPreferencesLogger extends LogOutput {
  SharedPreferencesProvider? provider;

  SharedPreferencesLogger(this.provider);

  @override
  void output(OutputEvent event) {
    for (var line in event.lines) {
      provider?.addLogLine(line);
    }
  }
}

String chameleonDeviceName(ChameleonDevice device) {
  return (device == ChameleonDevice.ultra) ? "Ultra" : "Lite";
}

class ChameleonLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true;
  }
}

ButtonConfig getButtonConfigType(int value) {
  if (value == 1) {
    return ButtonConfig.cycleForward;
  } else if (value == 2) {
    return ButtonConfig.cycleBackward;
  } else if (value == 3) {
    return ButtonConfig.cloneUID;
  } else {
    return ButtonConfig.disable;
  }
}

AnimationSetting getAnimationModeType(int value) {
  if (value == 0) {
    return AnimationSetting.full;
  } else if (value == 1) {
    return AnimationSetting.minimal;
  } else {
    return AnimationSetting.none;
  }
}
