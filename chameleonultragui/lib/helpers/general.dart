import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:provider/provider.dart';

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
  hex = hex.replaceAll(" ", "");
  List<int> bytes = [];
  for (int i = 0; i < hex.length; i += 2) {
    int byte = int.parse(hex.substring(i, i + 2), radix: 16);
    bytes.add(byte);
  }
  return Uint8List.fromList(bytes);
}

int bytesToU8(Uint8List byteArray) {
  return byteArray.buffer.asByteData().getUint8(0);
}

int bytesToU16(Uint8List byteArray) {
  return byteArray.buffer.asByteData().getUint16(0, Endian.big);
}

int bytesToU32(Uint8List byteArray) {
  return byteArray.buffer.asByteData().getUint32(0, Endian.big);
}

int bytesToU64(Uint8List byteArray) {
  return byteArray.buffer.asByteData().getUint64(0, Endian.big);
}

int parityToInt(int ntParErr) {
  return int.parse([
    (ntParErr >> 3) & 1,
    (ntParErr >> 2) & 1,
    (ntParErr >> 1) & 1,
    ntParErr & 1
  ].join(''));
}

int _swapEndian(int x) {
  x = (x >> 8 & 0xff00ff) | (x & 0xff00ff) << 8;
  x = (x >> 16) | (x << 16);
  return x & 0xffffffff;
}

int prngSuccessor(int x, int n) {
  x = _swapEndian(x);

  while (n > 0) {
    x = (x >> 1) | (((x >> 16) ^ (x >> 18) ^ (x >> 19) ^ (x >> 21)) << 31);
    x = x & 0xffffffff;
    n--;
  }

  return _swapEndian(x);
}

int reconstructFullNt(Uint8List responseData, int offset) {
  int nt = bytesToU16(responseData.sublist(offset, offset + 2));

  return (nt << 16) | prngSuccessor(nt, 16);
}

Uint8List u8ToBytes(int u8) {
  final ByteData byteData = ByteData(1)..setUint8(0, u8);
  return byteData.buffer.asUint8List();
}

Uint8List u16ToBytes(int u16) {
  final ByteData byteData = ByteData(2)..setUint16(0, u16);
  return byteData.buffer.asUint8List();
}

Uint8List u32ToBytes(int u32) {
  final ByteData byteData = ByteData(4)..setUint32(0, u32);
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

String chameleonTagToString(TagType tag, AppLocalizations localizations) {
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
  } else if (tag == TagType.em410X16) {
    return "EM410X (16)";
  } else if (tag == TagType.em410X32) {
    return "EM410X (32)";
  } else if (tag == TagType.em410X64) {
    return "EM410X (64)";
  } else if (tag == TagType.em410XElectra) {
    return "EM410X Electra";
  } else if (tag == TagType.hidProx) {
    return "HID Prox";
  } else if (tag == TagType.viking) {
    return "Viking";
  } else if (tag == TagType.ntag210) {
    return "NTAG210";
  } else if (tag == TagType.ntag212) {
    return "NTAG212";
  } else if (tag == TagType.ntag213) {
    return "NTAG213";
  } else if (tag == TagType.ntag215) {
    return "NTAG215";
  } else if (tag == TagType.ntag216) {
    return "NTAG216";
  } else if (tag == TagType.ultralight) {
    return "Ultralight";
  } else if (tag == TagType.ultralightC) {
    return "Ultralight C";
  } else if (tag == TagType.ultralight11) {
    return "Ultralight EV1 (20)";
  } else if (tag == TagType.ultralight21) {
    return "Ultralight EV1 (41)";
  } else {
    return localizations.unknown;
  }
}

String chameleonCardToString(CardSave card, AppLocalizations localizations) {
  String name = chameleonTagToString(card.tag, localizations);

  if (chameleonTagSaveCheckForMifareClassicEV1(card)) {
    name += " EV1";
  }

  return name;
}

TagType numberToChameleonTag(int type) {
  for (var value in TagType.values) {
    if (value.value == type) {
      return value;
    }
  }

  return TagType.unknown;
}

List<TagType> getTagTypes() {
  return TagType.values;
}

TagType getTagTypeByValue(int value) {
  return TagType.values.firstWhere((element) => element.value == value,
      orElse: () => TagType.unknown);
}

String colorToHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
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
  if (getTagTypesByFrequency(TagFrequency.lf).contains(tag)) {
    return TagFrequency.lf;
  } else {
    return TagFrequency.hf;
  }
}

int calculateBcc(Uint8List data) {
  int bcc = 0;
  for (int byte in data) {
    bcc ^= byte;
  }
  return bcc;
}

int getBlockCountForTagType(TagType tagType) {
  switch (tagType) {
    case TagType.mifareMini:
      return 20;
    case TagType.mifare1K:
      return 64;
    case TagType.mifare2K:
      return 128;
    case TagType.mifare4K:
      return 256;
    case TagType.ultralight:
    case TagType.ultralightC:
      return 16;
    case TagType.ultralight11:
    case TagType.ultralight21:
      return 20;
    case TagType.ntag210:
      return 16;
    case TagType.ntag212:
      return 41;
    case TagType.ntag213:
      return 45;
    case TagType.ntag215:
      return 135;
    case TagType.ntag216:
      return 231;
    default:
      return 64;
  }
}

int getMemorySizeForTagType(TagType tagType) {
  switch (tagType) {
    case TagType.ultralight:
    case TagType.ultralightC:
      return 64;
    case TagType.ultralight11:
    case TagType.ultralight21:
      return 80;
    case TagType.ntag210:
      return 64;
    case TagType.ntag212:
      return 164;
    case TagType.ntag213:
      return 180;
    case TagType.ntag215:
      return 540;
    case TagType.ntag216:
      return 924;
    default:
      return 64;
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
  } else if (value == 4) {
    return ButtonConfig.chargeStatus;
  } else {
    return ButtonConfig.disable;
  }
}

AnimationSetting getAnimationModeType(int value) {
  if (value == 0) {
    return AnimationSetting.full;
  } else if (value == 1) {
    return AnimationSetting.minimal;
  } else if (value == 2) {
    return AnimationSetting.none;
  } else if (value == 3) {
    return AnimationSetting.symmetric;
  } else {
    return AnimationSetting.none;
  }
}

Future<void> saveTag(CardSave tag, BuildContext context, bool bin) async {
  var localizations = AppLocalizations.of(context)!;
  if (bin) {
    List<int> tagDump = [];
    for (var block in tag.data) {
      tagDump.addAll(block);
    }
    try {
      await FileSaver.instance.saveAs(
          name: tag.name,
          bytes: Uint8List.fromList(tagDump),
          ext: 'bin',
          mimeType: MimeType.other);
    } on UnimplementedError catch (_) {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '${localizations.output_file}:',
        fileName: '${tag.name}.bin',
      );

      if (outputFile != null) {
        var file = File(outputFile);
        await file.writeAsBytes(Uint8List.fromList(tagDump));
      }
    }
  } else {
    try {
      await FileSaver.instance.saveAs(
          name: tag.name,
          bytes: const Utf8Encoder().convert(tag.toJson()),
          ext: 'json',
          mimeType: MimeType.other);
    } on UnimplementedError catch (_) {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '${localizations.output_file}:',
        fileName: '${tag.name}.json',
      );

      if (outputFile != null) {
        var file = File(outputFile);
        await file.writeAsBytes(const Utf8Encoder().convert(tag.toJson()));
      }
    }
  }
}

void updateNavigationRailWidth(BuildContext context) async {
  if (context.mounted) {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    await asyncSleep(500);
    appState.navigationRailSize =
        appState.navigationRailKey.currentContext!.size;
    appState.changesMade();
  }
}

List<TagType> getTagTypesByFrequency(TagFrequency frequency) {
  if (frequency == TagFrequency.hf) {
    return [
      TagType.mifare1K,
      TagType.mifare2K,
      TagType.mifare4K,
      TagType.mifareMini,
      TagType.ntag210,
      TagType.ntag212,
      TagType.ntag213,
      TagType.ntag215,
      TagType.ntag216,
      TagType.ultralight,
      TagType.ultralightC,
      TagType.ultralight11,
      TagType.ultralight21
    ];
  } else if (frequency == TagFrequency.lf) {
    return [
      TagType.em410X,
      TagType.em410X16,
      TagType.em410X32,
      TagType.em410X64,
      TagType.em410XElectra,
      TagType.hidProx,
      TagType.viking
    ];
  }

  return [TagType.unknown];
}

int evenParity32(int n) {
  int ret = 0;
  for (int i = 0; i < 32; i++) {
    if ((n & (1 << i)) != 0) {
      ret++;
    }
  }
  return ret % 2;
}

TagType getTagTypeByDumpSize(int size) {
  switch (size) {
    // Mifare Classic
    case 320:
      return TagType.mifareMini;
    case 1024:
      return TagType.mifare1K;
    case 1088: // EV1
    case 2048:
      return TagType.mifare2K;
    case 4096:
      return TagType.mifare4K;

    // Ultralight/NTAG
    case 64:
      return TagType.ultralight;
    case 192:
      return TagType.ultralightC;
    case 80:
      return TagType.ultralight11; // also NTAG210
    case 164:
      return TagType.ultralight21; // also NTAG212
    case 180:
      return TagType.ntag213;
    case 540:
      return TagType.ntag215;
    case 924:
      return TagType.ntag216;
  }

  return TagType.unknown;
}

const _hidProxTypeNames = <int, String>{
  1: "HID H10301 26-bit",
  2: "Indala 26-bit",
  3: "Indala 27-bit",
  4: "Indala ASC 27-bit",
  5: "Tecom 27-bit",
  6: "2804 Wiegand 28-bit",
  7: "Indala 29-bit",
  8: "ATS Wiegand 30-bit",
  9: "HID ADT 31-bit",
  10: "HID Check Point 32-bit",
  11: "HID Hewlett-Packard 32-bit",
  12: "Kastle 32-bit",
  13: "Indala/Kantech KFS 32-bit",
  14: "Wiegand 32-bit",
  15: "HID D10202 33-bit",
  16: "HID H10306 34-bit",
  17: "Honeywell/Northern N10002 34-bit",
  18: "Indala Optus 34-bit",
  19: "Cardkey Smartpass 34-bit",
  20: "BQT 34-bit",
  21: "HID Corporate 1000 35-bit Std",
  22: "HID KeyScan 36-bit",
  23: "HID Simplex 36-bit",
  24: "HID 36-bit Siemens",
  25: "HID H10320 37-bit BCD",
  26: "HID H10302 37-bit huge ID",
  27: "HID H10304 37-bit",
  28: "HID P10004 37-bit PCSC",
  29: "HID Generic 37-bit",
  30: "PointGuard MDI 37-bit",
  43: "HID 32-B 32-bit",
};

String getNameForHIDProxType(int type) {
  return _hidProxTypeNames[type] ?? "HID format($type)";
}

List<int> getHidProxTypeOptions() {
  final options = _hidProxTypeNames.keys.toList();
  options.sort((a, b) {
    final nameA = _hidProxTypeNames[a] ?? "";
    final nameB = _hidProxTypeNames[b] ?? "";
    final bitsA = _hidProxBitLength(nameA);
    final bitsB = _hidProxBitLength(nameB);
    if (bitsA != bitsB) {
      return bitsA.compareTo(bitsB);
    }
    return nameA.compareTo(nameB);
  });
  return options;
}

int _hidProxBitLength(String name) {
  final match = RegExp(r'(\d+)-bit').firstMatch(name);
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(1) ?? '') ?? 0;
}

LFCard getLFCardFromUID(TagType type, String uid) {
  if (type == TagType.hidProx) {
    return HIDCard.fromUID(uid);
  }

  if (type == TagType.viking) {
    return VikingCard.fromUID(uid);
  }

  return EM410XCard.fromUID(uid, type: type);
}

int uidSizeForLfTag(TagType type) {
  if (type == TagType.em410XElectra) {
    return 13;
  } else if (isEM410X(type)) {
    return 5;
  } else if (type == TagType.hidProx) {
    return 5;
  } else if (type == TagType.viking) {
    return 4;
  }

  return 0;
}

bool isEM410X(TagType type) {
  return [
    TagType.em410X,
    TagType.em410X16,
    TagType.em410X32,
    TagType.em410X64,
    TagType.em410XElectra
  ].contains(type);
}

Future<(HFCardInfo, MifareClassicInfo, MifareUltralightInfo)> readHFInfo(
    BuildContext context, dynamic updateMifareClassicRecovery) async {
  var appState = Provider.of<ChameleonGUIState>(context, listen: false);
  var localizations = AppLocalizations.of(context)!;

  HFCardInfo hfInfo = HFCardInfo();
  MifareClassicInfo mfcInfo = MifareClassicInfo();
  MifareUltralightInfo mfuInfo = MifareUltralightInfo();

  if (!await appState.communicator!.isReaderDeviceMode()) {
    await appState.communicator!.setReaderDeviceMode(true);
  }

  CardData? card = await appState.communicator!.scan14443aTag();

  if (card == null) {
    hfInfo.cardExist = false;
    return (hfInfo, mfcInfo, mfuInfo);
  }

  try {
    TagType type = TagType.unknown;

    if (!await appState.communicator!.detectMf1Support()) {
      (type, mfuInfo) =
          await performMifareUltralightScan(appState.communicator!, mfuInfo);
    } else {
      if (context.mounted) {
        (type, mfcInfo) = await performMifareClassicScan(appState.communicator!,
            mfcInfo, context, updateMifareClassicRecovery);
      }
    }

    hfInfo.uid = bytesToHexSpace(card.uid);
    hfInfo.sak = card.sak.toRadixString(16).padLeft(2, '0').toUpperCase();
    hfInfo.atqa = bytesToHexSpace(card.atqa);
    hfInfo.ats =
        (card.ats.isNotEmpty) ? bytesToHexSpace(card.ats) : localizations.no;
    hfInfo.type = type;
    mfcInfo.state = (mfcInfo.type != MifareClassicType.none)
        ? MifareClassicState.checkKeys
        : MifareClassicState.none;
    hfInfo.tech = chameleonTagToString(type, localizations) +
        (mfcInfo.isEV1 ? " EV1" : "");
  } catch (e) {
    appState.log!.e(e.toString());
    hfInfo.cardExist = false;
  }

  return (hfInfo, mfcInfo, mfuInfo);
}
