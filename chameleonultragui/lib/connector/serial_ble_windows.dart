import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/ble_trace.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/ble_pairing.dart';
import 'package:chameleonultragui/helpers/ble_status.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Guid _nrfService = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
final Guid _uartRx = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
final Guid _uartTx = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

const List<int> _uartHandshake = [
  0x11,
  0xef,
  0x03,
  0xfb,
  0x00,
  0x00,
  0x00,
  0x00,
  0x02,
  0x00,
];

/// Windows BLE connector using the WinRT implementation of flutter_blue_plus.
///
/// `CHAMELEON_BLE_MODE=legacy` keeps the previous connection flow for A/B
/// measurements; the default (`robust`) adds scan cancellation, connection
/// mutex, retries with backoff and a fresh GATT discovery per attempt.
class WindowsBLESerial extends AbstractSerial {
  final Map<String, Chameleon> chameleonMap = {};

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _stateSubscription;

  bool inSearch = false;
  bool _connecting = false;
  bool _reconnecting = false;
  DateTime? _lastScanAt;
  List<Chameleon> _lastScanResult = [];
  String? _activePort;
  Chameleon? _activeInfo;

  bool Function()? isOtherBusy;
  bool _watchEnabled = false;
  bool _watching = false;
  bool _usbSuspended = false;
  bool _directRunning = false;
  Completer<void>? _activeWatch;

  WindowsBLESerial({required super.log}) {
    BleTrace.setMode(mode);
  }

  String get mode => Platform.environment['CHAMELEON_BLE_MODE'] ?? 'robust';

  Duration get _scanWindow => mode == 'legacy'
      ? const Duration(milliseconds: 2000)
      : const Duration(milliseconds: 1500);

  int get _scanCacheSeconds => mode == 'legacy' ? 8 : 4;

  void _trace(String stage, String message) {
    BleTrace.instance.log(stage, message);
  }

  bool _isChameleonName(String name) {
    return name.startsWith('ChameleonUltra') ||
        name.startsWith('ChameleonLite');
  }

  bool _isChameleonResult(ScanResult result) {
    var name = result.advertisementData.advName;
    if (name.isEmpty) {
      name = result.device.platformName;
    }
    if (_isChameleonName(name)) {
      return true;
    }
    return result.advertisementData.serviceUuids.contains(_nrfService);
  }

  @override
  bool isManualConnectionSupported() {
    return false;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    // BLE DFU is not implemented; USB remains available for flashing.
    if (onlyDFU || connected || inSearch) {
      return [];
    }

    final now = DateTime.now();
    if (_lastScanAt != null &&
        now.difference(_lastScanAt!).inSeconds < _scanCacheSeconds) {
      _trace('scan.cached', 'count=${_lastScanResult.length}');
      return List<Chameleon>.from(_lastScanResult);
    }

    inSearch = true;
    final stopwatch = Stopwatch()..start();
    final found = <String, Chameleon>{};
    _trace('scan.start', 'window_ms=${_scanWindow.inMilliseconds}');

    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        var name = result.advertisementData.advName;
        if (name.isEmpty) {
          name = result.device.platformName;
        }
        if (!_isChameleonResult(result)) {
          continue;
        }
        final port = result.device.remoteId.str;
        found[port] = Chameleon(
          port: port,
          device: name.startsWith('ChameleonLite')
              ? ChameleonDevice.lite
              : ChameleonDevice.ultra,
          type: ConnectionType.ble,
          dfu: false,
        );
      }
    });

    try {
      await _stopScan();
      await FlutterBluePlus.startScan(timeout: _scanWindow);
      await Future<void>.delayed(
        _scanWindow + const Duration(milliseconds: 200),
      );
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _trace(
        'scan.error',
        'ms=${stopwatch.elapsedMilliseconds} error=${e.runtimeType}: $e',
      );
    } finally {
      await subscription.cancel();
      inSearch = false;
    }

    _lastScanAt = DateTime.now();
    _lastScanResult = found.values.toList();
    for (final entry in found.entries) {
      chameleonMap[entry.key] = entry.value;
    }
    _trace(
      'scan.done',
      'ms=${stopwatch.elapsedMilliseconds} count=${_lastScanResult.length} ports=${_lastScanResult.map((d) => d.port).join(",")}',
    );
    return _lastScanResult;
  }

  Future<List<Chameleon>> scanNow() async {
    _lastScanAt = null;
    return availableChameleons(false);
  }

  /// Continuously watches BLE advertisements while the app is open.
  ///
  /// Runs independently of the visible page. When a Chameleon advertisement is
  /// seen it stops scanning, connects, and resumes watching after a failure or
  /// disconnect. `isOtherBusy` lets the USB side win when it connects first.
  bool get connectingNow => _connecting || _reconnecting || pendingConnection;

  Future<void> suspendForUsb() async {
    if (_usbSuspended) {
      return;
    }
    _usbSuspended = true;
    _trace('usb.priority', 'suspending BLE for USB');
    await _stopScan();
    pendingConnection = false;
    if (!connected) {
      await _cleanupForConnect();
    }
    BleStatus.set(BlePhase.waiting);
    notifyConnectionStateChanged();
  }

  void resumeAfterUsb() {
    if (!_usbSuspended) {
      return;
    }
    _usbSuspended = false;
    _trace('usb.priority', 'resuming BLE after USB removal');
    startWatching();
  }

  void startWatching() {
    if (_watchEnabled || _usbSuspended) {
      return;
    }
    _watchEnabled = true;
    unawaited(_watchLoop());
    unawaited(_startDirectConnect());
  }

  Future<void> _watchLoop() async {
    if (_watching) {
      return;
    }
    _watching = true;
    _trace('watch.loop', 'started');
    while (_watchEnabled) {
      if (connected ||
          _usbSuspended ||
          _reconnecting ||
          (isOtherBusy?.call() ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      await _watchOnce();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    _watching = false;
    _trace('watch.loop', 'stopped');
  }

  Future<void> _watchOnce() async {
    final completer = Completer<void>();
    _activeWatch = completer;
    StreamSubscription<List<ScanResult>>? subscription;
    var handled = false;
    DateTime? firstAdvertisement;

    try {
      subscription = FlutterBluePlus.onScanResults.listen((results) {
        if (handled) {
          return;
        }
        for (final result in results) {
          if (!_isChameleonResult(result)) {
            continue;
          }
          if (connected) {
            handled = true;
            unawaited(FlutterBluePlus.stopScan());
            if (!completer.isCompleted) {
              completer.complete();
            }
            return;
          }
          // A direct attempt already owns the radio; keep scanning so the
          // advertisement that just arrived is still available if it fails.
          if (_connecting || _reconnecting) {
            continue;
          }
          handled = true;
          firstAdvertisement ??= DateTime.now();
          var name = result.advertisementData.advName;
          if (name.isEmpty) {
            name = result.device.platformName;
          }
          final port = result.device.remoteId.str;
          final info = Chameleon(
            port: port,
            device: name.startsWith('ChameleonLite')
                ? ChameleonDevice.lite
                : ChameleonDevice.ultra,
            type: ConnectionType.ble,
            dfu: false,
          );
          chameleonMap[port] = info;
          BleStatus.set(BlePhase.connecting);
          _trace('watch.found', 'port=$port name=$name');

          unawaited(() async {
            final stopWatch = Stopwatch()..start();
            try {
              await FlutterBluePlus.stopScan();
            } catch (_) {}
            final stopScanMs = stopWatch.elapsedMilliseconds;
            await subscription?.cancel();
            final ok = await connectSpecificDevice(port);
            final elapsed = DateTime.now()
                .difference(firstAdvertisement!)
                .inMilliseconds;
            if (ok) {
              _trace(
                'watch.timing',
                'first_adv_to_handshake_ms=$elapsed stop_scan_ms=$stopScanMs port=$port',
              );
              _trace('watch.connected', 'port=$port');
            } else {
              _trace(
                'watch.failed',
                'ms=$elapsed stop_scan_ms=$stopScanMs port=$port',
              );
              BleStatus.set(BlePhase.failedRetrying);
              unawaited(
                Future<void>.delayed(const Duration(milliseconds: 1200), () {
                  if (!connected) {
                    BleStatus.set(BlePhase.waiting);
                  }
                }),
              );
            }
            if (!completer.isCompleted) {
              completer.complete();
            }
          }());
          return;
        }
      });

      _trace('watch.scan.start', '');
      await FlutterBluePlus.startScan(timeout: const Duration(minutes: 5));
      _trace(
        'watch.scan.started',
        'isScanning=${FlutterBluePlus.isScanningNow}',
      );
      await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {},
      );
    } catch (e) {
      _trace('watch.error', '${e.runtimeType}: $e');
      await Future<void>.delayed(const Duration(seconds: 2));
    } finally {
      if (identical(_activeWatch, completer)) {
        _activeWatch = null;
      }
      await subscription?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      _trace('watch.scan.stop', '');
    }
  }

  Future<void> _startDirectConnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ble_last_device');
      if (raw == null || raw.isEmpty) {
        return;
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final address = data['address'] as String?;
      if (address == null || address.isEmpty) {
        return;
      }
      final info = Chameleon(
        port: address,
        device: data['device'] == 'lite'
            ? ChameleonDevice.lite
            : ChameleonDevice.ultra,
        type: ConnectionType.ble,
        dfu: false,
      );
      chameleonMap[address] = info;
      unawaited(_directLoop(address, info));
    } catch (_) {}
  }

  Future<void> _directLoop(String address, Chameleon info) async {
    if (_directRunning) {
      return;
    }
    _directRunning = true;
    _trace('direct.loop', 'address=$address');
    while (_watchEnabled) {
      if (connected ||
          _usbSuspended ||
          _connecting ||
          _reconnecting ||
          (isOtherBusy?.call() ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }

      _connecting = true;
      var stage = 'cleanup';
      final total = Stopwatch()..start();
      try {
        await _cleanupDirect();
        _trace('direct.attempt', 'address=$address');

        stage = 'connect';
        final device = BluetoothDevice.fromId(address);
        _device = device;
        _listenState(device, legacy: false);
        final connectWatch = Stopwatch()..start();
        await device
            .connect(
              license: License.nonprofit,
              timeout: const Duration(seconds: 3),
            )
            .timeout(const Duration(seconds: 4));
        _trace('direct.connect.ok', 'ms=${connectWatch.elapsedMilliseconds}');
        if (_usbSuspended) {
          throw 'usb-priority';
        }
        // Only a real link turns the page into "connecting"; retrying an
        // absent remembered address must keep showing "waiting".
        pendingConnection = true;
        BleStatus.set(BlePhase.connecting);
        notifyConnectionStateChanged();

        stage = 'discover';
        final discoverWatch = Stopwatch()..start();
        final uart = await _discover(device, retries: 1);
        _trace('direct.discover.ok', 'ms=${discoverWatch.elapsedMilliseconds}');

        stage = 'subscribe';
        final subscribeWatch = Stopwatch()..start();
        await _subscribeService(uart, retries: 1);
        _trace(
          'direct.subscribe.ok',
          'ms=${subscribeWatch.elapsedMilliseconds}',
        );

        stage = 'handshake';
        final handshakeWatch = Stopwatch()..start();
        await _handshake(_rx!, retries: 1);
        _trace(
          'direct.handshake.ok',
          'ms=${handshakeWatch.elapsedMilliseconds}',
        );

        _setConnected(address, info, notify: true);
        _trace('direct.ok', 'total_ms=${total.elapsedMilliseconds}');
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
        final watch = _activeWatch;
        if (watch != null && !watch.isCompleted) {
          watch.complete();
        }
        break;
      } catch (e) {
        _trace(
          'direct.fail',
          'stage=$stage ms=${total.elapsedMilliseconds} error=${e.runtimeType}: $e',
        );
        await _cleanupDirect();
        pendingConnection = false;
        BleStatus.set(BlePhase.failedRetrying);
        notifyConnectionStateChanged();
      } finally {
        _connecting = false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!connected) {
        BleStatus.set(BlePhase.waiting);
      }
    }
    _directRunning = false;
    _trace('direct.loop', 'stopped');
  }

  Future<void> _cleanupDirect() async {
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    final device = _device;
    _device = null;
    _rx = null;
    if (device != null) {
      try {
        await device.disconnect().timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
  }

  Future<void> _saveLastDevice(String address, Chameleon info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ble_last_device',
        jsonEncode({
          'address': address,
          'device': info.device == ChameleonDevice.lite ? 'lite' : 'ultra',
        }),
      );
    } catch (_) {}
  }

  Future<void> _stopScan() async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan().timeout(const Duration(seconds: 2));
        _trace('scan.stop', 'ok');
      }
    } catch (e) {
      _trace('scan.stop', 'error=${e.runtimeType}: $e');
    }
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    final info = chameleonMap[devicePort] ?? _activeInfo;
    if (info == null) {
      _trace('connect.no_info', 'port=$devicePort');
      return false;
    }
    if (mode == 'legacy') {
      return _connectLegacy(devicePort, info);
    }
    return _connectRobust(devicePort, info);
  }

  Future<bool> _connectLegacy(dynamic devicePort, Chameleon info) async {
    final stopwatch = Stopwatch()..start();
    var stage = 'disconnect';
    _trace('legacy.start', 'port=$devicePort');
    await performDisconnect();
    pendingConnection = true;

    try {
      final bluetoothDevice = BluetoothDevice.fromId(devicePort.toString());
      _device = bluetoothDevice;
      _listenState(bluetoothDevice, legacy: true);

      stage = 'connect';
      await bluetoothDevice.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );

      stage = 'discover';
      final uart = await _discover(bluetoothDevice, retries: 1);

      stage = 'subscribe';
      await _subscribeService(uart, retries: 1);

      stage = 'handshake';
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _handshake(_rx!, retries: 1);

      _setConnected(devicePort, info, notify: true);
      _trace('legacy.ok', 'ms=${stopwatch.elapsedMilliseconds}');
      return true;
    } catch (e) {
      _trace(
        'legacy.fail',
        'stage=$stage ms=${stopwatch.elapsedMilliseconds} error=${e.runtimeType}: $e',
      );
      await performDisconnect();
      return false;
    }
  }

  Future<bool> _connectRobust(dynamic devicePort, Chameleon info) async {
    if (_usbSuspended) {
      return false;
    }
    if (_connecting || _reconnecting) {
      _trace(
        'connect.busy',
        'connecting=$_connecting reconnecting=$_reconnecting',
      );
      return false;
    }
    _connecting = true;
    pendingConnection = true;
    notifyConnectionStateChanged();
    final stopwatch = Stopwatch()..start();
    try {
      final ok = await _robustAttempts(
        devicePort.toString(),
        info,
        reconnect: false,
      );
      if (!ok) {
        pendingConnection = false;
        await performDisconnect();
      }
      _trace('robust.done', 'ok=$ok total_ms=${stopwatch.elapsedMilliseconds}');
      return ok;
    } finally {
      _connecting = false;
    }
  }

  Future<bool> _robustAttempts(
    String port,
    Chameleon info, {
    required bool reconnect,
  }) async {
    const backoff = [0, 250, 600, 1200];
    final total = Stopwatch()..start();

    for (var i = 0; i < backoff.length; i++) {
      if (backoff[i] > 0) {
        await Future<void>.delayed(Duration(milliseconds: backoff[i]));
      }
      final attempt = i + 1;
      var stage = 'cleanup';
      final stopwatch = Stopwatch()..start();
      _trace(
        'attempt.start',
        'attempt=$attempt port=$port reconnect=$reconnect',
      );

      if (_usbSuspended) {
        return false;
      }
      try {
        await _cleanupForConnect();
        stage = 'stop_scan';
        await _stopScan();

        stage = 'connect';
        final bluetoothDevice = BluetoothDevice.fromId(port);
        _device = bluetoothDevice;
        _listenState(bluetoothDevice, legacy: false);
        final connectWatch = Stopwatch()..start();
        await bluetoothDevice
            .connect(
              license: License.nonprofit,
              timeout: const Duration(seconds: 8),
            )
            .timeout(const Duration(seconds: 10));
        _trace(
          'connect.ok',
          'attempt=$attempt ms=${connectWatch.elapsedMilliseconds}',
        );

        stage = 'discover';
        final uart = await _discover(bluetoothDevice, retries: 2);

        stage = 'subscribe';
        await _subscribeService(uart, retries: 2);

        stage = 'handshake';
        await _handshake(_rx!, retries: 2);

        _setConnected(port, info, notify: !reconnect);
        _trace(
          'attempt.ok',
          'attempt=$attempt total_ms=${stopwatch.elapsedMilliseconds}',
        );
        _trace(
          'robust.ok',
          'attempts=$attempt total_ms=${total.elapsedMilliseconds}',
        );
        return true;
      } catch (e) {
        _trace(
          'attempt.fail',
          'attempt=$attempt stage=$stage ms=${stopwatch.elapsedMilliseconds} error=${e.runtimeType}: $e',
        );
        await _cleanupForConnect();
      }
    }

    _trace(
      'robust.failed',
      'attempts=${backoff.length} total_ms=${total.elapsedMilliseconds}',
    );
    return false;
  }

  Future<void> _cleanupForConnect() async {
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    final device = _device;
    _device = null;
    _rx = null;
    if (device != null) {
      try {
        await device.disconnect().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    await _stopScan();
  }

  Future<BluetoothService> _discover(
    BluetoothDevice device, {
    required int retries,
  }) async {
    Object? lastError;
    for (var i = 0; i < retries; i++) {
      final stopwatch = Stopwatch()..start();
      try {
        final services = await device.discoverServices().timeout(
          const Duration(seconds: 6),
        );
        for (final service in services) {
          if (service.uuid == _nrfService) {
            _trace(
              'discover.ok',
              'attempt=${i + 1} ms=${stopwatch.elapsedMilliseconds} services=${services.length}',
            );
            return service;
          }
        }
        lastError = 'UART service missing (services=${services.length})';
        _trace(
          'discover.miss',
          'attempt=${i + 1} ms=${stopwatch.elapsedMilliseconds} services=${services.length}',
        );
      } catch (e) {
        lastError = e;
        _trace(
          'discover.error',
          'attempt=${i + 1} ms=${stopwatch.elapsedMilliseconds} error=${e.runtimeType}: $e',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw 'discover failed: $lastError';
  }

  Future<void> _subscribeService(
    BluetoothService uart, {
    required int retries,
  }) async {
    BluetoothCharacteristic? rx;
    BluetoothCharacteristic? tx;
    for (final characteristic in uart.characteristics) {
      if (characteristic.uuid == _uartRx) {
        rx = characteristic;
      } else if (characteristic.uuid == _uartTx) {
        tx = characteristic;
      }
    }
    if (rx == null || tx == null) {
      throw "Nordic UART characteristics not found";
    }

    await _valueSubscription?.cancel();
    _valueSubscription = null;

    Object? lastError;
    var attempt = 0;
    var pairingTried = false;
    while (attempt < retries) {
      final stopwatch = Stopwatch()..start();
      try {
        await tx.setNotifyValue(true).timeout(const Duration(seconds: 4));
        _valueSubscription = tx.onValueReceived.listen(
          (data) {
            if (messageCallback != null) {
              try {
                messageCallback(Uint8List.fromList(data));
              } catch (_) {
                log.w("Received unexpected data: ${data.length} bytes");
              }
            }
          },
          onError: (Object error) {
            _trace('notify.error', '${error.runtimeType}: $error');
          },
        );
        _rx = rx;
        _trace(
          'subscribe.ok',
          'attempt=${attempt + 1} ms=${stopwatch.elapsedMilliseconds}',
        );
        return;
      } catch (e) {
        lastError = e;
        _trace(
          'subscribe.error',
          'attempt=${attempt + 1} ms=${stopwatch.elapsedMilliseconds} error=${e.runtimeType}: $e',
        );

        // The CCCD is protected by the device's pairing setting. Pair here,
        // before giving up, otherwise the PIN dialog would only appear after
        // a handshake that can never happen.
        final port = _device?.remoteId.str;
        if (!pairingTried &&
            port != null &&
            BlePairingService.instance.isAuthFailure(e)) {
          pairingTried = true;
          final paired = await BlePairingService.instance.ensurePair(port);
          if (paired) {
            continue;
          }
        }

        attempt++;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw 'subscribe failed: $lastError';
  }

  Future<void> _handshake(
    BluetoothCharacteristic rx, {
    required int retries,
  }) async {
    Object? lastError;
    for (var i = 0; i < retries; i++) {
      final stopwatch = Stopwatch()..start();
      try {
        await rx
            .write(_uartHandshake, withoutResponse: false)
            .timeout(const Duration(seconds: 4));
        _trace(
          'handshake.ok',
          'attempt=${i + 1} ms=${stopwatch.elapsedMilliseconds}',
        );
        return;
      } catch (e) {
        lastError = e;
        _trace(
          'handshake.error',
          'attempt=${i + 1} ms=${stopwatch.elapsedMilliseconds} error=${e.runtimeType}: $e',
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw 'handshake failed: $lastError';
  }

  void _setConnected(dynamic port, Chameleon info, {required bool notify}) {
    connected = true;
    pendingConnection = false;
    portName = port.toString();
    device = info.device;
    activeDevicePort = port;
    connectionType = ConnectionType.ble;
    isDFU = false;
    _activePort = port.toString();
    _activeInfo = info;
    BleStatus.set(BlePhase.waiting);
    unawaited(() async {
      await _saveLastDevice(port.toString(), info);
      if (!_directRunning && _watchEnabled) {
        await _startDirectConnect();
      }
    }());
    if (notify) {
      notifyConnectionStateChanged();
    }
  }

  void _listenState(BluetoothDevice bluetoothDevice, {required bool legacy}) {
    unawaited(_stateSubscription?.cancel());
    _stateSubscription = bluetoothDevice.connectionState.listen((state) {
      _trace('state', '${state.name} connected=$connected');
      if (state == BluetoothConnectionState.disconnected &&
          connected &&
          !_connecting &&
          !_reconnecting) {
        if (legacy) {
          unawaited(_reconnectLegacy());
        } else {
          unawaited(_reconnectRobust());
        }
      }
    });
  }

  Future<void> _reconnectLegacy() async {
    final port = _activePort;
    final info = _activeInfo;
    if (_reconnecting || _connecting || port == null || info == null) {
      return;
    }
    _reconnecting = true;
    final stopwatch = Stopwatch()..start();
    _trace('reconnect.start', 'port=$port mode=legacy');
    try {
      for (var i = 0; i < 5; i++) {
        try {
          final bluetoothDevice = _device;
          if (bluetoothDevice == null) {
            throw 'no device object';
          }
          await bluetoothDevice.connect(
            license: License.nonprofit,
            timeout: const Duration(seconds: 2),
          );
          final uart = await _discover(bluetoothDevice, retries: 1);
          await _subscribeService(uart, retries: 1);
          await _handshake(_rx!, retries: 1);
          _trace(
            'reconnect.ok',
            'attempt=${i + 1} ms=${stopwatch.elapsedMilliseconds}',
          );
          return;
        } catch (e) {
          _trace(
            'reconnect.retry',
            'attempt=${i + 1} error=${e.runtimeType}: $e',
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      _trace('reconnect.failed', 'ms=${stopwatch.elapsedMilliseconds}');
      await performDisconnect();
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _reconnectRobust() async {
    final port = _activePort;
    final info = _activeInfo;
    if (_reconnecting || _connecting || port == null || info == null) {
      return;
    }
    _reconnecting = true;
    final stopwatch = Stopwatch()..start();
    _trace('reconnect.start', 'port=$port mode=robust');
    try {
      final ok = await _robustAttempts(port, info, reconnect: true);
      if (!ok) {
        _trace('reconnect.failed', 'ms=${stopwatch.elapsedMilliseconds}');
        await performDisconnect();
      } else {
        _trace('reconnect.ok', 'ms=${stopwatch.elapsedMilliseconds}');
      }
    } finally {
      _reconnecting = false;
    }
  }

  @override
  Future<bool> performDisconnect() async {
    final hadState = hasConnectionState || _device != null;
    _trace('disconnect', 'had=$hadState port=$_activePort');
    final device = _device;
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    _device = null;
    _rx = null;
    _activePort = null;
    _activeInfo = null;
    resetConnectionState();
    BleStatus.set(BlePhase.waiting);
    try {
      await device?.disconnect().timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (hadState) {
      notifyConnectionStateChanged();
    }
    return hadState;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final rx = _rx;
    if (rx == null) {
      throw "BLE not connected";
    }
    try {
      await rx.write(command, withoutResponse: firmware);
      return true;
    } catch (e) {
      _trace('write.error', '${e.runtimeType}: $e');
      rethrow;
    }
  }
}
