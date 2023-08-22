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

  // lf emulator
  setEM410XemulatorID(5000);

  const ChameleonCommand(this.value);
  final int value;
}

enum ChameleonTag {
  unknown(0),
  em410X(1),
  mifareMini(2),
  mifare1K(3),
  mifare2K(4),
  mifare4K(5),
  ntag213(6),
  ntag215(7),
  ntag216(8);

  const ChameleonTag(this.value);
  final int value;
}

enum ChameleonTagFrequiency {
  unknown(0),
  lf(1),
  hf(2);

  const ChameleonTagFrequiency(this.value);
  final int value;
}

enum ChameleonAnimation {
  full(0),
  minimal(1),
  none(2);

  const ChameleonAnimation(this.value);
  final int value;
}

enum ChameleonMf1WriteMode {
  normal(0),
  deined(1),
  deceive(2),
  shadow(3);

  const ChameleonMf1WriteMode(this.value);
  final int value;
}

class ChameleonCard {
  Uint8List uid;
  int sak;
  Uint8List atqa;

  ChameleonCard({required this.uid, required this.sak, required this.atqa});
}

class ChameleonMessage {
  int status;
  Uint8List data;

  ChameleonMessage({required this.status, required this.data});
}

enum ChameleonNTLevel { weak, static, hard, unknown }

enum ChameleonDarksideResult {
  vurnerable,
  fixed,
  cantFixNT,
  luckAuthOK,
  notSendingNACK,
  tagChanged,
}

class ChameleonNTDistance {
  int uid;
  int distance;

  ChameleonNTDistance({required this.uid, required this.distance});
}

class ChameleonNestedNonce {
  int nt;
  int ntEnc;
  int parity;

  ChameleonNestedNonce(
      {required this.nt, required this.ntEnc, required this.parity});
}

class ChameleonNestedNonces {
  List<ChameleonNestedNonce> nonces;

  ChameleonNestedNonces({required this.nonces});
}

class ChameleonDarkside {
  int uid;
  int nt1;
  int par;
  int ks1;
  int nr;
  int ar;

  ChameleonDarkside(
      {required this.uid,
      required this.nt1,
      required this.par,
      required this.ks1,
      required this.nr,
      required this.ar});
}

class ChameleonDetectionResult {
  int block;
  int type;
  bool isNested;
  int uid;
  int nt;
  int nr;
  int ar;

  ChameleonDetectionResult(
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

class ChameleonCom {
  int baudrate = 115200;
  int dataFrameSof = 0x11;
  int dataMaxLength = 512;
  AbstractSerial? _serialInstance;
  Logger log = Logger();

  ChameleonCom({AbstractSerial? port}) {
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

  Future<ChameleonMessage?> sendCmdSync(ChameleonCommand cmd, int status,
      {Uint8List? data,
      Duration timeout = const Duration(seconds: 5),
      bool skipReceive = false}) async {
    var dataFrame = makeDataFrameBytes(cmd, status, data);
    List<int> dataBuffer = [];
    var dataPosition = 0;
    var dataStatus = 0x0000;
    var dataLength = 0x0000;
    var startTime = DateTime.now();
    List<int> readBuffer = [];

    log.d("Sending: ${bytesToHex(dataFrame)}");
    await _serialInstance!.finishRead();
    await _serialInstance!.open();
    if (skipReceive) {
      try {
        await _serialInstance!.write(Uint8List.fromList(dataFrame));
      } catch (_) {}
      return null;
    }
    await _serialInstance!.write(Uint8List.fromList(dataFrame));

    while (true) {
      while (true) {
        readBuffer.addAll(await _serialInstance!.read(16384));
        if (readBuffer.isNotEmpty) {
          log.d("Received: ${bytesToHex(Uint8List.fromList(readBuffer))}");
          break;
        }
        if (startTime.millisecondsSinceEpoch + timeout.inMilliseconds <
            DateTime.now().millisecondsSinceEpoch) {
          throw ("Timeout waiting for response");
        }
      }

      if (readBuffer.isEmpty) {
        await asyncSleep(10);
        continue;
      }

      while (readBuffer.length > dataPosition) {
        Uint8List dataBytes = Uint8List.fromList([readBuffer[dataPosition]]);

        if (dataBytes.isNotEmpty) {
          var dataByte = dataBytes[0];
          dataBuffer.add(dataByte);
          if (dataPosition < 2) {
            // start of frame
            if (dataPosition == 0) {
              if (dataBuffer[dataPosition] != dataFrameSof) {
                throw ('Data frame no sof byte.');
              }
            }
            if (dataPosition == 1) {
              if (dataBuffer[dataPosition] !=
                  lrcCalc(dataBuffer.sublist(0, 1))) {
                throw ('Data frame sof lrc error.');
              }
            }
          } else if (dataPosition == 8) {
            // frame head lrc
            if (dataBuffer[dataPosition] != lrcCalc(dataBuffer.sublist(0, 8))) {
              throw ('Data frame head lrc error.');
            }
            // frame head complete, cache info
            //dataCmd = _toInt16BE(Uint8List.fromList(dataBuffer.sublist(2, 4)));
            dataStatus =
                _toInt16BE(Uint8List.fromList(dataBuffer.sublist(4, 6)));
            dataLength =
                _toInt16BE(Uint8List.fromList(dataBuffer.sublist(6, 8)));
            if (dataLength > dataMaxLength) {
              throw ('Data frame data length too than of max.');
            }
          } else if (dataPosition == (8 + dataLength + 1)) {
            if (dataBuffer[dataPosition] ==
                lrcCalc(dataBuffer.sublist(0, dataBuffer.length - 1))) {
              var dataResponse = dataBuffer.sublist(9, 9 + dataLength);
              await _serialInstance!.finishRead();
              return ChameleonMessage(
                  status: dataStatus, data: Uint8List.fromList(dataResponse));
            } else {
              throw ('Data frame finally lrc error.');
            }
          }

          dataPosition += 1;
        } else {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
    }
  }

  Uint8List _fromInt16BE(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.big);
  }

  int _toInt16BE(Uint8List bytes) {
    return bytes.buffer.asByteData().getInt16(0, Endian.big);
  }

  Future<int> getFirmwareVersion() async {
    var resp = await sendCmdSync(ChameleonCommand.getAppVersion, 0x00);
    if (resp!.data.length != 2) throw ("Invalid data length");
    return (resp.data[1] << 8) | resp.data[0];
  }

  Future<String> getDeviceChipID() async {
    var resp = await sendCmdSync(ChameleonCommand.getDeviceChipID, 0x00);
    return bytesToHex(resp!.data);
  }

  Future<String> getDeviceBLEAddress() async {
    var resp = await sendCmdSync(ChameleonCommand.getDeviceBLEAddress, 0x00);
    return bytesToHexSpace(Uint8List.fromList(resp!.data.reversed.toList()))
        .replaceAll(" ", ":");
  }

  Future<bool> isReaderDeviceMode() async {
    var resp = await sendCmdSync(ChameleonCommand.getDeviceMode, 0x00);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setReaderDeviceMode(bool readerMode) async {
    await sendCmdSync(ChameleonCommand.changeMode, 0x00,
        data: Uint8List.fromList([readerMode ? 1 : 0]));
  }

  Future<ChameleonCard> scan14443aTag() async {
    var resp = await sendCmdSync(ChameleonCommand.scan14ATag, 0x00);

    if (resp!.data.isNotEmpty) {
      return ChameleonCard(
          uid: resp.data.sublist(0, resp.data[10]),
          sak: resp.data[12],
          atqa:
              Uint8List.fromList(resp.data.sublist(13, 15).reversed.toList()));
    } else {
      throw ("Invalid data length");
    }
  }

  Future<bool> detectMf1Support() async {
    // Detects if it is a Mifare Classic tag
    // true - Mifare Classic
    // flase - any other card
    return (await sendCmdSync(ChameleonCommand.mf1SupportDetect, 0x00))!
            .status ==
        0;
  }

  Future<ChameleonNTLevel> getMf1NTLevel() async {
    // Get level of nt (weak/static/hard) in Mifare Classic
    var resp =
        (await sendCmdSync(ChameleonCommand.mf1NTLevelDetect, 0x00))!.status;
    if (resp == 0x00) {
      return ChameleonNTLevel.weak;
    } else if (resp == 0x24) {
      return ChameleonNTLevel.static;
    } else if (resp == 0x25) {
      return ChameleonNTLevel.hard;
    } else {
      return ChameleonNTLevel.unknown;
    }
  }

  Future<ChameleonDarksideResult> checkMf1Darkside() async {
    // Check card vulnerability to Mifare Classic darkside attack
    int status = (await sendCmdSync(ChameleonCommand.mf1DarksideDetect, 0x00,
            timeout: const Duration(seconds: 20)))!
        .status;
    if (status == 0) {
      return ChameleonDarksideResult.vurnerable;
    } else if (status == 0x20) {
      return ChameleonDarksideResult.cantFixNT;
    } else if (status == 0x21) {
      return ChameleonDarksideResult.luckAuthOK;
    } else if (status == 0x22) {
      return ChameleonDarksideResult.notSendingNACK;
    } else if (status == 0x23) {
      return ChameleonDarksideResult.tagChanged;
    } else {
      return ChameleonDarksideResult.fixed;
    }
  }

  Future<ChameleonNTDistance> getMf1NTDistance(
    int block,
    int keyType,
    Uint8List keyKnown,
  ) async {
    // Get PRNG distance
    // keyType 0x60 if A key, 0x61 B key
    var resp = await sendCmdSync(ChameleonCommand.mf1NTDistanceDetect, 0x00,
        data: Uint8List.fromList([keyType, block, ...keyKnown]));

    if (resp!.data.length != 8) {
      throw ("Invalid data length");
    }

    return ChameleonNTDistance(
        uid: bytesToU32(resp.data.sublist(0, 4)),
        distance: bytesToU32(resp.data.sublist(4, 8)));
  }

  Future<ChameleonNestedNonces> getMf1NestedNonces(int block, int keyType,
      Uint8List keyKnown, int targetBlock, int targetKeyType) async {
    // Collect nonces for nested attack
    // keyType 0x60 if A key, 0x61 B key
    int i = 0;
    var resp = await sendCmdSync(ChameleonCommand.mf1NestedAcquire, 0x00,
        data: Uint8List.fromList(
            [keyType, block, ...keyKnown, targetKeyType, targetBlock]),
        timeout: const Duration(seconds: 30));
    var nonces = ChameleonNestedNonces(nonces: []);

    while (i < resp!.data.length) {
      nonces.nonces.add(ChameleonNestedNonce(
          nt: bytesToU32(resp.data.sublist(i, i + 4)),
          ntEnc: bytesToU32(resp.data.sublist(i + 4, i + 8)),
          parity: resp.data[i + 8]));

      i += 9;
    }

    return nonces;
  }

  Future<ChameleonDarkside> getMf1Darkside(int targetBlock, int targetKeyType,
      bool firstRecover, int syncMax) async {
    // Collect parameters for darkside attack
    // keyType 0x60 if A key, 0x61 B key
    var resp = await sendCmdSync(ChameleonCommand.mf1DarksideAcquire, 0x00,
        data: Uint8List.fromList(
            [targetKeyType, targetBlock, firstRecover ? 1 : 0, syncMax]),
        timeout: const Duration(seconds: 30));

    if (resp!.data.length != 32) {
      throw ("Invalid data length");
    }

    return ChameleonDarkside(
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
    return (await sendCmdSync(ChameleonCommand.mf1CheckKey, 0x00,
                data: Uint8List.fromList([keyType, block, ...key])))!
            .status ==
        0;
  }

  Future<Uint8List> mf1ReadBlock(int block, int keyType, Uint8List key) async {
    // Read block
    // keyType 0x60 if A key, 0x61 B key
    return (await sendCmdSync(ChameleonCommand.mf1ReadBlock, 0x00,
            data: Uint8List.fromList([keyType, block, ...key])))!
        .data;
  }

  Future<void> mf1WriteBlock(
      int block, int keyType, Uint8List key, Uint8List data) async {
    // Write block
    // keyType 0x60 if A key, 0x61 B key
    await sendCmdSync(ChameleonCommand.mf1WriteBlock, 0x00,
        data: Uint8List.fromList([keyType, block, ...key, ...data]));
  }

  Future<void> activateSlot(int slot) async {
    // Slot 0-7
    await sendCmdSync(ChameleonCommand.setSlotActivated, 0x00,
        data: Uint8List.fromList([slot]));
  }

  Future<void> setSlotType(int slot, ChameleonTag type) async {
    await sendCmdSync(ChameleonCommand.setSlotTagType, 0x00,
        data: Uint8List.fromList([slot, type.value]));
  }

  Future<void> setDefaultDataToSlot(int slot, ChameleonTag type) async {
    await sendCmdSync(ChameleonCommand.setSlotDataDefault, 0x00,
        data: Uint8List.fromList([slot, type.value]));
  }

  Future<void> enableSlot(int slot, bool status) async {
    await sendCmdSync(ChameleonCommand.setSlotEnable, 0x00,
        data: Uint8List.fromList([slot, status ? 1 : 0]));
  }

  Future<bool> isMf1DetectionMode() async {
    var resp = await sendCmdSync(ChameleonCommand.mf1GetDetectionStatus, 0x00);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setMf1DetectionStatus(bool status) async {
    await sendCmdSync(ChameleonCommand.mf1SetDetectionEnable, 0x00,
        data: Uint8List.fromList([status ? 1 : 0]));
  }

  Future<int> getMf1DetectionCount() async {
    var resp = await sendCmdSync(ChameleonCommand.mf1GetDetectionCount, 0x00);
    return resp!.data.buffer.asByteData().getInt16(0, Endian.little);
  }

  Future<Map<int, Map<int, Map<String, List<ChameleonDetectionResult>>>>>
      getMf1DetectionResult(int index) async {
    // Get results from index
    var resp = (await sendCmdSync(ChameleonCommand.mf1GetDetectionResult, 0x00,
            data: Uint8List(4)
              ..buffer.asByteData().setInt16(0, index, Endian.big)))!
        .data;
    List<ChameleonDetectionResult> resultList = [];
    int pos = 0;
    while (pos < resp.length) {
      resultList.add(ChameleonDetectionResult(
          block: resp[0 + pos],
          type: 0x60 + (resp[1 + pos] & 0x01),
          isNested: (resp[1 + pos] >> 1 & 0x01) == 0x01,
          uid: bytesToU32(resp.sublist(2 + pos, 6 + pos)),
          nt: bytesToU32(resp.sublist(6 + pos, 10 + pos)),
          nr: bytesToU32(resp.sublist(10 + pos, 14 + pos)),
          ar: bytesToU32(resp.sublist(14 + pos, 18 + pos))));
      pos += 18;
    }

    // Classify
    Map<int, Map<int, Map<String, List<ChameleonDetectionResult>>>> resultMap =
        {};
    for (ChameleonDetectionResult item in resultList) {
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
    await sendCmdSync(ChameleonCommand.mf1LoadBlockData, 0x00,
        data: Uint8List.fromList([startBlock & 0xFF, ...blocks]));
  }

  Future<void> setMf1AntiCollision(ChameleonCard card) async {
    await sendCmdSync(ChameleonCommand.mf1SetAntiCollision, 0x00,
        data:
            Uint8List.fromList([card.sak, ...card.atqa.reversed, ...card.uid]));
  }

  Future<String> readEM410X() async {
    var resp = await sendCmdSync(ChameleonCommand.scanEM410Xtag, 0x00);
    return bytesToHexSpace(resp!.data);
  }

  Future<void> setEM410XEmulatorID(Uint8List uid) async {
    await sendCmdSync(ChameleonCommand.setEM410XemulatorID, 0x00, data: uid);
  }

  Future<void> writeEM410XtoT55XX(
      Uint8List uid, Uint8List key, List<Uint8List> oldKeys) async {
    List<int> keys = [];
    for (var oldKey in oldKeys) {
      keys.addAll(oldKey);
    }
    await sendCmdSync(ChameleonCommand.writeEM410XtoT5577, 0x00,
        data: Uint8List.fromList([...key, ...keys]));
  }

  Future<void> setSlotTagName(
      int index, String name, ChameleonTagFrequiency frequiency) async {
    await sendCmdSync(ChameleonCommand.setSlotTagNick, 0x00,
        data: Uint8List.fromList(
            [index, frequiency.value, ...utf8.encode(name)]));
  }

  Future<String> getSlotTagName(
      int index, ChameleonTagFrequiency frequiency) async {
    var resp = await sendCmdSync(ChameleonCommand.getSlotTagNick, 0x00,
        data: Uint8List.fromList([index, frequiency.value]));
    return utf8.decode(resp!.data);
  }

  Future<void> deleteSlotInfo(
      int index, ChameleonTagFrequiency frequiency) async {
    await sendCmdSync(ChameleonCommand.deleteSlotInfo, 0x00,
        data: Uint8List.fromList([index, frequiency.value]));
  }

  Future<void> saveSlotData() async {
    await sendCmdSync(ChameleonCommand.saveSlotNicks, 0x00);
  }

  Future<void> enterDFUMode() async {
    await sendCmdSync(ChameleonCommand.enterBootloader, 0x00,
        skipReceive: true);
  }

  Future<void> factoryReset() async {
    await sendCmdSync(ChameleonCommand.factoryReset, 0x00, skipReceive: true);
  }

  Future<void> saveSettings() async {
    await sendCmdSync(ChameleonCommand.saveSettings, 0x00);
  }

  Future<void> resetSettings() async {
    await sendCmdSync(ChameleonCommand.resetSettings, 0x00);
  }

  Future<void> setAnimationMode(ChameleonAnimation animation) async {
    await sendCmdSync(ChameleonCommand.setAnimationMode, 0x00,
        data: Uint8List.fromList([animation.value]));
  }

  Future<ChameleonAnimation> getAnimationMode() async {
    var resp = await sendCmdSync(ChameleonCommand.getAnimationMode, 0x00);
    if (resp!.data[0] == 0) {
      return ChameleonAnimation.full;
    } else if (resp.data[0] == 1) {
      return ChameleonAnimation.minimal;
    } else {
      return ChameleonAnimation.none;
    }
  }

  Future<String> getGitCommitHash() async {
    var resp = await sendCmdSync(ChameleonCommand.getGitCommitHash, 0x00);
    return const AsciiDecoder().convert(resp!.data);
  }

  Future<int> getActiveSlot() async {
    // get the selected slot on the device, 0-7 (8 slots)
    return (await sendCmdSync(ChameleonCommand.getActiveSlot, 0x00))!.data[0];
  }

  Future<List<(ChameleonTag, ChameleonTag)>> getUsedSlots() async {
    List<(ChameleonTag, ChameleonTag)> tags = [];
    var resp = await sendCmdSync(ChameleonCommand.getSlotInfo, 0x00);
    for (var i = 0; i < 8; i++) {
      tags.add((
        numberToChameleonTag(resp!.data[(i * 2)]),
        numberToChameleonTag(resp.data[(i * 2) + 1])
      ));
    }
    return tags;
  }

  Future<(bool, bool, bool, bool, ChameleonMf1WriteMode)>
      getMf1EmulatorConfig() async {
    var resp = await sendCmdSync(ChameleonCommand.mf1GetEmulatorConfig, 0x00);
    if (resp!.data.length != 5) throw ("Invalid data length");
    ChameleonMf1WriteMode mode = ChameleonMf1WriteMode.normal;
    if (resp.data[4] == 1) {
      mode = ChameleonMf1WriteMode.deined;
    } else if (resp.data[4] == 2) {
      mode = ChameleonMf1WriteMode.deceive;
    } else if (resp.data[4] == 3) {
      mode = ChameleonMf1WriteMode.shadow;
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
    var resp = await sendCmdSync(ChameleonCommand.mf1GetGen1aMode, 0x00);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setMf1Gen1aMode(bool gen1aMode) async {
    await sendCmdSync(ChameleonCommand.mf1SetGen1aMode, 0x00,
        data: Uint8List.fromList([gen1aMode ? 1 : 0]));
  }

  Future<bool> isMf1Gen2Mode() async {
    var resp = await sendCmdSync(ChameleonCommand.mf1GetGen2Mode, 0x00);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setMf1Gen2Mode(bool gen2Mode) async {
    await sendCmdSync(ChameleonCommand.mf1SetGen2Mode, 0x00,
        data: Uint8List.fromList([gen2Mode ? 1 : 0]));
  }

  Future<bool> isMf1UseFirstBlockColl() async {
    var resp = await sendCmdSync(ChameleonCommand.mf1GetFirstBlockColl, 0x00);
    if (resp!.data.length != 1) throw ("Invalid data length");
    return resp.data[0] == 1;
  }

  Future<void> setMf1UseFirstBlockColl(bool useColl) async {
    await sendCmdSync(ChameleonCommand.mf1SetFirstBlockColl, 0x00,
        data: Uint8List.fromList([useColl ? 1 : 0]));
  }

  Future<ChameleonMf1WriteMode> getMf1WriteMode() async {
    var resp = await sendCmdSync(ChameleonCommand.mf1GetWriteMode, 0x00);
    if (resp!.data.length != 1) throw ("Invalid data length");
    log.d(resp.data[0]);
    if (resp.data[0] == 1) {
      return ChameleonMf1WriteMode.deined;
    } else if (resp.data[0] == 2) {
      return ChameleonMf1WriteMode.deceive;
    } else if (resp.data[0] == 3) {
      return ChameleonMf1WriteMode.shadow;
    } else {
      return ChameleonMf1WriteMode.normal;
    }
  }

  Future<void> setMf1WriteMode(ChameleonMf1WriteMode mode) async {
    await sendCmdSync(ChameleonCommand.mf1SetWriteMode, 0x00,
        data: Uint8List.fromList([mode.value]));
  }

  Future<List<bool>> getEnabledSlots() async {
    var resp = await sendCmdSync(ChameleonCommand.getEnabledSlots, 0x00);
    if (resp!.data.length != 8) throw ("Invalid data length");
    List<bool> slots = [];
    for (var slot = 0; slot < 8; slot++) {
      slots.add(resp.data[slot] != 0);
    }
    return slots;
  }

  Future<(int, int)> getBatteryCharge() async {
    var resp = await sendCmdSync(ChameleonCommand.getBatteryCharge, 0x00);
    if (resp!.data.length != 3) throw ("Invalid data length");
    return (_toInt16BE(resp.data.sublist(0, 2)), resp.data[2]);
  }
}
