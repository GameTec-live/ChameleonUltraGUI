import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:logger/logger.dart';
import 'dart:math';

enum ChameleonDFUCommand {
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

  const ChameleonDFUCommand(this.value);
  final int value;
}

enum ChameleonResponseCode {
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

  const ChameleonResponseCode(this.value);
  final int value;

  static ChameleonResponseCode fromValue(int value) {
    return ChameleonResponseCode.values.firstWhere(
        (responseCode) => responseCode.value == value,
        orElse: () => ChameleonResponseCode.invalidCode);
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

  static List<dynamic> decodeAddByte(
      int c, List<int> decodedData, int currentState) {
    bool finished = false;
    if (currentState == slipStateDecoding) {
      if (c == slipByteEnd) {
        finished = true;
      } else if (c == slipByteEsc) {
        currentState = slipStateEscReceived;
      } else {
        decodedData.add(c);
      }
    } else if (currentState == slipStateEscReceived) {
      if (c == slipByteEscEnd) {
        decodedData.add(slipByteEnd);
        currentState = slipStateDecoding;
      } else if (c == slipByteEscEsc) {
        decodedData.add(slipByteEsc);
        currentState = slipStateDecoding;
      } else {
        currentState = slipStateClearingInvalidPacket;
      }
    } else if (currentState == slipStateClearingInvalidPacket) {
      if (c == slipByteEnd) {
        currentState = slipStateDecoding;
        decodedData = [];
      }
    }

    return [finished, currentState, decodedData];
  }
}

class ChameleonDFU {
  int baudrate = 115200;
  int dataFrameSof = 0x11;
  int dataMaxLength = 512;
  int mtu = 0;
  int prn = 0;
  AbstractSerial? _serialInstance;
  Logger log = Logger();

  ChameleonDFU({AbstractSerial? port}) {
    if (port != null) {
      open(port);
    }
  }

  open(AbstractSerial port) {
    _serialInstance = port;
  }

  Future<Uint8List?> sendCmdSync(
      ChameleonDFUCommand cmd, Uint8List data) async {
    var packet = Slip.encode(Uint8List.fromList([cmd.value, ...data.toList()]));

    log.d("Sending: ${bytesToHex(packet)}");
    await _serialInstance!.write(packet);

    List<int> readBuffer = [];

    while (true) {
      readBuffer.addAll(await _serialInstance!.read(16384));
      if (readBuffer.isNotEmpty) {
        break;
      }
    }

    log.d("Received: ${bytesToHex(Uint8List.fromList(readBuffer))}");

    if (readBuffer[0] != ChameleonDFUCommand.response.value) {
      throw ("DFU sent not response");
    }

    if (readBuffer[1] != cmd.value) {
      throw ("DFU sent invalid command response");
    }

    if (readBuffer[2] == ChameleonResponseCode.success.value) {
      return Uint8List.fromList(readBuffer).sublist(3);
    } else {
      if (readBuffer[2] == ChameleonResponseCode.extendedError.value) {
        throw ("DFU error: ${ChameleonResponseCode.fromValue(readBuffer[3])}");
      }
      throw ("DFU error: ${ChameleonResponseCode.fromValue(readBuffer[2])}");
    }
  }

  Future<dynamic> selectObject(int objectType) async {
    var response = (await sendCmdSync(ChameleonDFUCommand.readObject,
        Uint8List.fromList([objectType, 0x00, 0x00, 0x00])))!;
    var maxSize =
        response[0] << 24 | response[1] << 16 | response[2] << 8 | response[3];
    var offset =
        response[4] << 24 | response[5] << 16 | response[6] << 8 | response[7];
    var crc = response[8] << 24 |
        response[9] << 16 |
        response[10] << 8 |
        response[11];
    return {'maxSize': maxSize, 'offset': offset, 'crc': crc};
  }

  Future<void> createObject(int objectType, int objectSize) async {
    final buffer = Uint8List(4);
    buffer.buffer.asByteData().setUint32(0, objectSize, Endian.little);
    await sendCmdSync(ChameleonDFUCommand.createObject,
        Uint8List.fromList([objectType, ...buffer]));
  }

  Future<void> execute() async {
    await sendCmdSync(ChameleonDFUCommand.execute, Uint8List(0));
  }

  Future<void> setPRN() async {
    await sendCmdSync(ChameleonDFUCommand.setPRN, Uint8List.fromList([0x00]));
  }

  Future<int> getMTU() async {
    mtu = ByteData.view(
            (await sendCmdSync(ChameleonDFUCommand.getSerialMTU, Uint8List(0)))!
                .buffer)
        .getUint16(0, Endian.little);
    return mtu;
  }

  Future<Map<String, int>> calculateChecksum() async {
    var response =
        await sendCmdSync(ChameleonDFUCommand.calcChecSum, Uint8List(0));

    var offset = ByteData.view(response!.buffer).getUint32(0, Endian.little);
    var crc = ByteData.view(response.buffer).getUint32(4, Endian.little);

    return {'offset': offset, 'crc': crc};
  }

  Future<void> flashFirmware(int objectType, Uint8List firmwareBytes,
      void Function(int progress) callback) async {
    var object = await selectObject(objectType);
    if (object['maxSize'] < firmwareBytes.length) {
      throw ("Firmware can't fit here!");
    }
    var crc = 0;
    var length = ((mtu - 1) ~/ 2 - 1) * 4;
    for (var offset = 0; offset < firmwareBytes.length; offset += length) {
      await createObject(
          objectType, min(firmwareBytes.length - offset, length));
      crc = await sendFirmware(
          firmwareBytes.sublist(
              offset, min(firmwareBytes.length, offset + length)),
          crc: crc,
          offset: offset);
      await execute();

      callback(((offset / firmwareBytes.length) * 100).round());
      await asyncSleep(3);
    }
  }

  Future<int> sendFirmware(List<int> data,
      {int crc = 0, int offset = 0}) async {
    log.d(
        "Serial: Streaming Data: len:${data.length} offset:$offset crc:0x${crc.toRadixString(16).padLeft(8, '0')} mtu:$mtu");
    Map<String, int> response = {'crc': 0, 'offset': 0};

    void validateCrc() {
      // TODO: fix CRC
      if (crc != response['crc']) {
        log.w(
            "Failed CRC validation. Expected: $crc Received: ${response['crc']}.");
      }
      if (offset != response['offset']!) {
        log.w(
            "Failed offset validation. Expected: $offset Received: ${response['offset']}.");
      }
    }

    for (int i = 0; i < data.length; i += (mtu - 1) ~/ 2 - 1) {
      List<int> toTransmit =
          data.sublist(i, min(i + (mtu - 1) ~/ 2 - 1, data.length));

      var packet = Slip.encode(Uint8List.fromList(
          [ChameleonDFUCommand.writeObject.value, ...toTransmit.toList()]));

      await delayedSend(packet);

      offset += toTransmit.length;
      if (Platform.isAndroid) {
        await asyncSleep(100);
      }
      crc = (calculateCRC32(toTransmit.sublist(1)).toUnsigned(32) & 0xFFFFFFFF)
          .toInt();
      response = await calculateChecksum();
      validateCrc();
    }

    if (Platform.isWindows) {
      // Transmittion errors fix
      await _serialInstance!.read(16384);
    }

    response = await calculateChecksum();

    validateCrc();

    return crc;
  }

  Future<void> delayedSend(Uint8List packet) async {
    // Windows has some issues with transmitting data
    // We work around it by sending message by parts with delay
    var offsetSize = 128;

    if (Platform.isAndroid) {
      offsetSize = 8;
    }

    if (Platform.isWindows || Platform.isAndroid) {
      for (var offset = 0; offset < packet.length; offset += offsetSize) {
        if (min(offsetSize, packet.length - offset) != offsetSize) {
          for (var secondOffset = 0;
              secondOffset < min(offsetSize, packet.length - offset);
              secondOffset++) {
            await _serialInstance!.write(
                packet.sublist(
                    offset + secondOffset, offset + secondOffset + 1),
                firmware: true);
            await asyncSleep(100);
          }
        } else {
          await _serialInstance!.write(
              packet.sublist(
                  offset, offset + min(offsetSize, packet.length - offset)),
              firmware: true);
        }

        await asyncSleep(100);
      }
    } else {
      // Other OS: send as is
      _serialInstance!.write(packet, firmware: true);
    }
  }
}
