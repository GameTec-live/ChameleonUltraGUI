import 'dart:typed_data';

import 'package:chameleonultragui/bridge/dfu.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_test/flutter_test.dart';

class SerialConnectorTest extends AbstractSerial {
  int chunkCount = 1;

  @override
  open() async {
    isOpen = true;
  }

  @override
  write(Uint8List command, {bool firmware = false}) async {
    asyncSleep(10).then((_) {
      for (var uint = 1; uint <= chunkCount; uint++) {
        messageCallback!([uint]);
      }
    });

    return true;
  }

  @override
  connectSpecificDevice(devicePort) async {
    return true;
  }
}

class DFUCommunicatorTest extends DFUCommunicator {
  DFUCommunicatorTest({super.port, super.viaBLE});

  @override
  Uint8List parseCmdResponse(List<int> readBuffer, DFUCommand cmd) {
    return Uint8List.fromList(readBuffer);
  }
}

void main() {
  test('Send command that returns 1 chunk', () async {
    final port = SerialConnectorTest();
    final communicator = DFUCommunicatorTest(port: port);

    final response = await communicator.sendCmd(DFUCommand.ping, Uint8List.fromList([0]));

    assert(response != null, 'Invalid empty response');
    assert(response!.length == 1, 'Response should have a length of 1, got ${response.length}');
    assert(response![0] == 1, 'Expected response to be one');
  });

  test('Send command that returns 2 chunks', () async {
    final port = SerialConnectorTest();
    port.chunkCount = 2;
    final communicator = DFUCommunicatorTest(port: port);

    final response = await communicator.sendCmd(DFUCommand.ping, Uint8List(0));

    assert(response != null, 'Invalid empty response');
    assert(response!.length == 2, 'Response should have a length of 2, got ${response.length}');
    assert(response![0] == 1, 'Expected response to echo the sent data');
    assert(response![1] == 2, 'Expected response to echo the sent data');
  });
}