import 'package:chameleonultragui/helpers/sl1_card_save.dart';

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
  } else if (tag == TagType.pac) {
    return "PAC/Stanley";
  } else if (tag == TagType.ioProx) {
    return "ioProx";
  } else if (tag == TagType.idteck) {
    return "IDTECK";
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
  } else if (tag == TagType.hf14a4) {
    return "ISO14443-4 (T=CL)";
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

Uint8List classicExportBytesForCard(CardSave card) {
  card.validateProfileConsistency();
  if (card.nativeClassicCoverage != null) {
    return card.nativeClassicCoverage!.copy().image();
  }
  if (chameleonTagSaveCheckForMifareClassicEV1(card)) {
    if (card.data.length < 72 ||
        card.data.take(72).any((b) => b.length != 16) ||
        card.data.skip(72).any((b) => b.isNotEmpty)) {
      throw const FormatException(
        'EV1 binary export requires all 72 complete blocks. Export native JSON to retain unknown block positions.',
      );
    }
    return Uint8List.fromList(card.data.take(72).expand((b) => b).toList());
  }
  if (card.sl1Profile != null) {
    return Uint8List.fromList(
      card.sl1Profile!.image().expand((b) => b).toList(),
    );
  }
  return mfClassicGetExportBytes(
    chameleonTagTypeGetMfClassicType(card.tag),
    card.data,
  );
}

Future<bool> saveTag(CardSave tag, BuildContext context, bool bin) async {
  try {
    await _saveTagFile(tag, context, bin);
    return true;
  } catch (error) {
    if (!context.mounted) return false;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Card export failed'),
        content: Text(
          '$error\nExport JSON to preserve incomplete coverage, or acquire a complete image before exporting binary.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return false;
  }
}

Future<void> _saveTagFile(CardSave tag, BuildContext context, bool bin) async {
  tag.validateProfileConsistency();
  var localizations = AppLocalizations.of(context)!;
  if (isMifareClassic(tag.tag) &&
      chameleonTagSaveCheckForMifareClassicEV1(tag)) {
    // Native archival retains all EV1 positions and any existing metadata;
    // composite memory is not a common-v1 standalone profile.
    await FilePicker.saveFile(
      dialogTitle: '${localizations.output_file}:',
      fileName: '${tag.name}.${bin ? 'bin' : 'json'}',
      bytes: bin
          ? classicExportBytesForCard(tag)
          : const Utf8Encoder().convert(tag.toJson()),
    );
    return;
  }
  if (!bin && tag.sl1Profile != null) {
    await FilePicker.saveFile(
      dialogTitle: '${localizations.output_file}:',
      fileName: '${tag.name}.json',
      bytes: const Utf8Encoder().convert(exportSl1Card(tag)),
    );
    return;
  }
  if (bin) {
    Uint8List tagDump;
    if (isMifareClassic(tag.tag)) {
      tagDump = classicExportBytesForCard(tag);
    } else {
      List<int> dump = [];
      for (var block in tag.data) {
        dump.addAll(block);
      }
      tagDump = Uint8List.fromList(dump);
    }
    await FilePicker.saveFile(
      dialogTitle: '${localizations.output_file}:',
      fileName: '${tag.name}.bin',
      bytes: tagDump,
    );
  } else {
    var exportTag = tag;
    if (isMifareClassic(tag.tag)) {
      exportTag = CardSave(
          id: tag.id,
          uid: tag.uid,
          sak: tag.sak,
          atqa: tag.atqa,
          ats: tag.ats,
          name: tag.name,
          tag: tag.tag,
          data: chameleonTagSaveCheckForMifareClassicEV1(tag)
            ? List.generate(
                72,
                (i) => i < tag.data.length
                    ? Uint8List.fromList(tag.data[i])
                    : Uint8List(0),
              )
            : mfClassicGetExportBlocks(
              chameleonTagTypeGetMfClassicType(tag.tag), tag.data,
              ),
          extraData: tag.extraData,
          folderId: tag.folderId,
          color: tag.color);
    }
    await FilePicker.saveFile(
      dialogTitle: '${localizations.output_file}:',
      fileName: '${tag.name}.json',
      bytes: const Utf8Encoder().convert(exportTag.toJson()),
    );
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
      TagType.ultralight21,
      TagType.hf14a4
    ];
  } else if (frequency == TagFrequency.lf) {
    return [
      TagType.em410X,
      TagType.em410X16,
      TagType.em410X32,
      TagType.em410X64,
      TagType.em410XElectra,
      TagType.hidProx,
      TagType.viking,
      TagType.pac,
      TagType.ioProx,
      TagType.idteck
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
    case 1152: // EV1
      return TagType.mifare1K;
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

// Firmware format IDs are sparse: ACTPHID is 42, not the next list index.
const hidProxFormats = <int, String>{
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
  42: "HID ACTProx 36-bit",
};

String getNameForHIDProxType(int type) => hidProxFormats[type]!;

LFCard getLFCardFromUID(TagType type, String uid) {
  if (type == TagType.hidProx) {
    return HIDCard.fromUID(uid);
  }

  if (type == TagType.viking) {
    return VikingCard.fromUID(uid);
  }

  if (type == TagType.pac) {
    return PacCard.fromUID(uid);
  }

  if (type == TagType.ioProx) {
    return IoProxCard.fromUID(uid);
  }

  if (type == TagType.idteck) {
    return IdteckCard.fromUID(uid);
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
  } else if (type == TagType.pac) {
    return 8;
  } else if (type == TagType.ioProx) {
    return 16;
  } else if (type == TagType.idteck) {
    return 8;
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
        card = await appState.communicator!.scan14443aTagWithAts(selected: card);
        if (card == null) throw StateError('Card disappeared while reading ATS');
        if (!context.mounted) throw StateError('Card reading was cancelled');
        (type, mfcInfo) = await performMifareClassicScan(appState.communicator!,
            mfcInfo, context, updateMifareClassicRecovery,
          expectedIdentity: card,
        );
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
        (mfcInfo.isEV1 ? " EV1" : "") +
        (mfcInfo.sl1CardAuthDetected ? ' (SL1 CardAuth)' : '');
  } catch (e) {
    appState.log!.e(e.toString());
    hfInfo.cardExist = false;
  }

  return (hfInfo, mfcInfo, mfuInfo);
}
