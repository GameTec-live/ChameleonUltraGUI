import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/gui/component/connection_status.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({
    super.key,
    this.autoScanInterval = const Duration(seconds: 3),
  });

  final Duration autoScanInterval;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  Timer? _scanTimer;
  Object? _error;
  bool _scanInProgress = false;
  bool _connectionInProgress = false;
  bool _showedPermissionsSnackbar = false;
  dynamic _lastAutoConnectAttemptPort;

  ChameleonGUIState get _appState =>
      Provider.of<ChameleonGUIState>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanNow());
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  bool _shouldScan(ChameleonGUIState appState) {
    return mounted &&
        !_connectionInProgress &&
        !appState.connector!.connected &&
        !appState.connector!.pendingConnection;
  }

  List<Chameleon> _normalizeDevices(List<Chameleon> devices) {
    final output = <Chameleon>[];
    final seen = <String>{};

    for (final device in devices) {
      final key = '${device.port}|${device.type.name}|${device.dfu}';
      if (seen.add(key)) {
        output.add(device);
      }
    }

    return output;
  }

  dynamic _firstConnectablePort(List<Chameleon> devices) {
    for (final device in devices) {
      if (!device.dfu) {
        return device.port;
      }
    }
    return null;
  }

  void _scheduleNextScan() {
    _scanTimer?.cancel();

    if (!_shouldScan(_appState) ||
        !_appState.sharedPreferencesProvider.getAutoScanEnabled()) {
      return;
    }

    _scanTimer = Timer(widget.autoScanInterval, _scanNow);
  }

  void _showPermissionsWarningIfNeeded(List<Chameleon> devices) {
    final appState = _appState;
    if (appState.connector is! AndroidSerial) {
      _showedPermissionsSnackbar = false;
      return;
    }

    final androidSerial = appState.connector as AndroidSerial;
    final shouldShow = devices.isEmpty && !androidSerial.hasAllPermissions;
    if (!shouldShow) {
      _showedPermissionsSnackbar = false;
      return;
    }

    if (_showedPermissionsSnackbar) {
      return;
    }

    _showedPermissionsSnackbar = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final localizations = AppLocalizations.of(context)!;
      final snackBar = SnackBar(
        content: Text(localizations.android_ble_permissions_missing),
        action: SnackBarAction(label: localizations.close, onPressed: () {}),
      );

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(snackBar);
    });
  }

  Future<void> _scanNow() async {
    final appState = _appState;
    if (_scanInProgress || !_shouldScan(appState)) {
      return;
    }

    _scanTimer?.cancel();

    setState(() {
      _scanInProgress = true;
      _error = null;
    });

    try {
      final devices = _normalizeDevices(
        await appState.connector!.availableChameleons(false),
      );
      if (!mounted) {
        return;
      }

      appState.syncAutoReconnectSuppression(
        devices.map((device) => device.port),
      );

      final firstConnectablePort = _firstConnectablePort(devices);
      if (firstConnectablePort != _lastAutoConnectAttemptPort) {
        _lastAutoConnectAttemptPort = null;
      }

      _showPermissionsWarningIfNeeded(devices);
      await _maybeAutoConnect(devices);
    } catch (error) {
      await appState.connector!.performDisconnect();
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _scanInProgress = false;
        });
        _scheduleNextScan();
      }
    }
  }

  Future<void> _maybeAutoConnect(List<Chameleon> devices) async {
    final appState = _appState;
    if (!_shouldScan(appState)) {
      return;
    }
    // BLE has no manual device picker any more, so a found Chameleon is
    // always connected. USB keeps honouring the auto-connect preference.
    final autoConnect =
        appState.sharedPreferencesProvider.getAutoConnectFirstFoundDevice() ||
        devices.any((device) => device.type == ConnectionType.ble);
    if (!autoConnect) {
      return;
    }

    Chameleon? connectableDevice;
    for (final device in devices) {
      if (!device.dfu && !appState.isAutoReconnectSuppressed(device.port)) {
        connectableDevice = device;
        break;
      }
    }

    if (connectableDevice == null) {
      _lastAutoConnectAttemptPort = null;
      return;
    }

    if (_lastAutoConnectAttemptPort == connectableDevice.port) {
      return;
    }

    _lastAutoConnectAttemptPort = connectableDevice.port;
    await _connectToDevice(connectableDevice);
  }

  Future<void> _connectToDevice(Chameleon chameleonDevice) async {
    final appState = _appState;

    if (_connectionInProgress || chameleonDevice.dfu) {
      return;
    }

    _scanTimer?.cancel();
    if (mounted) {
      setState(() {
        _connectionInProgress = true;
      });
    }

    try {
      if (chameleonDevice.type == ConnectionType.ble) {
        appState.connector!.pendingConnection = true;
        appState.changesMade();
      }

      final connected = await appState.connector!.connectSpecificDevice(
        chameleonDevice.port,
      );
      if (connected) {
        appState.connector!.pendingConnection = false;
        appState.clearAutoReconnectSuppression(chameleonDevice.port);
        appState.communicator = ChameleonCommunicator(
          appState.log!,
          port: appState.connector,
        );
      } else {
        appState.connector!.pendingConnection = false;
        _lastAutoConnectAttemptPort = null;
      }

      appState.changesMade();
    } catch (error) {
      appState.connector!.pendingConnection = false;
      appState.changesMade();
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _connectionInProgress = false;
        });
      }

      if (!appState.connector!.connected) {
        _scheduleNextScan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(localizations.connect)),
        body: ErrorPage(errorMessage: _error.toString()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(localizations.connect)),
      body: ConnectionStatus(
        connected: appState.connector!.connected,
        connecting:
            appState.connector!.pendingConnection || _connectionInProgress,
      ),
    );
  }
}
