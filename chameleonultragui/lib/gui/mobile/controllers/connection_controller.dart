import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';

enum ConnectResult { connected, failed, dfu }

/// Scans for Chameleons and connects to one through the existing connector.
///
/// Scanning only runs while the connection page is visible and the app is in
/// the foreground. The transport and permission handling stay in the
/// connectors; this only drives them like the desktop connect page does.
class MobileConnectionController extends ChangeNotifier
    with WidgetsBindingObserver {
  MobileConnectionController(
    this.appState, {
    this.autoScanInterval = const Duration(seconds: 3),
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final ChameleonGUIState appState;
  final Duration autoScanInterval;

  List<Chameleon> devices = [];
  Object? error;
  bool initialScanCompleted = false;
  bool scanInProgress = false;
  bool connectionInProgress = false;

  /// True on Android when nothing was found and BLE permissions are missing.
  bool permissionsMissing = false;

  Timer? _scanTimer;
  bool _active = false;
  bool _paused = false;
  bool _disposed = false;
  dynamic _lastAutoConnectPort;

  AbstractSerial get _connector => appState.connector!;

  bool get manualConnectionSupported =>
      _connector.isManualConnectionSupported();

  /// Starts scanning; call when the page becomes visible.
  void start() {
    _active = true;
    scan();
  }

  /// Stops scanning; call when the page is hidden.
  void stop() {
    _active = false;
    _scanTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only reschedule: scanning right away would re-request the permissions
      // whose system dialog just paused/resumed the app, in an endless loop.
      _paused = false;
      _scheduleNextScan();
    } else if (state == AppLifecycleState.paused) {
      _paused = true;
      _scanTimer?.cancel();
    }
  }

  bool get _shouldScan =>
      !_disposed &&
      appState.connector != null &&
      _active &&
      !_paused &&
      !connectionInProgress &&
      !_connector.connected &&
      !_connector.pendingConnection;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  List<Chameleon> _normalize(List<Chameleon> found) {
    final output = <Chameleon>[];
    final seen = <String>{};

    for (final device in found) {
      final key = '${device.port}|${device.type.name}|${device.dfu}';
      if (seen.add(key)) {
        output.add(device);
      }
    }

    return output;
  }

  void _scheduleNextScan() {
    _scanTimer?.cancel();

    // Without permissions every rescan would show the system dialog again;
    // the user retries manually.
    if (!_shouldScan ||
        permissionsMissing ||
        !appState.sharedPreferencesProvider.getAutoScanEnabled()) {
      return;
    }

    _scanTimer = Timer(autoScanInterval, scan);
  }

  Future<void> scan() async {
    if (scanInProgress || !_shouldScan) {
      return;
    }

    _scanTimer?.cancel();
    scanInProgress = true;
    error = null;
    _notify();

    try {
      final found = _normalize(await _connector.availableChameleons(false));
      if (_disposed) {
        return;
      }

      appState.syncAutoReconnectSuppression(found.map((d) => d.port));

      devices = found;
      initialScanCompleted = true;
      permissionsMissing =
          _connector is AndroidSerial &&
          found.isEmpty &&
          !(_connector as AndroidSerial).hasAllPermissions;
      _notify();

      await _maybeAutoConnect(found);
    } catch (e) {
      await _connector.performDisconnect();
      error = e;
      initialScanCompleted = true;
    } finally {
      scanInProgress = false;
      _notify();
      _scheduleNextScan();
    }
  }

  Future<void> _maybeAutoConnect(List<Chameleon> found) async {
    if (!_shouldScan ||
        !appState.sharedPreferencesProvider.getAutoConnectFirstFoundDevice()) {
      return;
    }

    Chameleon? candidate;
    for (final device in found) {
      if (!device.dfu && !appState.isAutoReconnectSuppressed(device.port)) {
        candidate = device;
        break;
      }
    }

    if (candidate == null) {
      _lastAutoConnectPort = null;
      return;
    }

    if (_lastAutoConnectPort == candidate.port) {
      return;
    }

    _lastAutoConnectPort = candidate.port;
    await connect(candidate, fromAutoConnect: true);
  }

  /// Connects to [device]. DFU devices are not connected; the caller offers to
  /// flash them instead.
  Future<ConnectResult> connect(
    Chameleon device, {
    bool fromAutoConnect = false,
  }) async {
    if (connectionInProgress) {
      return ConnectResult.failed;
    }

    if (device.dfu) {
      return ConnectResult.dfu;
    }

    _scanTimer?.cancel();
    connectionInProgress = true;
    error = null;
    _notify();

    var result = ConnectResult.failed;
    try {
      if (device.type == ConnectionType.ble) {
        _connector.pendingConnection = true;
        appState.changesMade();
      }

      final connected = await _connector.connectSpecificDevice(device.port);
      _connector.pendingConnection = false;
      if (connected) {
        appState.clearAutoReconnectSuppression(device.port);
        appState.communicator = ChameleonCommunicator(
          appState.log!,
          port: _connector,
        );
        result = ConnectResult.connected;
      }

      appState.changesMade();
    } catch (e) {
      _connector.pendingConnection = false;
      appState.changesMade();
      error = e;
    } finally {
      connectionInProgress = false;
      _notify();

      if (!_connector.connected) {
        _scheduleNextScan();
      }
    }

    return result;
  }

  /// Flashes the latest firmware onto a device that is already in DFU mode.
  Future<void> flashDfuDevice(
    Chameleon device,
    ScaffoldMessengerState scaffoldMessenger,
  ) async {
    try {
      await flashFirmware(
        appState,
        scaffoldMessenger: scaffoldMessenger,
        device: device.device,
        enterDFU: false,
      );
    } finally {
      appState.changesMade();
      scan();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
