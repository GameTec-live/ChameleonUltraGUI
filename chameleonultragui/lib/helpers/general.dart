import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sizer_pro/sizer.dart';

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

int calculateCRC32(List<int> data) {
  Uint8List bytes = Uint8List.fromList(data);
  List<BigInt> crcTable = generateCRCTable();
  BigInt crc = BigInt.from(0xFFFFFFFF);

  for (int i = 0; i < bytes.length; i++) {
    crc = (crc >> 8) ^ crcTable[(((crc ^ BigInt.from(bytes[i]))) & BigInt.from(0xFF)).toInt()];
  }

  crc = crc ^ BigInt.from(0xFFFFFFFF);
  return crc.toInt();
}

List<BigInt> generateCRCTable() {
  var bigOne = BigInt.from(1);

  List<BigInt> crcTable = List.empty(growable: true);
  for (int i = 0; i < 256; i++) {
    BigInt crc = BigInt.from(i);
    for (int j = 0; j < 8; j++) {
      if ((crc & bigOne) == bigOne) {
        crc = (crc >> 1) ^ BigInt.from(0xEDB88320);
      } else {
        crc = crc >> 1;
      }
    }
    crcTable.add(crc);
  }
  return crcTable;
}

ChameleonTag numberToChameleonTag(int type) {
  for (var tag in ChameleonTag.values) {
    if (tag.value == type) {
      return tag;
    }
  }

  return ChameleonTag.unknown;
}

ChameleonTag getTagTypeByValue(int value) {
  return ChameleonTag.values.firstWhere((element) => element.value == value,
      orElse: () => ChameleonTag.unknown);
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
// TODO: remove this fix after https://github.com/jinosh05/sizer_pro/pull/1 is merged
int calculateCrossAxisCount({ int gridCellWidth = 400 }) {
  if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
    return max(1, (SizerUtil.width / gridCellWidth).floor());
  }

  // use height instead of width cause they are swapped
  return max(1, (SizerUtil.height / gridCellWidth).floor());
}
