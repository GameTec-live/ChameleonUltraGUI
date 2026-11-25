import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/ble_trace.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble_windows.dart';
import 'package:chameleonultragui/connector/serial_native.dart';
import 'package:chameleonultragui/connector/windows_route_policy.dart';
import 'package:chameleonultragui/helpers/ble_pairing.dart';

/// Combines Windows USB serial and BLE serial with USB priority.
class WindowsSerial extends AbstractSerial {
  late final WindowsBLESerial bleSerial = WindowsBLESerial(log: log);
  late final NativeSerial nativeSerial = NativeSerial(log: log);

  final WindowsRoutePolicy _route = WindowsRoutePolicy();
  bool _usbConnected = false;
  bool _usbConnectInFlight = false;
  bool _usbProbeBusy = false;
  bool _bleStarted = false;
  DateTime? _usbRetryAfter;
  Future<List<Chameleon>>? _usbProbeFuture;
  Future<bool>? _nativeConnectFuture;

  WindowsSerial({required super.log}) {
    bleSerial.connectionStateCallback = () {
      _route.markBleConnected(bleSerial.connected);
      notifyConnectionStateChanged();
    };
    nativeSerial.connectionStateCallback = () {
      if (nativeSerial.connected) {
        _usbConnected = true;
        _route.usbPresent = true;
      }
      notifyConnectionStateChanged();
    };
    bleSerial.isOtherBusy = () =>
        nativeSerial.connected || nativeSerial.pendingConnection;
    BlePairingService.instance.usbActive = () =>
        _route.usbPresent ||
        nativeSerial.connected ||
        nativeSerial.pendingConnection;
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final devices = await _probeUsb();
    final found = devices.where((device) => !device.dfu).toList();
    final decision = _route.startup(usbFound: found.isNotEmpty);
    _logRoute(decision);
    if (decision.connectUsb && found.isNotEmpty) {
      await _connectUsb(found.first);
    } else {
      _startBle();
    }
    Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_pollUsb()));
  }

  Future<List<Chameleon>> _probeUsb() {
    final existing = _usbProbeFuture;
    if (existing != null) {
      return existing;
    }
    final future = nativeSerial
        .availableChameleons(false)
        .catchError((_) => <Chameleon>[]);
    _usbProbeFuture = future;
    return future.whenComplete(() {
      if (identical(_usbProbeFuture, future)) {
        _usbProbeFuture = null;
      }
    });
  }

  void _startBle() {
    if (_route.usbPresent ||
        nativeSerial.connected ||
        nativeSerial.pendingConnection) {
      return;
    }
    if (!_bleStarted) {
      _bleStarted = true;
      bleSerial.startWatching();
    }
  }

  Future<void> _pollUsb() async {
    if (_usbProbeBusy) {
      return;
    }
    _usbProbeBusy = true;
    try {
      if (nativeSerial.connected) {
        _usbConnected = true;
        _route.usbPresent = true;
        final port = nativeSerial.portName;
        final ports = await nativeSerial.availableDevices();
        if (port.isNotEmpty && !ports.contains(port)) {
          await nativeSerial.performDisconnect();
        } else {
          return;
        }
      }

      final bleConnected = bleSerial.connected;
      _route.markBleConnected(bleConnected);

      if (_usbConnected && !nativeSerial.connected) {
        _usbConnected = false;
        final decision = _route.usbRemoved();
        _logRoute(decision);
        if (!bleConnected) {
          bleSerial.resumeAfterUsb();
        }
      }

      if (bleConnected) {
        return;
      }

      final retryAfter = _usbRetryAfter;
      if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
        return;
      }

      final found = (await _probeUsb()).where((device) => !device.dfu).toList();
      if (found.isNotEmpty) {
        if (!_route.usbPresent) {
          _logRoute(_route.usbAppeared());
        } else {
          _route.usbPresent = true;
        }
        await _connectUsb(found.first);
        return;
      }

      if (_route.usbPresent) {
        _logRoute(_route.usbRemoved());
      }
      _route.usbPresent = false;
      _startBle();
    } finally {
      _usbProbeBusy = false;
    }
  }

  Future<bool> _connectUsb(Chameleon device) async {
    if (_usbConnectInFlight ||
        nativeSerial.connected ||
        nativeSerial.pendingConnection ||
        bleSerial.connected) {
      return false;
    }
    _usbConnectInFlight = true;
    _route.usbPresent = true;
    try {
      await bleSerial.suspendForUsb();
      final ok = await _connectNativePort(device.port);
      if (ok) {
        _usbConnected = true;
        _usbRetryAfter = null;
        BleTrace.instance.log(
          'route',
          'selected=usb reason=${_route.usbPresent ? 'usb-priority' : 'usb'}',
        );
        notifyConnectionStateChanged();
        return true;
      }
      _usbRetryAfter = DateTime.now().add(const Duration(seconds: 10));
      _route.usbPresent = false;
      BleTrace.instance.log('route', 'selected=ble reason=usb-connect-failed');
      bleSerial.resumeAfterUsb();
      return false;
    } finally {
      _usbConnectInFlight = false;
    }
  }

  Future<bool> _connectNativePort(dynamic port) {
    if (_nativeConnectFuture != null) {
      return Future<bool>.value(false);
    }
    final future = nativeSerial.connectSpecificDevice(port);
    _nativeConnectFuture = future;
    return future.whenComplete(() {
      _nativeConnectFuture = null;
    });
  }

  void _logRoute(WindowsRouteDecision decision) {
    BleTrace.instance.log(
      'route',
      'selected=${decision.route.name} reason=${decision.reason}',
    );
  }

  @override
  Future<bool> performDisconnect() async {
    final ble = await bleSerial.performDisconnect();
    final native = await nativeSerial.performDisconnect();
    _usbConnected = false;
    _route.markBleConnected(false);
    if (!_usbConnectInFlight) {
      _route.usbPresent = false;
      bleSerial.resumeAfterUsb();
      _startBle();
    }
    return ble || native;
  }

  @override
  bool isManualConnectionSupported() {
    return nativeSerial.isManualConnectionSupported();
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    // BLE is handled by the always-on watcher; the page only lists USB devices.
    final devices = await _probeUsb();
    return onlyDFU ? devices.where((device) => device.dfu).toList() : devices;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    final port = devicePort.toString();
    if (RegExp(r'^COM\d+$', caseSensitive: false).hasMatch(port)) {
      if (nativeSerial.connected &&
          nativeSerial.activeDevicePort?.toString() == port) {
        return true;
      }
      if (bleSerial.connected || bleSerial.pendingConnection) {
        return false;
      }
      return await _connectNativePort(devicePort);
    }
    if (_route.usbPresent ||
        nativeSerial.connected ||
        nativeSerial.pendingConnection) {
      return false;
    }
    return await bleSerial.connectSpecificDevice(devicePort);
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (bleSerial.connected) {
      return await bleSerial.write(command, firmware: firmware);
    } else {
      return await nativeSerial.write(command, firmware: firmware);
    }
  }

  @override
  Future<void> registerCallback(dynamic callback) async {
    await bleSerial.registerCallback(callback);
    await nativeSerial.registerCallback(callback);
  }

  @override
  Future<void> open() async {
    if (bleSerial.connected) {
      await bleSerial.open();
    } else {
      await nativeSerial.open();
    }
  }

  @override
  dynamic get activeDevicePort => bleSerial.connected
      ? bleSerial.activeDevicePort
      : nativeSerial.activeDevicePort;

  @override
  ChameleonDevice get device =>
      bleSerial.connected ? bleSerial.device : nativeSerial.device;

  @override
  bool get connected => bleSerial.connected || nativeSerial.connected;

  @override
  String get portName =>
      bleSerial.connected ? bleSerial.portName : nativeSerial.portName;

  @override
  ConnectionType get connectionType => bleSerial.connected
      ? bleSerial.connectionType
      : nativeSerial.connectionType;

  @override
  bool get isOpen => bleSerial.isOpen || nativeSerial.isOpen;

  @override
  set isOpen(open) {
    bleSerial.isOpen = open;
    nativeSerial.isOpen = open;
  }

  @override
  bool get isDFU => bleSerial.isDFU || nativeSerial.isDFU;

  @override
  bool get pendingConnection =>
      bleSerial.pendingConnection || nativeSerial.pendingConnection;

  @override
  set pendingConnection(pendingConnection) {
    bleSerial.pendingConnection = pendingConnection;
    nativeSerial.pendingConnection = pendingConnection;
  }
}
