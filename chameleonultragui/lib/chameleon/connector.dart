import 'dart:typed_data';
import 'dart:async';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/comms/serial_abstract.dart';
import 'package:logger/logger.dart';
import 'package:enough_convert/enough_convert.dart';

// TODO: Decide if we want to change variable names to camelCase or not
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

enum ChameleonCommand {
  // basic commands
  getAppVersion(1000),
  changeMode(1001),
  getDeviceMode(1002),
  setSlotActivated(1003),
  setSlotTagType(1004),
  setSlotDataDefault(1005),
  setSlotEnable(1006),

  setSlotTagNick(1007),
  getSlotTagNick(1008),

  slotDataConfigSave(1009),

  // bootloader
  enterBootloader(1010),
  getDeviceChipID(1011),

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
  setEM410XemulatorID(5000),

  mf1LoadBlockData(4000),
  mf1SetAntiCollision(4001),

  // mfkey32
  mf1SetDetectionEnable(5003),
  mf1GetDetectionCount(5004),
  mf1GetDetectionResult(5005);

  const ChameleonCommand(this.value);
  final int value;
}

enum ChameleonTag {
  unknown(0),
  EM410X(1),
  mifareMini(2),
  mifare1K(3),
  mifare2K(4),
  mifare4K(5),
  NTAG213(6),
  NTAG215(7),
  NTAG216(8);

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

class ChameleonCard {
  Uint8List UID;
  int SAK;
  Uint8List ATQA;

  ChameleonCard({required this.UID, required this.SAK, required this.ATQA});
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
  int UID;
  int distance;

  ChameleonNTDistance({required this.UID, required this.distance});
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
  int UID;
  int nt1;
  int par;
  int ks1;
  int nr;
  int ar;

  ChameleonDarkside(
      {required this.UID,
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
// TODO: Handle error in messages

class ChameleonCom {
  int baudrate = 115200;
  int dataFrameSof = 0x11;
  int dataMaxLength = 512;
  AbstractSerial? _serialInstance;
  Logger log = Logger();
  GbkCodec codec = const GbkCodec(allowInvalid: false);

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
      {Uint8List? data, Duration timeout = const Duration(seconds: 3)}) async {
    var dataFrame = makeDataFrameBytes(cmd, status, data);
    List<int> dataBuffer = [];
    var dataPosition = 0;
    var dataStatus = 0x0000;
    var dataLength = 0x0000;
    // var startTime = DateTime.now();
    Uint8List readBuffer;

    log.d("Sending: ${bytesToHex(dataFrame)}");
    await _serialInstance!.finishRead();
    await _serialInstance!.write(Uint8List.fromList(dataFrame));

    while (true) {
      while (true) {
        // TODO: return timeout
        readBuffer = await _serialInstance!.read(16384);
        if (readBuffer.isNotEmpty) {
          log.d("Received: ${bytesToHex(readBuffer)}");
          break;
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
                log.e('Data frame no sof byte.');
                break;
              }
            }
            if (dataPosition == 1) {
              if (dataBuffer[dataPosition] !=
                  lrcCalc(dataBuffer.sublist(0, 1))) {
                log.e('Data frame sof lrc error.');
                break;
              }
            }
          } else if (dataPosition == 8) {
            // frame head lrc
            if (dataBuffer[dataPosition] != lrcCalc(dataBuffer.sublist(0, 8))) {
              log.e('Data frame head lrc error.');
              break;
            }
            // frame head complete, cache info
            //dataCmd = _toInt16BE(Uint8List.fromList(dataBuffer.sublist(2, 4)));
            dataStatus =
                _toInt16BE(Uint8List.fromList(dataBuffer.sublist(4, 6)));
            dataLength =
                _toInt16BE(Uint8List.fromList(dataBuffer.sublist(6, 8)));
            if (dataLength > dataMaxLength) {
              log.e('Data frame data length too than of max.');
              break;
            }
          } else if (dataPosition == (8 + dataLength + 1)) {
            if (dataBuffer[dataPosition] ==
                lrcCalc(dataBuffer.sublist(0, dataBuffer.length - 1))) {
              var dataResponse = dataBuffer.sublist(9, 9 + dataLength);
              await _serialInstance!.finishRead();
              return ChameleonMessage(
                  status: dataStatus, data: Uint8List.fromList(dataResponse));
            } else {
              log.e('Data frame finally lrc error.');
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
          UID: resp.data.sublist(0, resp.data[10]),
          SAK: resp.data[12],
          ATQA:
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
    int status =
        (await sendCmdSync(ChameleonCommand.mf1DarksideDetect, 0x00))!.status;
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
        UID: bytesToU32(resp.data.sublist(0, 4)),
        distance: bytesToU32(resp.data.sublist(4, 8)));
  }

  Future<ChameleonNestedNonces> getMf1NestedNonces(int block, int keyType,
      Uint8List keyKnown, int targetBlock, int targetKeyType) async {
    // Collect nonces for nested attack
    // keyType 0x60 if A key, 0x61 B key
    int i = 0;
    var resp = await sendCmdSync(ChameleonCommand.mf1NestedAcquire, 0x00,
        data: Uint8List.fromList(
            [keyType, block, ...keyKnown, targetKeyType, targetBlock]));
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
            [targetKeyType, targetBlock, firstRecover ? 1 : 0, syncMax]));

    if (resp!.data.length != 32) {
      throw ("Invalid data length");
    }

    return ChameleonDarkside(
        UID: bytesToU32(resp.data.sublist(0, 4)),
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
    // Slot 1-8
    await sendCmdSync(ChameleonCommand.setSlotActivated, 0x00,
        data: Uint8List.fromList([slot - 1]));
  }

  Future<void> setSlotType(int slot, ChameleonTag type) async {
    await sendCmdSync(ChameleonCommand.setSlotTagType, 0x00,
        data: Uint8List.fromList([slot - 1, type.value]));
  }

  Future<void> setDefaultDataToSlot(int slot, ChameleonTag type) async {
    await sendCmdSync(ChameleonCommand.setSlotDataDefault, 0x00,
        data: Uint8List.fromList([slot - 1, type.value]));
  }

  Future<void> enableSlot(int slot, bool status) async {
    await sendCmdSync(ChameleonCommand.setSlotEnable, 0x00,
        data: Uint8List.fromList([slot - 1, status ? 1 : 0]));
  }

  Future<void> enableMf1Detection(bool status) async {
    await sendCmdSync(ChameleonCommand.mf1SetDetectionEnable, 0x00,
        data: Uint8List.fromList([status ? 1 : 0]));
  }

  Future<int> getMf1DetectionCount() async {
    var resp = await sendCmdSync(ChameleonCommand.mf1GetDetectionCount, 0x00,
        data: Uint8List(0));
    return resp!.data.buffer.asByteData().getInt16(0, Endian.little);
  }

  Future<Map<int, Map<int, Map<String, List<ChameleonDetectionResult>>>>>
      getMf1DetectionResult(int index) async {
    // Get results from index
    var data = (await sendCmdSync(ChameleonCommand.mf1GetDetectionResult, 0x00,
            data: Uint8List(4)
              ..buffer.asByteData().setInt16(0, index, Endian.big)))!
        .data;
    List<ChameleonDetectionResult> resultList = [];
    int pos = 0;
    while (pos < data.length) {
      resultList.add(ChameleonDetectionResult(
          block: data[0 + pos],
          type: 0x60 + (data[1 + pos] & 0x01),
          isNested: (data[1 + pos] >> 1 & 0x01) == 0x01,
          uid: bytesToU32(data.sublist(2 + pos, 6 + pos)),
          nt: bytesToU32(data.sublist(6 + pos, 10 + pos)),
          nr: bytesToU32(data.sublist(10 + pos, 14 + pos)),
          ar: bytesToU32(data.sublist(14 + pos, 18 + pos))));
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
            Uint8List.fromList([card.SAK, ...card.ATQA.reversed, ...card.UID]));
  }

  Future<String> readEM410X() async {
    var resp = await sendCmdSync(ChameleonCommand.scanEM410Xtag, 0x00,
        data: Uint8List(0));
    return bytesToHex(resp!.data);
  }

  Future<void> setEM410XEmulatorID(Uint8List UID) async {
    await sendCmdSync(ChameleonCommand.setEM410XemulatorID, 0x00, data: UID);
  }

  Future<void> writeEM410XtoT55XX(
      Uint8List UID, Uint8List key, List<Uint8List> oldKeys) async {
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
            [index, frequiency.value, ...codec.encode(name)]));
  }

  Future<String> getSlotTagName(
      int index, ChameleonTagFrequiency frequiency) async {
    var resp = await sendCmdSync(ChameleonCommand.getSlotTagNick, 0x00,
        data: Uint8List.fromList([index, frequiency.value]));
    return codec.decode(resp!.data);
  }

  Future<void> saveSlotData() async {
    await sendCmdSync(ChameleonCommand.slotDataConfigSave, 0x00,
        data: Uint8List(0));
  }

  Future<void> enterDFUMode() async {
    await sendCmdSync(ChameleonCommand.enterBootloader, 0x00,
        data: Uint8List(0));
  }
}
