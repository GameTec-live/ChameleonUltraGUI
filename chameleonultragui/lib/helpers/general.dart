import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart' as sizer;

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

Uint8List u64ToBytes(int u64) {
  if (!kIsWeb) {
    // Uint64 accessor not supported by dart2js
    final ByteData byteData = ByteData(8)..setUint64(0, u64, Endian.big);
    return byteData.buffer.asUint8List();
  }

  final bigInt = BigInt.from(u64);
  final data = Uint8List((bigInt.bitLength / 8).ceil());
  var tmp = bigInt;

  for (var i = 1; i <= data.lengthInBytes; i++) {
    final int8 = tmp.toUnsigned(8).toInt();
    data[i - 1] = int8;
    tmp = tmp >> 8;
  }

  return data;
}


bool isValidHexString(String hexString) {
  final hexPattern = RegExp(r'^[A-Fa-f0-9]+$');
  return hexPattern.hasMatch(hexString);
}

int calculateCRC32(List<int> toTransmit, int crcInt) {
  List<BigInt> crcTable = List<BigInt>.filled(256, BigInt.zero);
  BigInt two32 = BigInt.from(0xFFFFFFFF);
  BigInt crc = BigInt.from(crcInt);

  for (int i = 0; i < 256; i++) {
    var c = i;
    for (var j = 0; j < 8; j++) {
      if ((c & 1) != 0) {
        c = 0xEDB88320 ^ (c >> 1);
      } else {
        c = c >> 1;
      }
    }
    crcTable[i] = BigInt.from(c);
  }

  crc = two32 - crc;

  for (var byteToTransmit in toTransmit) {
    var byte = BigInt.from(byteToTransmit);
    crc = (crc >> 8) ^ crcTable[((crc ^ byte) & BigInt.from(0xFF)).toInt()];
  }

  crc = crc ^ two32;

  return crc.toInt();
}

TagType numberToTagType(int type) {
  for (var tag in TagType.values) {
    if (tag.value == type) {
      return tag;
    }
  }

  return TagType.unknown;
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


/// This method fixes an issue in sizer_pro cause it swaps x/y axis on any platform atm
/// Default width for gridCell is 400, it's somewhat arbitrary but looks to be a good fit 
int calculateCrossAxisCount({ int gridCellWidth = 400 }) {
  return max(1, (sizer.Device.width / gridCellWidth).floor());
}

bool isUrl(String url, {
  List<String> allowedSchemes = const ['https'],
  bool Function(Uri uri)? more,
}) {
  try {
    var uri = Uri.parse(url);

    final isValid = 
      allowedSchemes.any((scheme) => uri.isScheme(scheme))
      && uri.host != ''
      && uri.path != ''
      && more!(uri);

    return isValid;
  } catch (_) {}

  return false;
}
