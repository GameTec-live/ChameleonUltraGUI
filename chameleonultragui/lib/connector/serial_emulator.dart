import 'dart:async';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/services.dart';

// Class for fake Chameleon Ultra device, aka emulator/demo
// Not all commands are implemented, nor should be
// For now main purpose is Apple reviews, maybe should be used for tests in future

class EmulatorSerial extends AbstractSerial {
  EmulatorSerial({required super.log});

  @override
  Future<bool> performConnect() async {
    return true;
  }

  @override
  Future<bool> performDisconnect() async {
    connected = false;
    return true;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    return [
      Chameleon(
          port: "Demo",
          device: ChameleonDevice.ultra,
          type: ConnectionType.usb,
          dfu: false)
    ];
  }

  Future<bool> connectDevice(String address, bool setPort) async {
    return true;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (emulatedCommands.containsKey(bytesToHex(command))) {
      await messageCallback(hexToBytes(emulatedCommands[bytesToHex(command)]!));
    } else {
      log.e('Missing response for ${bytesToHex(command)}');
    }

    return true;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    portName = "Demo";
    connected = true;
    device = ChameleonDevice.ultra;
    return true;
  }

  @override
  bool isManualConnectionSupported() {
    return false;
  }
}

// write: read
Map<String, String> emulatedCommands = {
  '11ef03fb000000000200':
      '11ef03fb006800207a03e90064044f0000000000640000000000000000000000000000000000000000f9',
  '11ef040100000000fb00': '11ef0401006800039010846408',
  '11ef03e8000000001500': '11ef03e800680002ab0200fe',
  '11ef03f9000000000400':
      '11ef03f9006800138976322e302e302d3234342d67333033643264337e',
  '11ef03ea000000001300': '11ef03ea00680001aa01ff',
  '11ef03fa000000000300': '11ef03fa006800019a0000',
  '11ef03eb000000011101ff': '11ef03eb00680000aa00',
  '11ef03eb000000011102fe': '11ef03eb00680000aa00',
  '11ef03eb000000011103fd': '11ef03eb00680000aa00',
  '11ef03eb000000011104fc': '11ef03eb00680000aa00',
  '11ef03eb000000011105fb': '11ef03eb00680000aa00',
  '11ef03eb000000011106fa': '11ef03eb00680000aa00',
  '11ef03eb000000011107f9': '11ef03eb00680000aa00',
  '11ef03eb00000001110000': '11ef03eb00680000aa00',
  '11ef03e9000000011301ff': '11ef03e900680000ac00',
  '11ef03e900000001130000': '11ef03e900680000ac00',
  '11ef040a00000000f200': '11ef040a0068000d7d05000102030400313233343536bc',
  '11ef03ff00000000fe00':
      '11ef03ff006800108601010100000100000000000000000000fc',
  '11ef03f0000000020b0002fe': '11ef03f0007100009c00',
  '11ef03f0000000020b0001ff': '11ef03f0007100009c00',
  '11ef03f0000000020b0102fd': '11ef03f0007100009c00',
  '11ef03f0000000020b0101fe': '11ef03f0007100009c00',
  '11ef03f0000000020b0202fc': '11ef03f0007100009c00',
  '11ef03f0000000020b0201fd': '11ef03f0007100009c00',
  '11ef03f0000000020b0302fb': '11ef03f0007100009c00',
  '11ef03f0000000020b0301fc': '11ef03f0007100009c00',
  '11ef03f0000000020b0402fa': '11ef03f0007100009c00',
  '11ef03f0000000020b0401fb': '11ef03f0007100009c00',
  '11ef03f0000000020b0502f9': '11ef03f0007100009c00',
  '11ef03f0000000020b0501fa': '11ef03f0007100009c00',
  '11ef03f0000000020b0602f8': '11ef03f0007100009c00',
  '11ef03f0000000020b0601f9': '11ef03f0007100009c00',
  '11ef03f0000000020b0702f7': '11ef03f0007100009c00',
  '11ef03f0000000020b0701f8': '11ef03f0007100009c00',
  '11ef0fb2000000003f00': '11ef0fb200680009ce04deadbeef04000800b8',
  '11ef0fa9000000004800': '11ef0fa900680005db000000000000',
  '11ef1389000000006400': '11ef138900680005f7deadbeef8840',
  '11ef0bb8000000003d00': '11ef0bb800400005f80001111111cc',
  '11ef07d0000000002900': '11ef07d00000000920040000000000000000fc',
  '11ef07d1000000002800': '11ef07d1000200002600',
  '11ef07da0000000619f4006400086040': '11ef07da000100001e00',
  '11ef040b00000000f100':
      '11ef040b006800b2d703e803e903ea03eb03ec03ed03ee03ef03f003f103f203f303f403f503f603f703f803f903fa03fb03fc03fd03ff0400040104020403040404050407040604080409040a040b040c040d040e07d007d107d207d307d407d507d607de07d707d807d907da07db07dc07dd07df0bb80bb90fa00fa10fa40fa50fa60fa70fa80fa90faa0fab0fac0fad0fae0faf0fb00fb10fb20fb30fb40fb50fb60fb70fb80fb90fba0fbb0fbc0fbd0fbe0fbf0fc0138813895e',
  '11ef040e00000000ee00':
      '11ef040e00680010760000000000000000000000000000000000',
};
