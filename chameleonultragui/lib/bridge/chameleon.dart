import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:logger/logger.dart';

// Some ChatGPT magic
// Nobody knows how it works

class ChameleonCommunicator {
  int baudrate = 115200;
  int dataFrameSof = 0x11;
  int dataMaxLength = 4096;
  AbstractSerial? _serialInstance;
  List<int> dataBuffer = [];
  int dataPosition = 0;
  int dataCmd = 0;
  int dataStatus = 0;
  int dataLength = 0;
  List<ChameleonMessage> messageQueue = [];
  List<int> commandQueue = [];

  final Logger log;

  ChameleonCommunicator(this.log, {AbstractSerial? port}) {
    if (port != null) {
      open(port);
    }
  }

  dynamic open(AbstractSerial port) {
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
    log.t("Received: ${bytesToHex(Uint8List.fromList(message))}");

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
      bool skipReceive = false,
      bool firstRun = false}) async {
    var startTime = DateTime.now();
    var dataFrame = makeDataFrameBytes(cmd, 0x00, data);

    if (!_serialInstance!.isOpen) {
      await _serialInstance!.open();
      await _serialInstance!.registerCallback(onSerialMessage);
      _serialInstance!.isOpen = true;
    }

    while (commandQueue.contains(cmd.value)) {
      if (startTime.millisecondsSinceEpoch + (timeout.inMilliseconds * 2) <
          DateTime.now().millisecondsSinceEpoch) {
        throw ("Timeout waiting for queue for command ${cmd.value}");
      }

      await asyncSleep(1);
    }

    commandQueue.add(cmd.value);

    log.t("Sending: ${bytesToHex(dataFrame)}");
    log.d(
        "Sending message: command = ${cmd.value}, data = ${bytesToHex(data ?? Uint8List(0))}");

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
          commandQueue.remove(cmd.value);
          return message;
        }
      }

      if (startTime.millisecondsSinceEpoch + timeout.inMilliseconds <
          DateTime.now().millisecondsSinceEpoch) {
        commandQueue.remove(cmd.value);
        if (firstRun) {
          sendCmd(cmd, data: data, timeout: timeout, firstRun: false);
        } else {
          // no luck
          throw ("Timeout waiting for response for command ${cmd.value}");
        }
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

  Future<FirmwareVersion> getFirmwareVersion() async {
    var resp = await sendCmd(ChameleonCommand.getAppVersion);

    // Check for legacy protocol
    if (resp!.data[0] == 0 && resp.data[1] == 1) {
      return FirmwareVersion(legacyProtocol: true, version: 256);
    } else {
      return FirmwareVersion(
          legacyProtocol: false, version: bytesToU16(resp.data));
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
    return resp!.data[0] == 1;
  }

  Future<void> setReaderDeviceMode(bool readerMode) async {
    await sendCmd(ChameleonCommand.changeDeviceMode,
        data: Uint8List.fromList([readerMode ? 1 : 0]));
  }

  Future<CardData?> scan14443aTag() async {
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
      return null;
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
      return NTLevel.static;
    } else if (resp == 1) {
      return NTLevel.weak;
    } else if (resp == 2) {
      return NTLevel.hard;
    } else {
      return NTLevel.unknown;
    }
  }

  Future<DarksideResult> checkMf1Darkside() async {
    // Check card vulnerability to Mifare Classic darkside attack
    var message = (await sendCmd(ChameleonCommand.mf1DarksideAcquire,
        data: Uint8List.fromList([0x61, 0x03, 1, 2]),
        timeout: const Duration(seconds: 60)))!;
    int status = message.status;
    if (message.data.isNotEmpty) {
      status = message.data[0];
    }

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

    return NTDistance(
        uid: bytesToU32(resp!.data.sublist(0, 4)),
        distance: bytesToU32(resp.data.sublist(4, 8)));
  }

  Future<NestedNonces> getMf1NestedNonces(int block, int keyType,
      Uint8List knownKey, int targetBlock, int targetKeyType,
      {NTLevel level = NTLevel.weak, bool slow = false}) async {
    // Collect nonces for nested attack
    // keyType 0x60 if A key, 0x61 B key
    int i = level == NTLevel.static ? 4 : 0;
    ChameleonCommand command = ChameleonCommand.mf1NestedAcquire;
    List<int> padding = [];
    if (level == NTLevel.static) {
      command = ChameleonCommand.mf1StaticNestedAcquire;
    } else if (level == NTLevel.hard) {
      command = ChameleonCommand.mf1HardNestedAcquire;
      padding = [slow ? 1 : 0];
    }

    var resp = await sendCmd(command,
        data: Uint8List.fromList([
          ...padding,
          keyType,
          block,
          ...knownKey,
          targetKeyType,
          targetBlock
        ]),
        timeout: const Duration(seconds: 30));
    var nonces = NestedNonces(nonces: []);

    while (i < resp!.data.length) {
      if (level == NTLevel.static) {
        nonces.nonces.add(NestedNonce(
            nt: bytesToU32(resp.data.sublist(i, i + 4)),
            ntEnc: bytesToU32(resp.data.sublist(i + 4, i + 8)),
            parity: 0));

        i += 8;
      } else {
        nonces.nonces.add(NestedNonce(
            nt: bytesToU32(resp.data.sublist(i, i + 4)),
            ntEnc: bytesToU32(resp.data.sublist(i + 4, i + 8)),
            parity: resp.data[i + 8]));

        i += 9;
      }
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
        timeout: const Duration(seconds: 60));

    if (resp!.data[0] != 0) {
      throw ("Not vulnerable to Darkside");
    }

    resp.data = resp.data.sublist(1);

    return Darkside(
        uid: bytesToU32(resp.data.sublist(0, 4)),
        nt1: bytesToU32(resp.data.sublist(4, 8)),
        par: bytesToU64(resp.data.sublist(8, 16)),
        ks1: bytesToU64(resp.data.sublist(16, 24)),
        nr: bytesToU32(resp.data.sublist(24, 28)),
        ar: bytesToU32(resp.data.sublist(28, 32)));
  }

  Future<(int, NestedNonces, NestedNonces, Uint8List)?>
      getMf1StaticEncryptedNestedAcquire(
          {int sectorCount = 16, int startingSector = 0}) async {
    for (var key in gMifareClassicBackdoorKeys) {
      var resp = await sendCmd(ChameleonCommand.mf1StaticEncryptedNestedAcquire,
          data: Uint8List.fromList([...key, sectorCount, startingSector]));
      if (resp!.status == 0) {
        var uid = bytesToU32(Uint8List.fromList(resp.data.sublist(0, 4)));
        int i = 4;
        var aNonces = NestedNonces(nonces: []);
        var bNonces = NestedNonces(nonces: []);

        while (i < resp.data.length) {
          aNonces.nonces.add(NestedNonce(
              nt: reconstructFullNt(resp.data, i),
              ntEnc: bytesToU32(resp.data.sublist(i + 3, i + 7)),
              parity: parityToInt(resp.data[i + 2])));
          bNonces.nonces.add(NestedNonce(
              nt: reconstructFullNt(resp.data, i + 7),
              ntEnc: bytesToU32(resp.data.sublist(i + 10, i + 14)),
              parity: parityToInt(resp.data[i + 9])));
          i += 14;
        }

        return (uid, aNonces, bNonces, key);
      }
    }

    return null;
  }

  Future<bool> mf1Auth(int block, int keyType, Uint8List key) async {
    // Check if key is valid for block
    // keyType 0x60 if A key, 0x61 B key
    int status = (await sendCmd(ChameleonCommand.mf1CheckKey,
            data: Uint8List.fromList([keyType, block, ...key])))!
        .status;

    return status == 0;
  }

  Future<Uint8List?> mf1AuthMultipleKeys(
      int block, int keyType, List<Uint8List> keys) async {
    var resp = (await sendCmd(ChameleonCommand.mf1CheckKeysOnBlock,
        data: Uint8List.fromList(
            [block, keyType, keys.length, ...keys.expand((key) => key)])));

    return resp!.status == 0 ? resp.data.sublist(1) : null;
  }

  Future<Uint8List> mf1ReadBlock(int block, int keyType, Uint8List key) async {
    // Read block
    // keyType 0x60 if A key, 0x61 B key
    return (await sendCmd(ChameleonCommand.mf1ReadBlock,
            data: Uint8List.fromList([keyType, block, ...key])))!
        .data;
  }

  Future<bool> mf1WriteBlock(
      int block, int keyType, Uint8List key, Uint8List data) async {
    // Write block
    // keyType 0x60 if A key, 0x61 B key
    return (await sendCmd(ChameleonCommand.mf1WriteBlock,
                data: Uint8List.fromList([keyType, block, ...key, ...data])))!
            .status ==
        0;
  }

  Future<void> activateSlot(int slot) async {
    // Slot 0-7
    await sendCmd(ChameleonCommand.setActiveSlot,
        data: Uint8List.fromList([slot]));
  }

  Future<void> setSlotType(int slot, TagType type) async {
    await sendCmd(ChameleonCommand.setSlotTagType,
        data: Uint8List.fromList([slot, ...u16ToBytes(type.value)]));
  }

  Future<void> setDefaultDataToSlot(int slot, TagType type) async {
    await sendCmd(ChameleonCommand.setSlotDataDefault,
        data: Uint8List.fromList([slot, ...u16ToBytes(type.value)]));
  }

  Future<void> enableSlot(int slot, TagFrequency frequency, bool status) async {
    await sendCmd(ChameleonCommand.setSlotEnable,
        data: Uint8List.fromList([slot, frequency.value, status ? 1 : 0]));
  }

  Future<bool> isMf1DetectionMode() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetDetectionStatus);
    return resp!.data[0] == 1;
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

  Future<EM410XCard?> readEM410X() async {
    var resp = await sendCmd(ChameleonCommand.scanEM410Xtag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return EM410XCard.fromBytes(resp.data);
  }

  Future<HIDCard?> readHIDProx() async {
    var resp = await sendCmd(ChameleonCommand.scanHIDProxTag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return HIDCard.fromBytes(resp.data);
  }

  Future<VikingCard?> readViking() async {
    var resp = await sendCmd(ChameleonCommand.scanVikingTag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return VikingCard.fromBytes(resp.data);
  }

  Future<PacCard?> readPac() async {
    var resp = await sendCmd(ChameleonCommand.scanPacTag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return PacCard.fromBytes(resp.data);
  }

  Future<IoProxCard?> readIoProx() async {
    var resp = await sendCmd(ChameleonCommand.scanIoProxTag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return IoProxCard.fromBytes(resp.data);
  }

  Future<void> setEM410XEmulatorID(Uint8List uid) async {
    await sendCmd(ChameleonCommand.setEM410XemulatorID, data: uid);
  }

  Future<void> setHIDProxEmulatorID(Uint8List uid) async {
    await sendCmd(ChameleonCommand.setHIDProxEmulatorID, data: uid);
  }

  Future<void> setVikingEmulatorID(Uint8List uid) async {
    await sendCmd(ChameleonCommand.setVikingEmulatorID, data: uid);
  }

  Future<void> setPacEmulatorID(Uint8List uid) async {
    await sendCmd(ChameleonCommand.setPacEmulatorID, data: uid);
  }

  Future<void> setIoProxEmulatorID(Uint8List uid) async {
    await sendCmd(ChameleonCommand.setIoProxEmulatorID, data: uid);
  }

  Future<void> setIdteckEmulatorID(Uint8List uid) async {
    await sendCmd(ChameleonCommand.setIdteckEmulatorID, data: uid);
  }

  Future<void> writeEM410XtoT55XX(
      Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys) async {
    List<int> keys = [];
    keys.addAll(newKey);
    for (var oldKey in oldKeys) {
      keys.addAll(oldKey);
    }
    if (uid.length == 5) {
      await sendCmd(ChameleonCommand.writeEM410XtoT5577,
          data: Uint8List.fromList([...uid, ...newKey, ...keys]));
      return;
    }
    if (uid.length == 13) {
      await sendCmd(ChameleonCommand.writeEM410XElectraToT5577,
          data: Uint8List.fromList([...uid, ...newKey, ...keys]));
      return;
    }
    throw ("Invalid EM410X UID length");
  }

  Future<void> writeHIDProxToT55XX(
      Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys) async {
    List<int> keys = [];

    keys.addAll(newKey);

    for (var oldKey in oldKeys) {
      keys.addAll(oldKey);
    }

    await sendCmd(ChameleonCommand.writeHIDProxToT5577,
        data: Uint8List.fromList([...uid, ...newKey, ...keys]));
  }

  Future<void> writeVikingToT55XX(
      Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys) async {
    List<int> keys = [];

    keys.addAll(newKey);

    for (var oldKey in oldKeys) {
      keys.addAll(oldKey);
    }

    await sendCmd(ChameleonCommand.writeVikingToT5577,
        data: Uint8List.fromList([...uid, ...newKey, ...keys]));
  }

  Future<void> writePacToT55XX(
      Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys) async {
    List<int> keys = [];

    keys.addAll(newKey);

    for (var oldKey in oldKeys) {
      keys.addAll(oldKey);
    }

    await sendCmd(ChameleonCommand.writePacToT5577,
        data: Uint8List.fromList([...uid, ...newKey, ...keys]));
  }

  Future<void> writeIoProxToT55XX(
      Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys) async {
    List<int> keys = [];

    keys.addAll(newKey);

    for (var oldKey in oldKeys) {
      keys.addAll(oldKey);
    }

    await sendCmd(ChameleonCommand.writeIoProxToT5577,
        data: Uint8List.fromList([...uid, ...newKey, ...keys]));
  }

  Future<Uint8List> lfSniff({int timeoutMs = 2000}) async {
    timeoutMs = timeoutMs.clamp(1, 10000);
    final resp = await sendCmd(ChameleonCommand.lfSniff,
        data: Uint8List.fromList([(timeoutMs >> 8) & 0xFF, timeoutMs & 0xFF]),
        timeout: Duration(seconds: timeoutMs ~/ 1000 + 2));

    if (resp == null) {
      throw ('No response from LF sniff command');
    }

    if (resp.status == 0x40) {
      return resp.data;
    }

    if (resp.status == 0x41) {
      return Uint8List(0);
    }

    throw ('LF sniff failed with status 0x${resp.status.toRadixString(16)}');
  }

  Future<Uint8List> hf14aSniff({int timeoutMs = 5000}) async {
    timeoutMs = timeoutMs.clamp(1, 30000);
    final resp = await sendCmd(ChameleonCommand.hf14aSniff,
        data: Uint8List.fromList([(timeoutMs >> 8) & 0xFF, timeoutMs & 0xFF]),
        timeout: Duration(seconds: timeoutMs ~/ 1000 + 5));

    if (resp == null) {
      throw ('No response from HF sniff command');
    }

    if (resp.status == 0x68 || resp.status == 0x00) {
      return resp.data;
    }

    if (resp.status == 0x01) {
      return Uint8List(0);
    }

    throw ('HF sniff failed with status 0x${resp.status.toRadixString(16)}');
  }

  Future<void> writeIdteckToT55XX(
      Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys) async {
    List<int> keys = [];

    keys.addAll(newKey);

    for (var oldKey in oldKeys) {
      keys.addAll(oldKey);
    }

    await sendCmd(ChameleonCommand.writeIdteckToT5577,
        data: Uint8List.fromList([...uid, ...newKey, ...keys]));
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

  Future<List<SlotNames>> getSlotTagNames() async {
    var resp = await sendCmd(ChameleonCommand.getAllSlotNicks);
    List<SlotNames> slots = List.generate(
      8,
      (_) => SlotNames(),
    );

    int i = 0;
    int index = 0;

    while (i < resp!.data.length && index < 8) {
      int hfLen = resp.data[i];
      i++;
      if (hfLen > 0) {
        slots[index].hf =
            utf8.decode(resp.data.sublist(i, i + hfLen), allowMalformed: true);
        i += hfLen;
      } else {
        slots[index].hf = '';
        i += hfLen;
      }

      int lfLen = resp.data[i];
      i++;
      if (lfLen > 0) {
        slots[index].lf =
            utf8.decode(resp.data.sublist(i, i + lfLen), allowMalformed: true);
        i += lfLen;
      } else {
        slots[index].lf = '';
        i += lfLen;
      }

      index++;
    }

    return slots;
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
    var resp = await sendCmd(ChameleonCommand.getGitVersion);
    return const AsciiDecoder().convert(resp!.data);
  }

  Future<int> getActiveSlot() async {
    // get the selected slot on the device, 0-7 (8 slots)
    return (await sendCmd(ChameleonCommand.getActiveSlot))!.data[0];
  }

  Future<List<SlotTypes>> getSlotTagTypes() async {
    List<SlotTypes> tags = [];
    var resp = await sendCmd(ChameleonCommand.getSlotInfo);
    var index = 0;
    for (var slot = 0; slot < 8; slot++) {
      tags.add(SlotTypes(
        hf: numberToChameleonTag(
            bytesToU16(resp!.data.sublist(index, index + 2))),
        lf: numberToChameleonTag(
            bytesToU16(resp.data.sublist(index + 2, index + 4))),
      ));

      index += 4;
    }
    return tags;
  }

  Future<EmulatorSettings> getMf1EmulatorSettings() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetEmulatorConfig);
    MifareWriteMode mode = MifareWriteMode.normal;

    if (resp!.data[4] == 1) {
      mode = MifareWriteMode.denied;
    } else if (resp.data[4] == 2) {
      mode = MifareWriteMode.deceive;
    } else if (resp.data[4] == 3 || resp.data[4] == 4) {
      mode = MifareWriteMode.shadow;
    }

    return EmulatorSettings(
        isDetectionEnabled: resp.data[0] == 1, // is detection enabled
        isGen1a: resp.data[1] == 1, // is gen1a mode enabled
        isGen2: resp.data[2] == 1, // is gen2 mode enabled
        isAntiColl: resp.data[3] ==
            1, // use anti collision data from block 0 mode enabled
        writeMode: mode // write mode
        );
  }

  Future<bool> isMf1Gen1aMode() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetGen1aMode);
    return resp!.data[0] == 1;
  }

  Future<void> setMf1Gen1aMode(bool gen1aMode) async {
    await sendCmd(ChameleonCommand.mf1SetGen1aMode,
        data: Uint8List.fromList([gen1aMode ? 1 : 0]));
  }

  Future<bool> isMf1Gen2Mode() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetGen2Mode);
    return resp!.data[0] == 1;
  }

  Future<void> setMf1Gen2Mode(bool gen2Mode) async {
    await sendCmd(ChameleonCommand.mf1SetGen2Mode,
        data: Uint8List.fromList([gen2Mode ? 1 : 0]));
  }

  Future<bool> isMf1UseFirstBlockColl() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetFirstBlockColl);
    return resp!.data[0] == 1;
  }

  Future<void> setMf1UseFirstBlockColl(bool useColl) async {
    await sendCmd(ChameleonCommand.mf1SetFirstBlockColl,
        data: Uint8List.fromList([useColl ? 1 : 0]));
  }

  Future<MifareWriteMode> getMf1WriteMode() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetWriteMode);
    if (resp!.data[0] == 1) {
      return MifareWriteMode.denied;
    } else if (resp.data[0] == 2) {
      return MifareWriteMode.deceive;
    } else if (resp.data[0] == 3) {
      return MifareWriteMode.shadow;
    } else {
      return MifareWriteMode.normal;
    }
  }

  Future<void> setMf1WriteMode(MifareWriteMode mode) async {
    await sendCmd(ChameleonCommand.mf1SetWriteMode,
        data: Uint8List.fromList([mode.value]));
  }

  Future<Mf1PrngType> getMf1PrngType() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetPrngType);
    return Mf1PrngType.values.firstWhere(
      (type) => type.value == resp!.data[0],
      orElse: () => throw ("Unknown MF1 PRNG type ${resp!.data[0]}"),
    );
  }

  Future<void> setMf1PrngType(Mf1PrngType type) async {
    await sendCmd(ChameleonCommand.mf1SetPrngType,
        data: Uint8List.fromList([type.value]));
  }

  Future<List<EnabledSlotInfo>> getEnabledSlots() async {
    var resp = await sendCmd(ChameleonCommand.getEnabledSlots);
    List<EnabledSlotInfo> slots = [];
    for (var slot = 0; slot < 8; slot++) {
      slots.add(EnabledSlotInfo(
          hf: resp!.data[slot * 2] != 0, lf: resp.data[slot * 2 + 1] != 0));
    }
    return slots;
  }

  Future<BatteryCharge> getBatteryCharge() async {
    var resp = await sendCmd(ChameleonCommand.getBatteryCharge);
    return BatteryCharge(
        voltage: _toInt16BE(resp!.data.sublist(0, 2)), percent: resp.data[2]);
  }

  Future<ButtonConfig> getButtonConfig(ButtonType type) async {
    var resp = await sendCmd(ChameleonCommand.getButtonPressConfig,
        data: Uint8List.fromList([type.value]));
    return getButtonConfigType(resp!.data[0]);
  }

  Future<void> setButtonConfig(ButtonType type, ButtonConfig mode) async {
    await sendCmd(ChameleonCommand.setButtonPressConfig,
        data: Uint8List.fromList([type.value, mode.value]));
  }

  Future<ButtonConfig> getLongButtonConfig(ButtonType type) async {
    var resp = await sendCmd(ChameleonCommand.getLongButtonPressConfig,
        data: Uint8List.fromList([type.value]));
    return getButtonConfigType(resp!.data[0]);
  }

  Future<void> setLongButtonConfig(ButtonType type, ButtonConfig mode) async {
    await sendCmd(ChameleonCommand.setLongButtonPressConfig,
        data: Uint8List.fromList([type.value, mode.value]));
  }

  Future<int> getSleepTimeout() async {
    var resp = await sendCmd(ChameleonCommand.getSleepTimeout);
    return resp!.data[0];
  }

  Future<void> setSleepTimeout(int seconds) async {
    await sendCmd(ChameleonCommand.setSleepTimeout,
        data: Uint8List.fromList([seconds]));
  }

  Future<int> getLongPressThreshold() async {
    var resp = await sendCmd(ChameleonCommand.getLongPressThreshold);
    return bytesToU16(resp!.data);
  }

  Future<void> setLongPressThreshold(int milliseconds) async {
    await sendCmd(ChameleonCommand.setLongPressThreshold,
        data: u16ToBytes(milliseconds));
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
    return (await sendCmd(ChameleonCommand.getDeviceType))!.data[0] == 0
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

    int uidLength = resp!.data[0];
    int atsLength = resp.data[uidLength + 4];
    return CardData(
      uid: resp.data.sublist(1, uidLength + 1),
      atqa: Uint8List.fromList(
          resp.data.sublist(uidLength + 1, uidLength + 3).reversed.toList()),
      sak: resp.data[uidLength + 3],
      ats: resp.data.sublist(uidLength + 5, uidLength + 5 + atsLength),
    );
  }

  Future<Uint8List> getEM410XEmulatorID() async {
    Uint8List data =
        (await sendCmd(ChameleonCommand.getEM410XemulatorID))!.data;

    if (data.length == 5 || data.length == 13) {
      return data;
    }

    if (data.length >= 2) {
      TagType type = numberToChameleonTag(bytesToU16(data.sublist(0, 2)));
      int uidLength = uidSizeForLfTag(type);

      if (uidLength > 0 && data.length >= uidLength + 2) {
        return data.sublist(2, 2 + uidLength);
      }
    }

    try {
      int slot = await getActiveSlot();
      TagType activeLfType = (await getSlotTagTypes())[slot].lf;
      int uidLength = uidSizeForLfTag(activeLfType);

      if (uidLength > 0) {
        if (data.length >= uidLength + 2) {
          return data.sublist(2, 2 + uidLength);
        }
        if (data.length >= uidLength) {
          return data.sublist(0, uidLength);
        }
      }
    } catch (_) {}

    return data;
  }

  Future<HIDCard> getHIDProxEmulatorID() async {
    return HIDCard.fromBytes(
        (await sendCmd(ChameleonCommand.getHIDProxEmulatorID))!.data);
  }

  Future<VikingCard> getVikingEmulatorID() async {
    return VikingCard.fromBytes(
        (await sendCmd(ChameleonCommand.getVikingEmulatorID))!.data);
  }

  Future<PacCard> getPacEmulatorID() async {
    return PacCard.fromBytes(
        (await sendCmd(ChameleonCommand.getPacEmulatorID))!.data);
  }

  Future<IoProxCard> getIoProxEmulatorID() async {
    return IoProxCard.fromBytes(
        (await sendCmd(ChameleonCommand.getIoProxEmulatorID))!.data);
  }

  Future<IdteckCard> getIdteckEmulatorID() async {
    return IdteckCard.fromBytes(
        (await sendCmd(ChameleonCommand.getIdteckEmulatorID))!.data);
  }

  Future<DeviceSettings> getDeviceSettings() async {
    var resp = (await sendCmd(ChameleonCommand.getDeviceSettings))!.data;
    if (resp.length < 13) {
      throw ("Invalid settings payload");
    }

    AnimationSetting animationMode = getAnimationModeType(resp[1]);
    ButtonConfig aPress = getButtonConfigType(resp[2]),
        bPress = getButtonConfigType(resp[3]),
        aLongPress = getButtonConfigType(resp[4]),
        bLongPress = getButtonConfigType(resp[5]);

    return DeviceSettings(
        animation: animationMode,
        aPress: aPress,
        bPress: bPress,
        aLongPress: aLongPress,
        bLongPress: bLongPress,
        pairingEnabled: resp[6] == 1,
        key: utf8.decode(resp.sublist(7, 13), allowMalformed: true),
        wakeTimeSeconds: resp.length >= 14 ? resp[13] : null);
  }

  Future<List<int>> getDeviceCapabilities() async {
    var resp = (await sendCmd(ChameleonCommand.getDeviceCapabilities))!.data;
    List<int> commands = [];

    for (int i = 0; i < resp.length; i += 2) {
      commands.add(bytesToU16(resp.sublist(i, i + 2)));
    }

    return commands;
  }

  Future<void> manipulateValueBlock(
      int srcBlock,
      int srcKeyType,
      Uint8List srcKey,
      MifareClassicValueBlockOperator op,
      int value,
      int dstBlock,
      int dstKeyType,
      Uint8List dstKey) async {
    await sendCmd(ChameleonCommand.mf1ManipulateValueBlock,
        data: Uint8List.fromList([
          srcKeyType,
          srcBlock,
          ...srcKey,
          op.value,
          value >> 24,
          value >> 16 & 0xFF,
          value >> 8 & 0xFF,
          value & 0xFF,
          dstKeyType,
          dstBlock,
          ...dstKey
        ]));
  }

  Future<Uint8List> send14ARaw(Uint8List data,
      {int respTimeoutMs = 100,
      int? bitLen,
      bool activateRfField = true,
      bool waitResponse = true,
      bool appendCrc = true,
      bool autoSelect = true,
      bool keepRfField = false,
      bool checkResponseCrc = true}) async {
    bitLen ??= data.length * 8; // bits = bytes * 8(bit)
    int options = 0;

    if (activateRfField) {
      options += 128;
    }
    if (waitResponse) {
      options += 64;
    }
    if (appendCrc) {
      options += 32;
    }
    if (autoSelect) {
      options += 16;
    }
    if (keepRfField) {
      options += 8;
    }
    if (checkResponseCrc) {
      options += 4;
    }

    return (await sendCmd(ChameleonCommand.hf14ARawCommand,
            data: Uint8List.fromList([
              options,
              ...u16ToBytes(respTimeoutMs),
              ...u16ToBytes(bitLen),
              ...data
            ])))!
        .data;
  }

  Future<bool> mf0UlcAuth(Uint8List key) async {
    return (await sendCmd(ChameleonCommand.mf0UlcAuth,
                data: Uint8List.fromList([...key])))!
            .status ==
        0;
  }

  Future<Uint8List> mf0UlcReadPages(Uint8List key, int page, int count) async {
    return (await sendCmd(ChameleonCommand.mf0UlcRead,
            data: Uint8List.fromList([...key, page, count])))!
        .data;
  }

  Future<bool> mf0UlcWritePage(Uint8List key, int page, Uint8List data) async {
    return (await sendCmd(ChameleonCommand.mf0UlcWrite,
                data: Uint8List.fromList([...key, page, ...data])))!
            .status ==
        0;
  }

  Future<bool> mf0UlcSetKey(Uint8List oldKey, Uint8List newKey) async {
    return (await sendCmd(ChameleonCommand.mf0UlcSetKey,
                data: Uint8List.fromList([...oldKey, ...newKey])))!
            .status ==
        0;
  }

  Future<void> hf14aSetFieldOn() async {
    await sendCmd(ChameleonCommand.hf14aSetFieldOn);
  }

  Future<void> hf14aSetFieldOff() async {
    await sendCmd(ChameleonCommand.hf14aSetFieldOff);
  }

  Future<bool> mf1GetFieldOffDoReset() async {
    return (await sendCmd(ChameleonCommand.mf1GetFieldOffDoReset))!.data[0] == 1;
  }

  Future<void> mf1SetFieldOffDoReset(bool enabled) async {
    await sendCmd(ChameleonCommand.mf1SetFieldOffDoReset,
        data: Uint8List.fromList([enabled ? 1 : 0]));
  }

  Future<void> deleteSlotTagNick(int index, TagFrequency frequency) async {
    await sendCmd(ChameleonCommand.deleteSlotTagNick,
        data: Uint8List.fromList([index, frequency.value]));
  }

  Future<List<CardData>> scan14443aTagKeep() async {
    var resp = await sendCmd(ChameleonCommand.hf14aScanKeep);
    List<CardData> cards = [];
    if (resp != null && resp.data.isNotEmpty) {
      int offset = 0;
      while (offset < resp.data.length) {
        int uidLength = resp.data[offset];
        int atsLength = resp.data[offset + uidLength + 4];
        cards.add(CardData(
          uid: resp.data.sublist(offset + 1, offset + uidLength + 1),
          atqa: Uint8List.fromList(resp.data
              .sublist(offset + uidLength + 1, offset + uidLength + 3)
              .reversed
              .toList()),
          sak: resp.data[offset + uidLength + 3],
          ats: resp.data.sublist(
              offset + uidLength + 5, offset + uidLength + 5 + atsLength),
        ));
        offset += uidLength + 5 + atsLength;
      }
    }
    return cards;
  }

  Future<Uint8List> hf14aAuthTrace(int block, int keyType, Uint8List key,
      {int timeoutMs = 5000}) async {
    return (await sendCmd(ChameleonCommand.hf14aAuthTrace,
            data: Uint8List.fromList(
                [keyType, block, ...key, (timeoutMs >> 8) & 0xFF, timeoutMs & 0xFF]),
            timeout: Duration(milliseconds: timeoutMs + 3000)))!
        .data;
  }

  Future<(int, int, int, int)> hf14aGetConfig() async {
    var data = (await sendCmd(ChameleonCommand.hf14aGetConfig))!.data;
    int signed(int b) => b > 127 ? b - 256 : b;
    return (signed(data[0]), signed(data[1]), signed(data[2]), signed(data[3]));
  }

  Future<void> hf14aSetConfig(int bcc, int cl2, int cl3, int rats) async {
    await sendCmd(ChameleonCommand.hf14aSetConfig,
        data: Uint8List.fromList(
            [bcc & 0xFF, cl2 & 0xFF, cl3 & 0xFF, rats & 0xFF]));
  }

  Future<Uint8List> ioProxDecodeRaw(Uint8List raw8) async {
    return (await sendCmd(ChameleonCommand.ioProxDecodeRaw,
            data: Uint8List.fromList([...raw8])))!
        .data;
  }

  Future<Uint8List> ioProxComposeID(int version, int facility, int card) async {
    return (await sendCmd(ChameleonCommand.ioProxComposeID,
            data: Uint8List.fromList(
                [version, facility, (card >> 8) & 0xFF, card & 0xFF])))!
        .data;
  }

  Future<Uint8List> adcGenericRead() async {
    return (await sendCmd(ChameleonCommand.adcGenericRead))!.data;
  }

  Future<void> writeT55XX(int block, Uint8List word,
      {Uint8List? password, bool page1 = false}) async {
    bool usePwd = password != null;
    Uint8List pwd = password ?? Uint8List(4);
    await sendCmd(ChameleonCommand.writeT55XX,
        data: Uint8List.fromList(
            [block, ...word, usePwd ? 1 : 0, ...pwd, page1 ? 1 : 0]));
  }

  Future<(int, int, int, bool, int)> scanEM4X05({int password = 0}) async {
    var data = (await sendCmd(ChameleonCommand.scanEM4X05Tag,
            data: Uint8List.fromList([
              (password >> 24) & 0xFF,
              (password >> 16) & 0xFF,
              (password >> 8) & 0xFF,
              password & 0xFF
            ])))!
        .data;
    return (
      bytesToU32(data.sublist(0, 4)),
      bytesToU32(data.sublist(4, 8)),
      bytesToU32(data.sublist(8, 12)),
      data[12] == 1,
      data[13]
    );
  }

  Future<(int, Uint8List)> hf14a4ApduRecv() async {
    var resp = (await sendCmd(ChameleonCommand.hf14a4ApduRecv,
        timeout: const Duration(seconds: 2)))!;
    return (resp.status, resp.data);
  }

  Future<void> hf14a4ApduSend(Uint8List response) async {
    await sendCmd(ChameleonCommand.hf14a4ApduSend,
        data: Uint8List.fromList([
          (response.length >> 8) & 0xFF,
          response.length & 0xFF,
          ...response
        ]));
  }

  Future<void> hf14a4SetAntiColl(
      Uint8List uid, Uint8List atqa, int sak, Uint8List ats) async {
    await sendCmd(ChameleonCommand.hf14a4SetAntiColl,
        data: Uint8List.fromList(
            [uid.length, ...uid, ...atqa, sak, ats.length, ...ats]));
  }

  Future<void> hf14a4AddStaticResponse(
      Uint8List cmd, Uint8List response) async {
    await sendCmd(ChameleonCommand.hf14a4StaticResp,
        data: Uint8List.fromList([
          cmd.length,
          ...cmd,
          (response.length >> 8) & 0xFF,
          response.length & 0xFF,
          ...response
        ]));
  }

  Future<void> hf14a4ClearStaticResponses() async {
    await sendCmd(ChameleonCommand.hf14a4StaticResp,
        data: Uint8List.fromList([0]));
  }

  Future<Uint8List> hf14a4ReaderApdu(Uint8List apdu) async {
    return (await sendCmd(ChameleonCommand.hf14a4ReaderApdu,
            data: Uint8List.fromList([...apdu]),
            timeout: const Duration(seconds: 3)))!
        .data;
  }

  Future<Uint8List> hf14a4EmvScan() async {
    return (await sendCmd(ChameleonCommand.hf14a4EmvScan,
            timeout: const Duration(seconds: 10)))!
        .data;
  }

  // ---- DESFire (Phreakbyte fork additions) ------------------------------
  // Wire layouts copied from software/script/chameleon_cmd.py in
  // nieldk/ChameleonUltra (DESFIRE_* commands, 6006-6013). GET_INFO/
  // GET_CREDENTIAL/FACTORY_BLANK return status 0x60 (PAR_ERR) when the
  // active slot's live DESFire buffer isn't populated yet (set the slot's
  // tag type + default data first).

  Future<DesfireInfo> desfireGetInfo() async {
    var resp = (await sendCmd(ChameleonCommand.desfireGetInfo))!;
    if (resp.status == 0x60) {
      throw ("Slot's live DESFire buffer isn't populated -- set the tag "
          "type and default data on this slot first.");
    }
    var d = resp.data;
    if (d.length < 20) throw ("short DESFire GET_INFO reply (${d.length}b)");
    int uidLen = d[0];
    return DesfireInfo(
      uid: d.sublist(1, 1 + uidLen),
      numApps: d[8],
      numFiles: d[9],
      poolUsed: (d[10] << 8) | d[11],
      poolSize: (d[12] << 8) | d[13],
      credSize: (d[14] << 8) | d[15],
      maxApps: d[16],
      maxKeys: d[17],
      maxFiles: d[18],
      piccAuthCommand: d[19],
    );
  }

  Future<DesfireStats> desfireGetStats() async {
    var resp = (await sendCmd(ChameleonCommand.desfireGetStats))!;
    var d = resp.data;
    if (d.length < 10) throw ("short DESFire GET_STATS reply (${d.length}b)");
    int u16(int o) => (d[o] << 8) | d[o + 1];
    return DesfireStats(
      framesRx: u16(0),
      framesTx: u16(2),
      engineErrors: u16(4),
      maxHandlerUs: u16(6),
      entropyStarvations: u16(8),
      activationRequests: d.length >= 18 ? u16(10) : null,
      atqaTx: d.length >= 18 ? u16(12) : null,
      fdtTimeouts: d.length >= 18 ? u16(14) : null,
      maxResetUs: d.length >= 18 ? u16(16) : null,
    );
  }

  Future<Uint8List> desfireFactoryBlank({Uint8List? uid}) async {
    var payload =
        uid != null && uid.isNotEmpty ? [uid.length, ...uid] : <int>[];
    var resp = (await sendCmd(ChameleonCommand.desfireFactoryBlank,
        data: Uint8List.fromList(payload)))!;
    if (resp.status == 0x60) {
      throw ("Slot's live DESFire buffer isn't populated -- set the tag "
          "type and default data on this slot first.");
    }
    return resp.data; // new UID
  }

  // Credential transfer is chunked (DESFIRE_CHUNK = 480 bytes/call, BLE
  // MTU-constrained); the .dfcb blob itself is opaque here, same as the
  // GUI's other raw-dump paths -- no DfcCredential parsing is done client
  // side.
  static const int desfireChunk = 480;

  Future<Uint8List> desfireGetCredential(
      {void Function(int sent, int total)? progress}) async {
    List<int> out = [];
    int? total;
    int offset = 0;
    for (int i = 0; i < 200; i++) {
      var resp = (await sendCmd(ChameleonCommand.desfireGetCredential,
          data: Uint8List.fromList([(offset >> 8) & 0xFF, offset & 0xFF])))!;
      if (resp.status == 0x60) {
        throw ("Slot's live DESFire buffer isn't populated -- set the tag "
            "type and default data on this slot first.");
      }
      var d = resp.data;
      if (d.length < 6) throw ("short DESFire GET_CREDENTIAL reply");
      int gotTotal = (d[0] << 8) | d[1];
      int gotOffset = (d[2] << 8) | d[3];
      int chunkLen = (d[4] << 8) | d[5];
      if (gotOffset != offset) {
        throw ("device returned offset $gotOffset, expected $offset");
      }
      total ??= gotTotal;
      out.addAll(d.sublist(6, 6 + chunkLen));
      offset += chunkLen;
      progress?.call(offset, total);
      if (chunkLen == 0 || offset >= total) break;
    }
    return Uint8List.fromList(out);
  }

  Future<void> desfireSetCredential(Uint8List blob,
      {void Function(int sent, int total)? progress}) async {
    if (blob.isEmpty) throw ("empty credential blob");
    if (blob.length > 0xFFFF) {
      throw ("credential too large for the protocol (${blob.length} bytes, max 65535)");
    }
    int sent = 0;
    while (sent < blob.length) {
      var chunk = blob.sublist(
          sent, sent + desfireChunk > blob.length ? blob.length : sent + desfireChunk);
      var payload = [
        (blob.length >> 8) & 0xFF, blob.length & 0xFF,
        (sent >> 8) & 0xFF, sent & 0xFF,
        (chunk.length >> 8) & 0xFF, chunk.length & 0xFF,
        ...chunk,
      ];
      var resp = (await sendCmd(ChameleonCommand.desfireSetCredential,
          data: Uint8List.fromList(payload)))!;
      if (resp.status != 0x68) {
        throw ("device rejected the credential at offset $sent (status ${resp.status})");
      }
      sent += chunk.length;
      progress?.call(sent, blob.length);
    }
  }

  // key_reference = (0x80 if aid != null else 0) | keyNo, matching
  // desfire_reader_auth_iso7816's wire encoding (chameleon_cmd.py).
  Future<DesfireAuthResult> desfireReaderAuthIso7816({
    required int keyNo,
    required String algorithm, // '2tdea' | '3tdea' | 'aes'
    required Uint8List key,
    Uint8List? aid,
  }) async {
    const algos = {
      '2tdea': [0x02, 16],
      '3tdea': [0x04, 24],
      'aes': [0x09, 16],
    };
    var algo = algos[algorithm];
    if (algo == null) throw ("algorithm must be one of ${algos.keys}");
    int algByte = algo[0], wantLen = algo[1];
    if (key.length != wantLen) {
      throw ("$algorithm key must be $wantLen bytes, got ${key.length}");
    }
    if (keyNo < 0 || keyNo > 31) throw ("keyNo must be 0-31");
    bool hasAid = aid != null;
    if (hasAid && aid!.length != 3) throw ("aid must be 3 bytes");
    int keyRef = (hasAid ? 0x80 : 0) | keyNo;
    var payload = [
      hasAid ? 1 : 0,
      ...(hasAid ? aid! : Uint8List(3)),
      keyRef, algByte, wantLen,
      ...key,
    ];
    var resp = (await sendCmd(ChameleonCommand.desfireReaderAuthIso7816,
        data: Uint8List.fromList(payload),
        timeout: const Duration(seconds: 3)))!;
    if (resp.status == 0x01) return DesfireAuthResult.noCard;
    if (resp.status != 0x00) return DesfireAuthResult.requestError;
    if (resp.data.isEmpty) return DesfireAuthResult.requestError;
    int rc = resp.data[0];
    if (rc == 0) return DesfireAuthResult.authenticated;
    if (rc == 6 && resp.data.length >= 2) return DesfireAuthResult.cardRejected;
    return DesfireAuthResult.failed;
  }

  // Three-frame GetVersion in one firmware call: frame(1 len+payload+2 SW)
  // repeated `count` times, led by a frame-count byte. Returns the frames
  // with their trailing SW1/SW2 stripped (see splitVersionFrames in the
  // web terminal port of this same decode).
  Future<List<Uint8List>> desfireReaderGetVersion() async {
    var resp = (await sendCmd(ChameleonCommand.desfireReaderGetVersion,
        timeout: const Duration(seconds: 3)))!;
    var blob = resp.data;
    List<Uint8List> frames = [];
    if (blob.isEmpty) return frames;
    int n = blob[0];
    int o = 1;
    for (int i = 0; i < n && o < blob.length; i++) {
      int len = blob[o];
      o++;
      var chunk = blob.sublist(o, o + len);
      o += len;
      frames.add(chunk.length >= 2
          ? chunk.sublist(0, chunk.length - 2)
          : Uint8List(0));
    }
    return frames;
  }

  // GetApplicationIDs (native INS 0x6A) over the generic single-APDU
  // reader primitive (hf14a4ReaderApdu/6004). That primitive re-selects
  // the card on every call, so this can't continue a 0x91/0xAF multi-frame
  // reply -- fine for GetApplicationIDs (always fits one frame), not a
  // general DESFire command runner.
  Future<List<Uint8List>> desfireGetApplicationIds() async {
    var apdu = Uint8List.fromList([0x90, 0x6A, 0x00, 0x00, 0x00]);
    var d = await hf14a4ReaderApdu(apdu);
    if (d.length < 2) throw ("short APDU reply (${d.length} bytes)");
    int sw1 = d[d.length - 2], sw2 = d[d.length - 1];
    if (sw1 != 0x91) {
      throw ("not a DESFire-over-ISO7816 reply (SW1=0x${sw1.toRadixString(16)})");
    }
    if (sw2 == 0xAF) {
      throw ("reply needs a continuation frame -- more AIDs than fit one frame");
    }
    if (sw2 != 0x00) throw ("device status 0x${sw2.toRadixString(16)}");
    var body = d.sublist(0, d.length - 2);
    List<Uint8List> aids = [];
    for (int o = 0; o + 3 <= body.length; o += 3) {
      aids.add(body.sublist(o, o + 3));
    }
    return aids;
  }

  Future<bool> mf0GetMagicMode() async {
    return (await sendCmd(ChameleonCommand.mf0NtagGetUidMagicMode))!.data[0] ==
        1;
  }

  Future<void> mf0SetMagicMode(bool enabled) async {
    await sendCmd(ChameleonCommand.mf0NtagSetUidMagicMode,
        data: Uint8List.fromList([enabled ? 1 : 0]));
  }

  Future<Uint8List> mf0EmulatorReadPages(int from, int count) async {
    return (await sendCmd(ChameleonCommand.mf0NtagReadEmuPageData,
            data: Uint8List.fromList([from, count])))!
        .data;
  }

  Future<void> mf0EmulatorWritePages(int from, Uint8List data) async {
    await sendCmd(ChameleonCommand.mf0NtagWriteEmuPageData,
        data: Uint8List.fromList([from, data.length >> 2, ...data]));
  }

  Future<Uint8List> mf0EmulatorGetVersionData() async {
    return (await sendCmd(ChameleonCommand.mf0NtagGetVersionData))!.data;
  }

  Future<void> mf0EmulatorSetVersionData(Uint8List data) async {
    await sendCmd(ChameleonCommand.mf0NtagSetVersionData,
        data: Uint8List.fromList([...data]));
  }

  Future<Uint8List> mf0EmulatorGetSignatureData() async {
    return (await sendCmd(ChameleonCommand.mf0NtagGetSignatureData))!.data;
  }

  Future<void> mf0EmulatorSetSignatureData(Uint8List data) async {
    await sendCmd(ChameleonCommand.mf0NtagSetSignatureData,
        data: Uint8List.fromList([...data]));
  }

  Future<int> mf0ResetAuthCount() async {
    return (await sendCmd(ChameleonCommand.mf0NtagResetAuthCount))!.data[0];
  }

  Future<int> mf0EmulatorGetPageCount() async {
    return (await sendCmd(ChameleonCommand.mf0NtagGetPageCount))!.data[0];
  }

  Future<(int, bool)> mf0EmulatorGetCounterData(int index) async {
    Uint8List data = (await sendCmd(ChameleonCommand.mf0NtagGetCounterData,
            data: Uint8List.fromList([index])))!
        .data;
    return (((data[2] << 16) | (data[1] << 8) | data[0]), data[3] == 0xBD);
  }

  Future<void> mf0EmulatorSetCounterData(
      int index, int value, bool resetTearing) async {
    await sendCmd(ChameleonCommand.mf0NtagSetCounterData,
        data: Uint8List.fromList([
          index | ((resetTearing ? 1 : 0) << 7),
          value & 0xFF,
          (value >> 8) & 0xFF,
          (value >> 16) & 0xFF
        ]));
  }

  Future<MifareWriteMode> mf0NtagGetWriteMode() async {
    var resp = await sendCmd(ChameleonCommand.mf0NtagGetWriteMode);
    if (resp!.data[0] == 1) {
      return MifareWriteMode.denied;
    } else if (resp.data[0] == 2) {
      return MifareWriteMode.deceive;
    } else if (resp.data[0] == 3) {
      return MifareWriteMode.shadow;
    } else {
      return MifareWriteMode.normal;
    }
  }

  Future<void> mf0NtagSetWriteMode(MifareWriteMode mode) async {
    await sendCmd(ChameleonCommand.mf0NtagSetWriteMode,
        data: Uint8List.fromList([mode.value]));
  }

  Future<bool> mf0NtagGetDetectionEnable() async {
    var resp = await sendCmd(ChameleonCommand.mf0NtagGetDetectionEnable);
    return resp!.data[0] == 1;
  }

  Future<void> mf0NtagSetDetectionEnable(bool enabled) async {
    await sendCmd(ChameleonCommand.mf0NtagSetDetectionEnable,
        data: Uint8List.fromList([enabled ? 1 : 0]));
  }

  Future<int> mf0NtagGetDetectionCount() async {
    var resp = await sendCmd(ChameleonCommand.mf0NtagGetDetectionCount);
    return bytesToU32(resp!.data);
  }

  Future<List<String>> mf0NtagGetDetectionLog(int index) async {
    var resp = await sendCmd(ChameleonCommand.mf0NtagGetDetectionLog,
        data: u32ToBytes(index));

    List<String> resultList = [];
    int pos = 0;
    while (pos < resp!.data.length) {
      var password = resp.data.sublist(pos, pos + 4);
      resultList.add(bytesToHex(password));
      pos += 4;
    }

    return resultList;
  }

  Future<EmulatorSettings> mf0NtagGetEmulatorConfig() async {
    var resp = await sendCmd(ChameleonCommand.mf0NtagGetEmulatorConfig);
    MifareWriteMode mode = MifareWriteMode.normal;

    if (resp!.data[2] == 1) {
      mode = MifareWriteMode.denied;
    } else if (resp.data[2] == 2) {
      mode = MifareWriteMode.deceive;
    } else if (resp.data[2] == 3 || resp.data[2] == 4) {
      mode = MifareWriteMode.shadow;
    }

    return EmulatorSettings(
        isDetectionEnabled: resp.data[0] == 1, // is detection enabled
        isGen1a: false,
        isGen2: resp.data[1] == 1, // is uid magic mode enabled
        isAntiColl: false,
        writeMode: mode // write mode
        );
  }
}
