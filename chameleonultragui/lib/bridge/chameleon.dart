import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:logger/logger.dart';

enum ChameleonCommand {
  // basic commands
  getAppVersion(1000),
  changeMode(1001),
  getDeviceMode(1002),
  getGitCommitHash(1017),
  getBatteryCharge(1025),

  // slot
  setSlotActivated(1003),
  setSlotTagType(1004),
  setSlotDataDefault(1005),
  setSlotEnable(1006),
  setSlotTagNick(1007),
  getSlotTagNick(1008),
  saveSlotNicks(1009),
  getActiveSlot(1018),
  getSlotInfo(1019),
  getEnabledSlots(1023),
  deleteSlotInfo(1024),

  // bootloader
  enterBootloader(1010),

  // device info
  getDeviceChipID(1011),
  getDeviceBLEAddress(1012),

  // settings
  saveSettings(1013),
  resetSettings(1014),

  // animation
  setAnimationMode(1015),
  getAnimationMode(1016),

  factoryReset(1020), // WARNING: ERASES ALL
  getDeviceType(1033),
  getDeviceSettings(1034),
  getDeviceCapabilities(1035),

  // button config
  getButtonPressConfig(1026),
  setButtonPressConfig(1027),
  getLongButtonPressConfig(1028),
  setLongButtonPressConfig(1029),

  // BLE
  bleSetConnectKey(1030),
  bleGetConnectKey(1031),
  bleClearBondedDevices(1032),
  bleGetPairEnable(1036),
  bleSetPairEnable(1037),

  // hf reader commands
  scan14ATag(2000),
  mf1SupportDetect(2001),
  mf1NTLevelDetect(2002),
  mf1DarksideDetect(2003),
  mf1DarksideAcquire(2004),
  mf1NTDistanceDetect(2005),
  mf1NestedAcquire(2006),
  mf1CheckKey(2007),
  mf1ReadBlock(2008),
  mf1WriteBlock(2009),

  // lf commands
  scanEM410Xtag(3000),
  writeEM410XtoT5577(3001),

  mf1LoadBlockData(4000),
  mf1SetAntiCollision(4001),

  // mfkey32
  mf1SetDetectionEnable(4004),
  mf1GetDetectionCount(4005),
  mf1GetDetectionResult(4006),
  mf1GetDetectionStatus(4007),

  // emulator settings
  mf1GetEmulatorConfig(4009),
  mf1GetGen1aMode(4010),
  mf1SetGen1aMode(4011),
  mf1GetGen2Mode(4012),
  mf1SetGen2Mode(4013),
  mf1GetFirstBlockColl(4014),
  mf1SetFirstBlockColl(4015),
  mf1GetWriteMode(4016),
  mf1SetWriteMode(4017),

  // read slot info
  mf1GetBlockData(4008),
  mf1GetAntiCollData(4018),

  // lf emulator
  setEM410XemulatorID(5000),
  getEM410XemulatorID(5001);

  const ChameleonCommand(this.value);
  final int value;
}

enum TagType {
  unknown(0),
  em410X(100),
  mifareMini(1000),
  mifare1K(1001),
  mifare2K(1002),
  mifare4K(1003),
  ntag213(1100),
  ntag215(1101),
  ntag216(1102);

  const TagType(this.value);
  final int value;
}

enum TagFrequency {
  unknown(0),
  lf(1),
  hf(2);

  const TagFrequency(this.value);
  final int value;
}

enum AnimationSetting {
  full(0),
  minimal(1),
  none(2);

  const AnimationSetting(this.value);
  final int value;
}

enum MifareClassicWriteMode {
  normal(0),
  denied(1),
  deceive(2),
  shadow(3);

  const MifareClassicWriteMode(this.value);
  final int value;
}

enum ButtonType {
  a(65), // ord('A')
  b(66); // ord('B')

  const ButtonType(this.value);
  final int value;
}

enum ButtonConfig {
  disable(0),
  cycleForward(1),
  cycleBackward(2),
  cloneUID(3);

  const ButtonConfig(this.value);
  final int value;
}

class CardData {
  Uint8List uid;
  int sak;
  Uint8List atqa;
  Uint8List ats;

  CardData(
      {required this.uid,
      required this.sak,
      required this.atqa,
      required this.ats});
}

class ChameleonMessage {
  int command;
  int status;
  Uint8List data;

  ChameleonMessage(
      {required this.command, required this.status, required this.data});
}

enum NTLevel { weak, static, hard, unknown }

enum DarksideResult {
  vulnerable,
  fixed,
  cantFixNT,
  luckAuthOK,
  notSendingNACK,
  tagChanged,
}

class NTDistance {
  int uid;
  int distance;

  NTDistance({required this.uid, required this.distance});
}

class NestedNonce {
  int nt;
  int ntEnc;
  int parity;

  NestedNonce({required this.nt, required this.ntEnc, required this.parity});
}

class NestedNonces {
  List<NestedNonce> nonces;

  NestedNonces({required this.nonces});
}

class Darkside {
  int uid;
  int nt1;
  int par;
  int ks1;
  int nr;
  int ar;

  Darkside(
      {required this.uid,
      required this.nt1,
      required this.par,
      required this.ks1,
      required this.nr,
      required this.ar});
}

class DetectionResult {
  int block;
  int type;
  bool isNested;
  int uid;
  int nt;
  int nr;
  int ar;

  DetectionResult(
      {required this.block,
      required this.type,
      required this.isNested,
      required this.uid,
      required this.nt,
      required this.nr,
      required this.ar});
}

// Some ChatGPT magic
// Nobody knows how it works

class ChameleonCommunicator {
  int baudrate = 115200;
  int dataFrameSof = 0x11;
  int dataMaxLength = 512;
  AbstractSerial? _serialInstance;
  List<int> dataBuffer = [];
  int dataPosition = 0;
  int dataCmd = 0;
  int dataStatus = 0;
  int dataLength = 0;
  List<ChameleonMessage> messageQueue = [];

  final Logger log;

  ChameleonCommunicator(this.log, {AbstractSerial? port}) {
    if (port != null) {
      open(port);
    }
  }

  open(AbstractSerial port) {
    _serialInstance = port;
  }

  int lrcCalc(List<int> array) {
    var ret = 0x00;
    for (var b in array) {
      ret += b;
      ret &= 0xFF;
    }
    return (0x100 - ret) & 0xFF;
  }

  Uint8List makeDataFrameBytes(
      ChameleonCommand cmd, int status, Uint8List? data) {
    List<int> frameList = [];
    frameList.add(dataFrameSof);
    frameList.add(lrcCalc(frameList.sublist(0, 1)));
    frameList.addAll(_fromInt16BE(cmd.value));
    frameList.addAll(_fromInt16BE(status));
    frameList.addAll(_fromInt16BE(data == null ? 0 : data.length));
    frameList.add(lrcCalc(frameList.sublist(2, 8)));

    if (data != null) {
      frameList.addAll(data);
    }

    frameList.add(lrcCalc(frameList));

    Uint8List frame = Uint8List.fromList(frameList);
    return frame;
  }

  Future<void> onSerialMessage(List<int> message) async {
    for (var byte in message) {
      dataBuffer.add(byte);

      if (dataPosition < 2) {
        // start of frame
        if (dataPosition == 0) {
          if (dataBuffer[dataPosition] != dataFrameSof) {
            throw ('Data frame no sof byte.');
          }
        } else {
          if (dataBuffer[dataPosition] != lrcCalc(dataBuffer.sublist(0, 1))) {
            throw ('Data frame sof lrc error.');
          }
        }
      } else if (dataPosition == 8) {
        // frame head lrc
        if (dataBuffer[dataPosition] != lrcCalc(dataBuffer.sublist(0, 8))) {
          throw ('Data frame head lrc error.');
        }
        // frame head complete, cache info
        dataCmd = _toInt16BE(Uint8List.fromList(dataBuffer.sublist(2, 4)));
        dataStatus = _toInt16BE(Uint8List.fromList(dataBuffer.sublist(4, 6)));
        dataLength = _toInt16BE(Uint8List.fromList(dataBuffer.sublist(6, 8)));
        if (dataLength > dataMaxLength) {
          throw ('Data frame data length too than of max.');
        }
      } else if (dataPosition == (8 + dataLength + 1)) {
        if (dataBuffer[dataPosition] ==
            lrcCalc(dataBuffer.sublist(0, dataBuffer.length - 1))) {
          var dataResponse = dataBuffer.sublist(9, 9 + dataLength);
          var message = ChameleonMessage(
              command: dataCmd,
              status: dataStatus,
              data: Uint8List.fromList(dataResponse));
          log.d(
              "Received message: command = ${message.command}, status = ${message.status}, data = ${bytesToHex(message.data)}");
          dataPosition = 0;
          dataBuffer = [];
          messageQueue.add(message);
          return;
        } else {
          throw ('Data frame finally lrc error.');
        }
      }

      dataPosition += 1;
    }
  }

  Future<ChameleonMessage?> sendCmd(ChameleonCommand cmd,
      {Uint8List? data,
      Duration timeout = const Duration(seconds: 5),
      bool skipReceive = false}) async {
    var startTime = DateTime.now();
    var dataFrame = makeDataFrameBytes(cmd, 0x00, data);

    if (!_serialInstance!.isOpen) {
      await _serialInstance!.open();
      await _serialInstance!.registerCallback(onSerialMessage);
      _serialInstance!.isOpen = true;
    }

    log.d("Sending: ${bytesToHex(dataFrame)}");

    if (skipReceive) {
      try {
        await _serialInstance!.write(Uint8List.fromList(dataFrame));
      } catch (_) {}
      return null;
    }

    await _serialInstance!.write(Uint8List.fromList(dataFrame));

    while (true) {
      for (var message in messageQueue) {
        if (message.command == cmd.value) {
          messageQueue.remove(message);
          return message;
        }
      }

      if (startTime.millisecondsSinceEpoch + timeout.inMilliseconds <
          DateTime.now().millisecondsSinceEpoch) {
        throw ("Timeout waiting for response for command ${cmd.value}");
      }

      await asyncSleep(1);
    }
  }

  Uint8List _fromInt16BE(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.big);
  }

  int _toInt16BE(Uint8List bytes) {
    return bytes.buffer.asByteData().getInt16(0, Endian.big);
  }

  int networkToInt(Uint8List bytes) {
    return (bytes[0] << 8) | bytes[1];
  }

  Uint8List intToNetwork(int value) {
    var bytes = Uint8List(2);
    bytes[0] = (value >> 8) & 0xFF;
    bytes[1] = value & 0xFF;
    return bytes;
  }

  Future<(bool, int)> getFirmwareVersion() async {
    var resp = await sendCmd(ChameleonCommand.getAppVersion);
    if (resp!.data.length != 2) throw ("Invalid data length");

    // Check for legacy protocol
    if (resp.data[0] == 0 && resp.data[1] == 1) {
      return (true, 256);
    } else {
      return (false, networkToInt(resp.data));
    }
  }

  Future<String> getDeviceChipID() async {
    var resp = await sendCmd(ChameleonCommand.getDeviceChipID);
    return bytesToHex(resp!.data);
  }

  Future<String> getDeviceBLEAddress() async {
    var resp = await sendCmd(ChameleonCommand.getDeviceBLEAddress);
    return bytesToHexSpace(resp!.data).replaceAll(" ", ":");
  }

  Future<bool> isReaderDeviceMode() async {
    var resp = await sendCmd(ChameleonCommand.getDeviceMode);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setReaderDeviceMode(bool readerMode) async {
    await sendCmd(ChameleonCommand.changeMode,
        data: Uint8List.fromList([readerMode ? 1 : 0]));
  }

  Future<CardData> scan14443aTag() async {
    var resp = await sendCmd(ChameleonCommand.scan14ATag);

    if (resp!.data.isNotEmpty) {
      int uidLength = resp.data[0];
      int atsLength = resp.data[uidLength + 4];
      return CardData(
        uid: resp.data.sublist(1, uidLength + 1),
        atqa: Uint8List.fromList(
            resp.data.sublist(uidLength + 1, uidLength + 3).reversed.toList()),
        sak: resp.data[uidLength + 3],
        ats: resp.data.sublist(uidLength + 5, uidLength + 5 + atsLength),
      );
    } else {
      throw ("Invalid data length");
    }
  }

  Future<bool> detectMf1Support() async {
    // Detects if it is a Mifare Classic tag
    // true - Mifare Classic
    // false - any other card
    return (await sendCmd(ChameleonCommand.mf1SupportDetect))!.status == 0;
  }

  Future<NTLevel> getMf1NTLevel() async {
    // Get level of nt (weak/static/hard) in Mifare Classic
    var resp = (await sendCmd(ChameleonCommand.mf1NTLevelDetect))!.data[0];
    if (resp == 0) {
      return NTLevel.weak;
    } else if (resp == 1) {
      return NTLevel.static;
    } else if (resp == 2) {
      return NTLevel.hard;
    } else {
      return NTLevel.unknown;
    }
  }

  Future<DarksideResult> checkMf1Darkside() async {
    // Check card vulnerability to Mifare Classic darkside attack
    var status = (await sendCmd(ChameleonCommand.mf1DarksideAcquire,
            data: Uint8List.fromList([0, 0, 1, 15]),
            timeout: const Duration(seconds: 30)))!
        .data[0];

    if (status == 0) {
      return DarksideResult.vulnerable;
    } else if (status == 1) {
      return DarksideResult.cantFixNT;
    } else if (status == 2) {
      return DarksideResult.luckAuthOK;
    } else if (status == 3) {
      return DarksideResult.notSendingNACK;
    } else if (status == 4) {
      return DarksideResult.tagChanged;
    } else {
      return DarksideResult.fixed;
    }
  }

  Future<NTDistance> getMf1NTDistance(
    int block,
    int keyType,
    Uint8List keyKnown,
  ) async {
    // Get PRNG distance
    // keyType 0x60 if A key, 0x61 B key
    var resp = await sendCmd(ChameleonCommand.mf1NTDistanceDetect,
        data: Uint8List.fromList([keyType, block, ...keyKnown]));

    if (resp!.data.length != 8) {
      throw ("Invalid data length");
    }

    return NTDistance(
        uid: bytesToU32(resp.data.sublist(0, 4)),
        distance: bytesToU32(resp.data.sublist(4, 8)));
  }

  Future<NestedNonces> getMf1NestedNonces(int block, int keyType,
      Uint8List keyKnown, int targetBlock, int targetKeyType) async {
    // Collect nonces for nested attack
    // keyType 0x60 if A key, 0x61 B key
    int i = 0;
    var resp = await sendCmd(ChameleonCommand.mf1NestedAcquire,
        data: Uint8List.fromList(
            [keyType, block, ...keyKnown, targetKeyType, targetBlock]),
        timeout: const Duration(seconds: 30));
    var nonces = NestedNonces(nonces: []);

    while (i < resp!.data.length) {
      nonces.nonces.add(NestedNonce(
          nt: bytesToU32(resp.data.sublist(i, i + 4)),
          ntEnc: bytesToU32(resp.data.sublist(i + 4, i + 8)),
          parity: resp.data[i + 8]));

      i += 9;
    }

    return nonces;
  }

  Future<Darkside> getMf1Darkside(int targetBlock, int targetKeyType,
      bool firstRecover, int syncMax) async {
    // Collect parameters for darkside attack
    // keyType 0x60 if A key, 0x61 B key
    var resp = await sendCmd(ChameleonCommand.mf1DarksideAcquire,
        data: Uint8List.fromList(
            [targetKeyType, targetBlock, firstRecover ? 1 : 0, syncMax]),
        timeout: const Duration(seconds: 30));

    if (resp!.data[0] != 0) {
      throw ("Not vulnerable to Darkside");
    }

    resp.data = resp.data.sublist(1);

    if (resp.data.length != 32) {
      throw ("Invalid data length");
    }

    return Darkside(
        uid: bytesToU32(resp.data.sublist(0, 4)),
        nt1: bytesToU32(resp.data.sublist(4, 8)),
        par: bytesToU64(resp.data.sublist(8, 16)),
        ks1: bytesToU64(resp.data.sublist(16, 24)),
        nr: bytesToU32(resp.data.sublist(24, 28)),
        ar: bytesToU32(resp.data.sublist(28, 32)));
  }

  Future<bool> mf1Auth(int block, int keyType, Uint8List key) async {
    // Check if key is valid for block
    // keyType 0x60 if A key, 0x61 B key
    return (await sendCmd(ChameleonCommand.mf1CheckKey,
                data: Uint8List.fromList([keyType, block, ...key])))!
            .status ==
        0;
  }

  Future<Uint8List> mf1ReadBlock(int block, int keyType, Uint8List key) async {
    // Read block
    // keyType 0x60 if A key, 0x61 B key
    return (await sendCmd(ChameleonCommand.mf1ReadBlock,
            data: Uint8List.fromList([keyType, block, ...key])))!
        .data;
  }

  Future<void> mf1WriteBlock(
      int block, int keyType, Uint8List key, Uint8List data) async {
    // Write block
    // keyType 0x60 if A key, 0x61 B key
    await sendCmd(ChameleonCommand.mf1WriteBlock,
        data: Uint8List.fromList([keyType, block, ...key, ...data]));
  }

  Future<void> activateSlot(int slot) async {
    // Slot 0-7
    await sendCmd(ChameleonCommand.setSlotActivated,
        data: Uint8List.fromList([slot]));
  }

  Future<void> setSlotType(int slot, TagType type) async {
    await sendCmd(ChameleonCommand.setSlotTagType,
        data: Uint8List.fromList([slot, ...intToNetwork(type.value)]));
  }

  Future<void> setDefaultDataToSlot(int slot, TagType type) async {
    await sendCmd(ChameleonCommand.setSlotDataDefault,
        data: Uint8List.fromList([slot, ...intToNetwork(type.value)]));
  }

  Future<void> enableSlot(int slot, TagFrequency frequency, bool status) async {
    await sendCmd(ChameleonCommand.setSlotEnable,
        data: Uint8List.fromList([slot, frequency.value, status ? 1 : 0]));
  }

  Future<bool> isMf1DetectionMode() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetDetectionStatus);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setMf1DetectionStatus(bool status) async {
    await sendCmd(ChameleonCommand.mf1SetDetectionEnable,
        data: Uint8List.fromList([status ? 1 : 0]));
  }

  Future<int> getMf1DetectionCount() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetDetectionCount);
    return resp!.data.buffer.asByteData().getInt32(0, Endian.big);
  }

  Future<Map<int, Map<int, Map<String, List<DetectionResult>>>>>
      getMf1DetectionResult(int count) async {
    List<DetectionResult> resultList = [];
    while (resultList.length < count) {
      // Get results from index
      var resp = (await sendCmd(ChameleonCommand.mf1GetDetectionResult,
              data: Uint8List(4)
                ..buffer
                    .asByteData()
                    .setInt32(0, resultList.length, Endian.big)))!
          .data;

      int pos = 0;
      while (pos < resp.length) {
        resultList.add(DetectionResult(
            block: resp[0 + pos],
            type: 0x60 + (resp[1 + pos] & 0x01),
            isNested: (resp[1 + pos] >> 1 & 0x01) == 0x01,
            uid: bytesToU32(resp.sublist(2 + pos, 6 + pos)),
            nt: bytesToU32(resp.sublist(6 + pos, 10 + pos)),
            nr: bytesToU32(resp.sublist(10 + pos, 14 + pos)),
            ar: bytesToU32(resp.sublist(14 + pos, 18 + pos))));
        pos += 18;
      }
    }

    // Classify
    Map<int, Map<int, Map<String, List<DetectionResult>>>> resultMap = {};
    for (DetectionResult item in resultList) {
      if (!resultMap.containsKey(item.uid)) {
        resultMap[item.uid] = {};
      }

      int block = item.block;
      if (!resultMap[item.uid]!.containsKey(block)) {
        resultMap[item.uid]![block] = {};
      }

      String typeChr = item.type == 0x60 ? 'A' : 'B';
      if (!resultMap[item.uid]![block]!.containsKey(typeChr)) {
        resultMap[item.uid]![block]![typeChr] = [];
      }

      resultMap[item.uid]![block]![typeChr]!.add(item);
    }

    return resultMap;
  }

  Future<void> setMf1BlockData(int startBlock, Uint8List blocks) async {
    // Set block data in emulator
    // Can contain multiple block data, automatically incremented from startBlock
    await sendCmd(ChameleonCommand.mf1LoadBlockData,
        data: Uint8List.fromList([startBlock & 0xFF, ...blocks]));
  }

  Future<void> setMf1AntiCollision(CardData card) async {
    await sendCmd(ChameleonCommand.mf1SetAntiCollision,
        data: Uint8List.fromList([
          card.uid.length,
          ...card.uid,
          ...card.atqa.reversed,
          card.sak,
          card.ats.length,
          ...card.ats
        ]));
  }

  Future<String> readEM410X() async {
    var resp = await sendCmd(ChameleonCommand.scanEM410Xtag);
    return bytesToHexSpace(resp!.data);
  }

  Future<void> setEM410XEmulatorID(Uint8List uid) async {
    await sendCmd(ChameleonCommand.setEM410XemulatorID, data: uid);
  }

  Future<void> writeEM410XtoT55XX(
      Uint8List uid, Uint8List key, List<Uint8List> oldKeys) async {
    List<int> keys = [];
    for (var oldKey in oldKeys) {
      keys.addAll(oldKey);
    }
    await sendCmd(ChameleonCommand.writeEM410XtoT5577,
        data: Uint8List.fromList([...key, ...keys]));
  }

  Future<void> setSlotTagName(
      int index, String name, TagFrequency frequency) async {
    await sendCmd(ChameleonCommand.setSlotTagNick,
        data:
            Uint8List.fromList([index, frequency.value, ...utf8.encode(name)]));
  }

  Future<String> getSlotTagName(int index, TagFrequency frequency) async {
    var resp = await sendCmd(ChameleonCommand.getSlotTagNick,
        data: Uint8List.fromList([index, frequency.value]));
    return utf8.decode(resp!.data, allowMalformed: true);
  }

  Future<void> deleteSlotInfo(int index, TagFrequency frequency) async {
    await sendCmd(ChameleonCommand.deleteSlotInfo,
        data: Uint8List.fromList([index, frequency.value]));
  }

  Future<void> saveSlotData() async {
    await sendCmd(ChameleonCommand.saveSlotNicks);
  }

  Future<void> enterDFUMode() async {
    await sendCmd(ChameleonCommand.enterBootloader, skipReceive: true);
  }

  Future<void> factoryReset() async {
    await sendCmd(ChameleonCommand.factoryReset, skipReceive: true);
  }

  Future<void> saveSettings() async {
    await sendCmd(ChameleonCommand.saveSettings);
  }

  Future<void> resetSettings() async {
    await sendCmd(ChameleonCommand.resetSettings);
  }

  Future<void> setAnimationMode(AnimationSetting animation) async {
    await sendCmd(ChameleonCommand.setAnimationMode,
        data: Uint8List.fromList([animation.value]));
  }

  Future<AnimationSetting> getAnimationMode() async {
    var resp = await sendCmd(ChameleonCommand.getAnimationMode);
    return getAnimationModeType(resp!.data[0]);
  }

  Future<String> getGitCommitHash() async {
    var resp = await sendCmd(ChameleonCommand.getGitCommitHash);
    return const AsciiDecoder().convert(resp!.data);
  }

  Future<int> getActiveSlot() async {
    // get the selected slot on the device, 0-7 (8 slots)
    return (await sendCmd(ChameleonCommand.getActiveSlot))!.data[0];
  }

  Future<List<(TagType, TagType)>> getUsedSlots() async {
    List<(TagType, TagType)> tags = [];
    var resp = await sendCmd(ChameleonCommand.getSlotInfo);
    var index = 0;
    for (var slot = 0; slot < 8; slot++) {
      tags.add((
        numberToChameleonTag(
            networkToInt(resp!.data.sublist(index, index + 2))),
        numberToChameleonTag(
            networkToInt(resp.data.sublist(index + 2, index + 4))),
      ));

      index += 4;
    }
    return tags;
  }

  Future<(bool, bool, bool, bool, MifareClassicWriteMode)>
      getMf1EmulatorConfig() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetEmulatorConfig);
    if (resp!.data.length != 5) throw ("Invalid data length");
    MifareClassicWriteMode mode = MifareClassicWriteMode.normal;
    if (resp.data[4] == 1) {
      mode = MifareClassicWriteMode.denied;
    } else if (resp.data[4] == 2) {
      mode = MifareClassicWriteMode.deceive;
    } else if (resp.data[4] == 3 || resp.data[4] == 4) {
      mode = MifareClassicWriteMode.shadow;
    }
    return (
      resp.data[0] == 1, // is detection enabled
      resp.data[1] == 1, // is gen1a mode enabled
      resp.data[2] == 1, // is gen2 mode enabled
      resp.data[3] == 1, // use anti collision data from block 0 mode enabled
      mode // write mode
    );
  }

  Future<bool> isMf1Gen1aMode() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetGen1aMode);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setMf1Gen1aMode(bool gen1aMode) async {
    await sendCmd(ChameleonCommand.mf1SetGen1aMode,
        data: Uint8List.fromList([gen1aMode ? 1 : 0]));
  }

  Future<bool> isMf1Gen2Mode() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetGen2Mode);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setMf1Gen2Mode(bool gen2Mode) async {
    await sendCmd(ChameleonCommand.mf1SetGen2Mode,
        data: Uint8List.fromList([gen2Mode ? 1 : 0]));
  }

  Future<bool> isMf1UseFirstBlockColl() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetFirstBlockColl);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setMf1UseFirstBlockColl(bool useColl) async {
    await sendCmd(ChameleonCommand.mf1SetFirstBlockColl,
        data: Uint8List.fromList([useColl ? 1 : 0]));
  }

  Future<MifareClassicWriteMode> getMf1WriteMode() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetWriteMode);
    if (resp!.data.length != 1) throw ("Invalid data length");
    if (resp.data[0] == 1) {
      return MifareClassicWriteMode.denied;
    } else if (resp.data[0] == 2) {
      return MifareClassicWriteMode.deceive;
    } else if (resp.data[0] == 3) {
      return MifareClassicWriteMode.shadow;
    } else {
      return MifareClassicWriteMode.normal;
    }
  }

  Future<void> setMf1WriteMode(MifareClassicWriteMode mode) async {
    await sendCmd(ChameleonCommand.mf1SetWriteMode,
        data: Uint8List.fromList([mode.value]));
  }

  Future<List<(bool, bool)>> getEnabledSlots() async {
    var resp = await sendCmd(ChameleonCommand.getEnabledSlots);
    if (resp!.data.length != 16) throw ("Invalid data length");
    List<(bool, bool)> slots = [];
    for (var slot = 0; slot < 8; slot++) {
      slots.add((resp.data[slot * 2] != 0, resp.data[slot * 2 + 1] != 0));
    }
    return slots;
  }

  Future<(int, int)> getBatteryCharge() async {
    var resp = await sendCmd(ChameleonCommand.getBatteryCharge);
    if (resp!.data.length != 3) throw ("Invalid data length");
    return (_toInt16BE(resp.data.sublist(0, 2)), resp.data[2]);
  }

  Future<ButtonConfig> getButtonConfig(ButtonType type) async {
    var resp = await sendCmd(ChameleonCommand.getButtonPressConfig,
        data: Uint8List.fromList([type.value]));
    if (resp!.data[0] == 1) {
      return ButtonConfig.cycleForward;
    } else if (resp.data[0] == 2) {
      return ButtonConfig.cycleBackward;
    } else if (resp.data[0] == 3) {
      return ButtonConfig.cloneUID;
    } else {
      return ButtonConfig.disable;
    }
  }

  Future<void> setButtonConfig(ButtonType type, ButtonConfig mode) async {
    await sendCmd(ChameleonCommand.setButtonPressConfig,
        data: Uint8List.fromList([type.value, mode.value]));
  }

  Future<ButtonConfig> getLongButtonConfig(ButtonType type) async {
    var resp = await sendCmd(ChameleonCommand.getLongButtonPressConfig,
        data: Uint8List.fromList([type.value]));
    if (resp!.data[0] == 1) {
      return ButtonConfig.cycleForward;
    } else if (resp.data[0] == 2) {
      return ButtonConfig.cycleBackward;
    } else if (resp.data[0] == 3) {
      return ButtonConfig.cloneUID;
    } else {
      return ButtonConfig.disable;
    }
  }

  Future<void> setLongButtonConfig(ButtonType type, ButtonConfig mode) async {
    await sendCmd(ChameleonCommand.setLongButtonPressConfig,
        data: Uint8List.fromList([type.value, mode.value]));
  }

  Future<void> clearBLEBoundedDevices() async {
    await sendCmd(ChameleonCommand.bleClearBondedDevices, skipReceive: true);
  }

  Future<String> getBLEConnectionKey() async {
    var resp = await sendCmd(ChameleonCommand.bleGetConnectKey);
    return utf8.decode(resp!.data, allowMalformed: true);
  }

  Future<void> setBLEConnectKey(String key) async {
    await sendCmd(ChameleonCommand.bleSetConnectKey,
        data: Uint8List.fromList(utf8.encode(key)));
  }

  Future<bool> isBLEPairEnabled() async {
    var resp = await sendCmd(ChameleonCommand.bleGetPairEnable);
    return resp!.data[0] == 1;
  }

  Future<void> setBLEPairEnabled(bool status) async {
    await sendCmd(ChameleonCommand.bleSetPairEnable,
        data: Uint8List.fromList([status ? 1 : 0]));
  }

  Future<ChameleonDevice> getDeviceType() async {
    return (await sendCmd(ChameleonCommand.getDeviceType))!.data[0] == 1
        ? ChameleonDevice.ultra
        : ChameleonDevice.lite;
  }

  Future<Uint8List> mf1GetEmulatorBlock(int startBlock, int blockCount) async {
    return (await sendCmd(ChameleonCommand.mf1GetBlockData,
            data: Uint8List.fromList([startBlock, blockCount])))!
        .data;
  }

  Future<CardData> mf1GetAntiCollData() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetAntiCollData);

    if (resp!.data.isNotEmpty) {
      int uidLength = resp.data[0];
      int atsLength = resp.data[uidLength + 4];
      return CardData(
        uid: resp.data.sublist(1, uidLength + 1),
        atqa: Uint8List.fromList(
            resp.data.sublist(uidLength + 1, uidLength + 3).reversed.toList()),
        sak: resp.data[uidLength + 3],
        ats: resp.data.sublist(uidLength + 5, uidLength + 5 + atsLength),
      );
    } else {
      throw ("Invalid data length");
    }
  }

  Future<Uint8List> getEM410XEmulatorID() async {
    return (await sendCmd(ChameleonCommand.getEM410XemulatorID))!.data;
  }

  Future<
      (
        AnimationSetting,
        ButtonConfig,
        ButtonConfig,
        ButtonConfig,
        ButtonConfig,
        bool,
        String
      )> getDeviceSettings() async {
    var resp = (await sendCmd(ChameleonCommand.getDeviceSettings))!.data;
    if (resp[0] != 5) {
      throw ("Invalid settings version");
    }

    AnimationSetting animationMode = getAnimationModeType(resp[1]);
    ButtonConfig aPress = getButtonConfigType(resp[2]),
        bPress = getButtonConfigType(resp[3]),
        aLongPress = getButtonConfigType(resp[4]),
        bLongPress = getButtonConfigType(resp[5]);

    return (
      animationMode,
      aPress,
      bPress,
      aLongPress,
      bLongPress,
      resp[6] == 1,
      utf8.decode(resp.sublist(7, 13), allowMalformed: true)
    );
  }

  Future<List<int>> getDeviceCapabilities() async {
    var resp = (await sendCmd(ChameleonCommand.getDeviceCapabilities))!.data;
    List<int> commands = [];

    for (int i = 0; i < resp.length; i += 2) {
      commands.add(networkToInt(resp.sublist(i, i + 2)));
    }

    return commands;
  }
}
