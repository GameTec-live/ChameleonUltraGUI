import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/dialogs/manual_connect.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
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
  List<Chameleon> _devices = [];
  Timer? _scanTimer;
  Object? _error;
  bool _isLoading = true;
  bool _initialScanCompleted = false;
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
        action: SnackBarAction(
          label: localizations.close,
          onPressed: () {},
        ),
      );

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(snackBar);
    });
  }

  Future<void> _scanNow({bool manual = false}) async {
    final appState = _appState;
    if (_scanInProgress || !_shouldScan(appState)) {
      return;
    }

    _scanTimer?.cancel();

    setState(() {
      _scanInProgress = true;
      _error = null;
      if (!_initialScanCompleted || manual) {
        _isLoading = true;
      }
    });

    try {
      final devices = _normalizeDevices(
          await appState.connector!.availableChameleons(false));
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

      setState(() {
        _devices = devices;
        _isLoading = false;
        _initialScanCompleted = true;
      });

      _showPermissionsWarningIfNeeded(devices);
      await _maybeAutoConnect(devices);
    } catch (error) {
      await appState.connector!.performDisconnect();
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
        _isLoading = false;
        _initialScanCompleted = true;
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
    if (!_shouldScan(appState) ||
        !appState.sharedPreferencesProvider.getAutoConnectFirstFoundDevice()) {
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
    await _connectToDevice(connectableDevice, fromAutoConnect: true);
  }

  Future<void> _connectToDevice(
    Chameleon chameleonDevice, {
    bool fromAutoConnect = false,
  }) async {
    final appState = _appState;

    if (_connectionInProgress) {
      return;
    }

    if (chameleonDevice.dfu) {
      if (!fromAutoConnect) {
        _showDfuDialog(chameleonDevice);
      }
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

      final connected =
          await appState.connector!.connectSpecificDevice(chameleonDevice.port);
      if (connected) {
        appState.connector!.pendingConnection = false;
        appState.clearAutoReconnectSuppression(chameleonDevice.port);
        appState.communicator =
            ChameleonCommunicator(appState.log!, port: appState.connector);
      } else {
        appState.connector!.pendingConnection = false;
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

  void _showDfuDialog(Chameleon chameleonDevice) {
    final appState = _appState;
    final localizations = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(localizations.chameleon_is_dfu),
        content: Text(localizations.firmware_is_corrupted),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, localizations.cancel),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext, localizations.flash);
              appState.changesMade();

              scaffoldMessenger.hideCurrentSnackBar();
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(
                    localizations.downloading_fw(
                      chameleonDeviceName(chameleonDevice.device),
                    ),
                  ),
                  action: SnackBarAction(
                    label: localizations.close,
                    onPressed: scaffoldMessenger.hideCurrentSnackBar,
                  ),
                ),
              );

              await flashFirmware(
                appState,
                scaffoldMessenger: scaffoldMessenger,
                device: chameleonDevice.device,
                enterDFU: false,
              );

              appState.changesMade();
              if (mounted) {
                _scanNow();
              }
            },
            child: Text(localizations.flash),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceGrid(AppLocalizations localizations) {
    return GridView(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      scrollDirection: Axis.vertical,
      children: [
        ..._devices.map<Widget>((chameleonDevice) {
          return ElevatedButton(
            onPressed: () => _connectToDevice(chameleonDevice),
            style: ButtonStyle(
              shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18.0),
                ),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: FittedBox(
                    alignment: Alignment.centerRight,
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            chameleonDevice.type == ConnectionType.ble
                                ? const Icon(Icons.bluetooth)
                                : const Icon(Icons.usb),
                            Text(chameleonDevice.port ?? ""),
                            if (chameleonDevice.dfu) Text(localizations.dfu),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
                FittedBox(
                  alignment: Alignment.topRight,
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(
                        "Chameleon ${chameleonDeviceName(chameleonDevice.device)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Image.asset(
                    chameleonDevice.device == ChameleonDevice.ultra
                        ? 'assets/black-ultra-standing-front.webp'
                        : 'assets/black-lite-standing-front.webp',
                    fit: BoxFit.fitHeight,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(localizations.connect),
        ),
        body: ErrorPage(errorMessage: _error.toString()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.connect),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => _scanNow(manual: true),
                icon: const Icon(Icons.refresh),
              ),
            ),
            Expanded(
              child: (_isLoading && !_initialScanCompleted)
                  ? const Center(child: CircularProgressIndicator())
                  : _buildDeviceGrid(localizations),
            ),
            if (appState.connector!.isManualConnectionSupported())
              Align(
                alignment: Alignment.bottomRight,
                child: Row(
                  children: [
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: IconButton(
                        onPressed: () => showDialog<String>(
                          context: context,
                          builder: (BuildContext dialogContext) =>
                              const ManualConnect(),
                        ),
                        icon: const Icon(Icons.add),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
