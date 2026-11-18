import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

import 'sl1_profile_test.dart' show fixture;

/// Test-only byte peer. It never invokes an OS serial/BLE implementation.
class FragmentedProfilePeer extends AbstractSerial {
  final ConnectionType kind;
  FragmentedProfilePeer({required super.log, required this.kind});
  final commands = <int>[];
  final payloads = <List<int>>[];
  bool supported = true;
  bool reader = true;
  bool staged = false;
  bool configured = false;
  bool dropNextWrite = false;
  int beginStatus = 0x68;
  int received = 0;
  int opens = 0;
  int registrations = 0;
  int fragments = 0;
  @override
  bool isManualConnectionSupported() => true;
  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];
  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    connected = true;
    device = ChameleonDevice.ultra;
    connectionType = kind;
    activeDevicePort = devicePort;
    return true;
  }

  @override
  Future<bool> performDisconnect() async {
    resetConnectionState();
    return true;
  }

  @override
  Future<void> open() async {
    opens++;
  }

  @override
  Future<void> registerCallback(dynamic callback) async {
    registrations++;
    await super.registerCallback(callback);
  }

  int checksum(Iterable<int> bytes) =>
      (-bytes.fold<int>(0, (sum, b) => sum + b)) & 255;
  @override
  Future<bool> write(Uint8List frame, {bool firmware = false}) async {
    // Decode and independently check the real communicator's request frame.
    expect(frame[0], 0x11);
    expect(frame[1], checksum([0x11]));
    expect(frame.take(9).fold<int>(0, (sum, b) => sum + b) & 255, 0);
    expect(frame.fold<int>(0, (sum, b) => sum + b) & 255, 0);
    final length = (frame[6] << 8) | frame[7];
    expect(frame.length, length + 10);
    final command = (frame[2] << 8) | frame[3];
    final payload = frame.sublist(9, 9 + length);
    commands.add(command);
    payloads.add(payload);
    var status = 0x68;
    var response = <int>[];
    if (command == ChameleonCommand.getDeviceCapabilities.value) {
      response = [
        if (supported)
          for (var c = 4045; c <= 4051; c++) ...[c >> 8, c & 255],
      ];
    } else if (command == ChameleonCommand.getDeviceMode.value) {
      response = [reader ? 1 : 0];
    } else if (command == ChameleonCommand.changeDeviceMode.value) {
      reader = payload[0] == 1;
    } else if (command == 4045) {
      response = [
        1,
        payload[1],
        (staged ? 8 : 0) | (configured ? 1 : 0),
        3,
        232,
        1,
        0x90,
        4,
        0,
        received,
        0,
        20,
        0x68,
        staged ? 1 : 7,
      ];
    } else if (command == 4046) {
      status = beginStatus;
      if (status == 0x68) {
        staged = true;
        received = 0;
      }
    } else if (command == 4047) {
      received = ((payload[2] << 8) | payload[3]) + (payload.length - 4) ~/ 16;
      if (dropNextWrite) {
        dropNextWrite = false;
        await performDisconnect();
        return true;
      }
    } else if (command == 4048) {
      expect(received, 20);
      configured = true;
      staged = false;
    }
    final reply = <int>[
      0x11,
      0xef,
      command >> 8,
      command & 255,
      status >> 8,
      status & 255,
      response.length >> 8,
      response.length & 255,
    ];
    reply.add(checksum(reply));
    reply.addAll(response);
    reply.add(checksum(reply));
    final sizes = kind == ConnectionType.usb
        ? [1, 2, 1, 4, 7]
        : [3, 1, 5, 2, 20];
    for (var offset = 0, index = 0; offset < reply.length; index++) {
      final end = (offset + sizes[index % sizes.length]).clamp(0, reply.length);
      fragments++;
      await messageCallback(Uint8List.fromList(reply.sublist(offset, end)));
      offset = end;
    }
    return true;
  }
}

Future<
  (FragmentedProfilePeer, ChameleonCommunicator, SharedPreferencesProvider)
>
peer(ConnectionType kind) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = SharedPreferencesProvider();
  await preferences.load();
  final log = Logger(
    output: SharedPreferencesLogger(preferences),
    filter: ChameleonLogFilter(),
    printer: SimplePrinter(colors: false),
  );
  final serial = FragmentedProfilePeer(log: log, kind: kind);
  await serial.connectSpecificDevice('synthetic-local-peer');
  return (serial, ChameleonCommunicator(log, port: serial), preferences);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in [ConnectionType.usb, ConnectionType.ble]) {
    test(
      '${kind.name} fragmented real codec and reconnect retain complete synthetic debug',
      () async {
        final (serial, communicator, preferences) = await peer(kind);
        await communicator.sl1Uploader.upload(fixture(), 3);
        expect(serial.commands.where((c) => c == 4048), hasLength(1));
        expect(serial.fragments, greaterThan(serial.commands.length * 2));
        final begin = serial.payloads[serial.commands.indexOf(4046)];
        final marker = fixture().json['cardAuth']['key'] as String;
        expect(Sl1Profile.encodeBytes(begin.sublist(20, 36)), marker);
        expect(
          preferences.getLogLines().join('\n'),
          contains(marker.toLowerCase()),
        );
        await serial.performDisconnect();
        await serial.connectSpecificDevice('synthetic-reconnect');
        final status = await communicator.sl1Uploader.status(3);
        expect(status[2] & 1, 1);
        expect(serial.opens, 2);
        expect(serial.registrations, 2);
        expect(communicator.dataBuffer, isEmpty);
        expect(communicator.commandQueue, isEmpty);
      },
    );
    test(
      '${kind.name} real codec rejects unsupported and numeric failure without SAVE',
      () async {
        final (serial, communicator, _) = await peer(kind);
        serial.supported = false;
        await expectLater(
          communicator.sl1Uploader.upload(fixture(), 3),
          throwsUnsupportedError,
        );
        expect(serial.commands, [ChameleonCommand.getDeviceCapabilities.value]);
        serial.supported = true;
        serial.commands.clear();
        serial.payloads.clear();
        serial.beginStatus = 0x66;
        await expectLater(
          communicator.sl1Uploader.upload(fixture(), 3),
          throwsA(predicate((e) => e.toString().contains('status 102'))),
        );
        expect(serial.commands, isNot(contains(4047)));
        expect(serial.commands, isNot(contains(4048)));
        expect(communicator.commandQueue, isEmpty);
      },
    );
    test(
      '${kind.name} dropped response times out then explicitly reconnects without commit',
      () async {
        final (serial, communicator, preferences) = await peer(kind);
        serial.dropNextWrite = true;
        await expectLater(
          communicator.sl1Uploader.upload(fixture(), 3),
          throwsA(
            predicate(
              (e) => e.toString().contains('Timeout waiting for response'),
            ),
          ),
        );
        expect(serial.commands, isNot(contains(4048)));
        expect(serial.staged, isTrue);
        expect(communicator.commandQueue, isEmpty);
        await serial.connectSpecificDevice('synthetic-reconnect');
        final status = await communicator.sl1Uploader.status(3);
        expect(status[2] & 8, 8);
        expect(status[9], 8);
        expect(serial.opens, 2);
        expect(serial.commands, isNot(contains(4048)));
        expect(
          preferences.getLogLines().join('\n'),
          contains((fixture().json['cardAuth']['key'] as String).toLowerCase()),
        );
      },
    );
  }
}
