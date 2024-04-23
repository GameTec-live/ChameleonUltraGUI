import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:logger/logger.dart';
import 'dart:math';

enum DFUCommand {
  createObject(0x01),
  setPRN(0x02),
  calcChecSum(0x03),
  execute(0x04),
  readError(0x05),
  readObject(0x06),
  getSerialMTU(0x07),
  writeObject(0x08),
  ping(0x09),
  getHW(0x0a),
  response(0x60);

  const DFUCommand(this.value);
  final int value;
}

enum DFUResponseCode {
  invalidCode(0x00),
  success(0x01),
  notSupported(0x02),
  invalidParameter(0x03),
  insufficientResources(0x04),
  invalidObject(0x05),
  invalidSignature(0x06),
  unsupportedType(0x07),
  operationNotPermitted(0x08),
  operationFailed(0x0A),
  extendedError(0x0B);

  const DFUResponseCode(this.value);
  final int value;

  static DFUResponseCode fromValue(int value) {
    return DFUResponseCode.values.firstWhere(
        (responseCode) => responseCode.value == value,
        orElse: () => DFUResponseCode.invalidCode);
  }
}

class Slip {
  static const int slipByteEnd = 0xc0;
  static const int slipByteEsc = 0xdb;
  static const int slipByteEscEnd = 0xdc;
  static const int slipByteEscEsc = 0xdd;

  static const int slipStateDecoding = 1;
  static const int slipStateEscReceived = 2;
  static const int slipStateClearingInvalidPacket = 3;

  static Uint8List encode(Uint8List data) {
    List<int> newData = [];
    for (int elem in data) {
      if (elem == slipByteEnd) {
        newData.add(slipByteEsc);
        newData.add(slipByteEscEnd);
      } else if (elem == slipByteEsc) {
        newData.add(slipByteEsc);
        newData.add(slipByteEscEsc);
      } else {
        newData.add(elem);
      }
    }
    newData.add(slipByteEnd);
    return Uint8List.fromList(newData);
  }

  static Uint8List decode(Uint8List data) {
    bool finished = false;
    int state = slipStateDecoding;
    List<int> decoded = [];
    for (var byte in data) {
      (finished, state, decoded) = Slip.decodeAddByte(byte, decoded, state);
      if (finished) {
        break;
      }
    }

    return Uint8List.fromList(decoded);
  }

  static (bool, int, List<int>) decodeAddByte(
      int byte, List<int> previous, int currentState) {
    bool finished = false;
    List<int> decoded = previous;
    if (currentState == slipStateDecoding) {
      if (byte == slipByteEnd) {
        finished = true;
      } else if (byte == slipByteEsc) {
        currentState = slipStateEscReceived;
      } else {
        decoded.add(byte);
      }
    } else if (currentState == slipStateEscReceived) {
      if (byte == slipByteEscEnd) {
        decoded.add(slipByteEnd);
        currentState = slipStateDecoding;
      } else if (byte == slipByteEscEsc) {
        decoded.add(slipByteEsc);
        currentState = slipStateDecoding;
      } else {
        currentState = slipStateClearingInvalidPacket;
      }
    } else if (currentState == slipStateClearingInvalidPacket) {
      if (byte == slipByteEnd) {
        currentState = slipStateDecoding;
        decoded = [];
      }
    }

    return (finished, currentState, decoded);
  }
}

class DFUTransferError implements Exception {
  String cause;
  DFUTransferError(this.cause);
}

class DFUCommunicator {
  int baudrate = 115200;
  int dataFrameSof = 0x11;
  int dataMaxLength = 512;
  int mtu = 0;
  int prn = 0;
  bool isBLE = false;
  AbstractSerial? _serialInstance;
  Completer<List<int>>? responseCompleter;

  final Logger log;

  DFUCommunicator(this.log, {AbstractSerial? port, bool viaBLE = false}) {
    isBLE = viaBLE;
    if (port != null) {
      open(port);
    }
  }

  open(AbstractSerial port) {
    _serialInstance = port;
  }

  Future<Uint8List?> sendCmd(DFUCommand cmd, Uint8List data) async {
    var packet = Uint8List.fromList([cmd.value, ...data]);
    if (!isBLE) {
      packet = Slip.encode(packet);
    }

    if (responseCompleter != null && !responseCompleter!.isCompleted) {
      responseCompleter?.complete([]);
    }

    responseCompleter = Completer<List<int>>();

    if (!_serialInstance!.isOpen) {
      await _serialInstance!.open();
      _serialInstance!.isOpen = true;
    }

    // we initialize completer each time in DFU, because it being recreated on each message
    await _serialInstance!.registerCallback(responseCompleter?.complete);

    log.d("Sending: ${bytesToHex(packet)}");
    await _serialInstance!.write(packet);

    List<int>? readBuffer = await responseCompleter?.future;

    if (readBuffer == null || readBuffer.isEmpty) {
      return null;
    }

    log.d("Received: ${bytesToHex(Uint8List.fromList(readBuffer))}");

    if (!isBLE) {
      readBuffer = Slip.decode(Uint8List.fromList(readBuffer)).toList();
      log.d("Slip decoded: ${bytesToHex(Uint8List.fromList(readBuffer))}");
    }

    if (readBuffer[0] != DFUCommand.response.value) {
      throw ("DFU sent not response");
    }

    if (readBuffer[1] != cmd.value) {
      throw DFUTransferError("Received unexpected DFU command");
    }

    if (readBuffer[2] == DFUResponseCode.success.value) {
      return Uint8List.fromList(readBuffer).sublist(3);
    } else {
      if (readBuffer[2] == DFUResponseCode.extendedError.value) {
        throw ("DFU error: ${DFUResponseCode.fromValue(readBuffer[3])}");
      }
      throw ("DFU error: ${DFUResponseCode.fromValue(readBuffer[2])}");
    }
  }

  Future<dynamic> selectObject(int objectType) async {
    var response = (await sendCmd(DFUCommand.readObject,
        Uint8List.fromList([objectType, 0x00, 0x00, 0x00])))!;
    var maxSize = ByteData.view(response.buffer).getUint32(0, Endian.little);
    var offset = ByteData.view(response.buffer).getUint32(4, Endian.little);
    var crc = ByteData.view(response.buffer).getUint32(8, Endian.little);
    return {'maxSize': maxSize, 'offset': offset, 'crc': crc};
  }

  Future<void> createObject(int objectType, int objectSize) async {
    final buffer = Uint8List(4);
    buffer.buffer.asByteData().setUint32(0, objectSize, Endian.little);
    await sendCmd(
        DFUCommand.createObject, Uint8List.fromList([objectType, ...buffer]));
  }

  Future<void> execute() async {
    await sendCmd(DFUCommand.execute, Uint8List(0));
  }

  Future<void> setPRN() async {
    await sendCmd(DFUCommand.setPRN, Uint8List.fromList([0x00]));
  }

  Future<int> getMTU() async {
    try {
      mtu = ByteData.view(
              (await sendCmd(DFUCommand.getSerialMTU, Uint8List(0)))!.buffer)
          .getUint16(0, Endian.little);
    } catch (_) {
      mtu = 2051;
    }

    if (mtu == 0) {
      mtu = 2051;
    }

    return mtu;
  }

  Future<Map<String, int>> calculateChecksum() async {
    var response = await sendCmd(DFUCommand.calcChecSum, Uint8List(0));
    var offset = ByteData.view(response!.buffer).getUint32(0, Endian.little);
    var crc = ByteData.view(response.buffer).getUint32(4, Endian.little);

    return {'offset': offset, 'crc': crc};
  }

  Future<void> flashFirmware(int objectType, Uint8List firmwareBytes,
      void Function(int progress) callback) async {
    var object = await selectObject(objectType);

    var crc = 0;
    var length = object['maxSize'] as int;
    for (var offset = 0; offset < firmwareBytes.length; offset += length) {
      var tries = 0;
      var crcBackup = crc;
      for (; tries < ((Platform.isIOS) ? 50 : 10); tries++) {
        await createObject(
            objectType, min(firmwareBytes.length - offset, length));

        try {
          crc = await sendFirmware(
              firmwareBytes.sublist(
                  offset, min(firmwareBytes.length, offset + length)),
              crc: crc,
              offset: offset);
        } on DFUTransferError {
          log.w("Got error, trying ($tries) to recover...");
          object = await selectObject(objectType);
          crc = crcBackup;
          continue;
        }

        await asyncSleep(1);
        await execute();
        callback(((offset / firmwareBytes.length) * 100).round());
        await asyncSleep(1);
        break;
      }

      if (tries == ((Platform.isIOS) ? 50 : 10)) {
        throw ("Unable to recover from DFU");
      }
    }
  }

  Future<int> sendFirmware(List<int> data,
      {int crc = 0, int offset = 0}) async {
    log.d(
        "Serial: Streaming Data: len:${data.length} offset:$offset crc:0x${crc.toRadixString(16).padLeft(8, '0')} mtu:$mtu");
    Map<String, int> response = {'crc': 0, 'offset': 0};

    void validateCrc() {
      if (offset != response['offset']!) {
        log.w(
            "Failed offset validation. Expected: $offset Received: ${response['offset']}.");
        throw DFUTransferError("Offset");
      }
      if (crc != response['crc']) {
        log.w(
            "Failed CRC validation. Expected: $crc Received: ${response['crc']}.");
        throw DFUTransferError("CRC");
      }
    }

    var currentPrn = 0;
    for (int i = 0; i < data.length; i += (mtu - 1) ~/ 2 - 1) {
      List<int> toTransmit =
          data.sublist(i, min(i + (mtu - 1) ~/ 2 - 1, data.length));

      var packet = Uint8List.fromList([...toTransmit]);

      if (!isBLE) {
        packet = Slip.encode(
            Uint8List.fromList([DFUCommand.writeObject.value, ...toTransmit]));
      }

      await delayedSend(packet);

      offset += toTransmit.length;
      crc = calculateCRC32(toTransmit, crc) & 0xFFFFFFFF;
      currentPrn++;
      if (currentPrn == prn) {
        await asyncSleep(1);
        response = await calculateChecksum();
        validateCrc();
        currentPrn = 0;
      }
    }

    await asyncSleep(1);
    response = await calculateChecksum();
    validateCrc();

    return crc;
  }

  Future<void> delayedSend(Uint8List packet) async {
    // Windows has some issues with transmitting data
    // We work around it by sending message by parts with delay
    var offsetSize = 128;
    if (isBLE) {
      offsetSize = 20;
    }

    if (Platform.isWindows || Platform.isMacOS || isBLE) {
      for (var offset = 0; offset < packet.length; offset += offsetSize) {
        await _serialInstance!.write(
            packet.sublist(
                offset, offset + min(offsetSize, packet.length - offset)),
            firmware: true);
      }

      if (Platform.isIOS) {
        await asyncSleep(250);
      }
    } else {
      // Other OS: send as is
      await _serialInstance!.write(packet, firmware: true);
    }
  }
}
