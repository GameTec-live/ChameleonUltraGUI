import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/chameleon_settings.dart';
import 'package:chameleonultragui/gui/page/home_overview.dart';
import 'package:chameleonultragui/helpers/battery_reading.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenSavedCards});

  final VoidCallback? onOpenSavedCards;

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  HomeViewData _data = HomeViewData.placeholder();
  bool _loading = true;
  bool _busy = false;
  bool _isLegacyFirmware = false;
  Timer? _batteryRetryTimer;
  final BatteryRetryPlan _batteryRetryPlan = BatteryRetryPlan();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_busy || !mounted) {
      return;
    }
    _busy = true;
    final appState = context.read<ChameleonGUIState>();
    final communicator = appState.communicator;
    final connector = appState.connector;

    List<SlotTypes> slotTypes = [];
    List<SlotNames> slotNames = List.generate(8, (_) => SlotNames());
    List<EnabledSlotInfo> enabledSlots = List.generate(
      8,
      (_) => EnabledSlotInfo(hf: true, lf: true),
    );
    var activeSlot = 0;
    int? batteryPercent;
    var firmware = '—';
    var commit = '';
    var readerMode = false;
    var capabilities = true;
    var slotsReady = false;

    if (communicator != null && connector != null) {
      try {
        slotTypes = await communicator.getSlotTagTypes();
        slotsReady = slotTypes.length >= 8;
      } catch (_) {}
      try {
        activeSlot = await communicator.getActiveSlot();
      } catch (_) {}
      try {
        slotNames = await communicator.getSlotTagNames();
      } catch (_) {}
      try {
        enabledSlots = await communicator.getEnabledSlots();
      } catch (_) {}
      batteryPercent = await _getBatteryPercent(communicator);
      try {
        final version = await _readFirmware(communicator, connector);
        firmware = version.$1;
        commit = version.$2;
      } catch (_) {}
      try {
        readerMode = await communicator.isReaderDeviceMode();
      } catch (_) {}
      try {
        capabilities = await _capabilitiesSupported(communicator, connector);
      } catch (_) {}
    }

    final cards = appState.sharedPreferencesProvider
        .getCards()
        .reversed
        .take(3)
        .toList();

    if (!mounted) {
      _busy = false;
      return;
    }

    setState(() {
      _data = HomeViewData(
        deviceName: connector == null
            ? '—'
            : 'Chameleon ${chameleonDeviceName(connector.device)}',
        device: connector?.device ?? ChameleonDevice.ultra,
        connectionType: connector?.connectionType ?? ConnectionType.none,
        portName: connector?.portName ?? '—',
        batteryPercent: batteryPercent,
        firmwareVersion: firmware,
        firmwareCommit: commit,
        updateAvailable: false,
        isReaderMode: readerMode,
        isDemo: connector?.portName == 'Demo',
        capabilitiesSupported: capabilities,
        activeSlot: activeSlot.clamp(0, 7),
        slotsReady: slotsReady,
        slotTypes: slotsReady ? slotTypes : _data.slotTypes,
        slotNames: slotNames,
        enabledSlots: enabledSlots,
        recentCards: cards,
      );
      _loading = false;
    });
    _busy = false;

    if (batteryPercent == null && communicator != null) {
      _batteryRetryPlan.reset();
      _scheduleNextBatteryRetry(communicator);
    }
    if (commit.isNotEmpty && mounted) {
      unawaited(_checkUpdate(commit));
    }
  }

  Future<int?> _getBatteryPercent(ChameleonCommunicator communicator) async {
    try {
      return batteryPercentFromCharge(await communicator.getBatteryCharge());
    } catch (_) {
      return null;
    }
  }

  void _scheduleNextBatteryRetry(ChameleonCommunicator communicator) {
    _batteryRetryTimer?.cancel();
    final delay = _batteryRetryPlan.next();
    if (delay == null) {
      return;
    }
    _batteryRetryTimer = Timer(delay, () {
      unawaited(_retryBattery(communicator));
    });
  }

  Future<void> _retryBattery(ChameleonCommunicator communicator) async {
    if (!mounted || _data.batteryPercent != null) {
      return;
    }
    final percent = await _getBatteryPercent(communicator);
    if (!mounted) {
      return;
    }
    if (percent == null) {
      _scheduleNextBatteryRetry(communicator);
      return;
    }
    setState(() {
      _data = _data.copyWith(batteryPercent: percent);
    });
  }

  Future<bool> _capabilitiesSupported(
    ChameleonCommunicator communicator,
    AbstractSerial connector,
  ) async {
    final List<int> capabilities;
    try {
      capabilities = await communicator.getDeviceCapabilities();
    } catch (_) {
      return true;
    }

    if (connector.device == ChameleonDevice.ultra) {
      return capabilities.contains(ChameleonCommand.mf0UlcAuth.value);
    }
    if (connector.device == ChameleonDevice.lite) {
      return capabilities.contains(ChameleonCommand.setIdteckEmulatorID.value);
    }
    return true;
  }

  Future<(String, String)> _readFirmware(
    ChameleonCommunicator communicator,
    AbstractSerial connector,
  ) async {
    final firmware = await communicator.getFirmwareVersion();
    _isLegacyFirmware = firmware.legacyProtocol;
    final version = numToVerCode(firmware.version);
    var commit = '';
    try {
      commit = await communicator.getGitCommitHash();
    } catch (_) {}

    if (commit.isEmpty) {
      commit = mounted
          ? AppLocalizations.of(context)!.outdated_fw
          : 'Outdated FW';
    }

    if (mounted && _isLegacyFirmware) {
      final localizations = AppLocalizations.of(context)!;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(localizations.outdated_protocol),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(localizations.outdated_protocol_description_1),
                  Text(localizations.outdated_protocol_description_2),
                  Text(localizations.outdated_protocol_description_3),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(localizations.update),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_flashFirmware());
                },
              ),
              TextButton(
                child: Text(localizations.skip),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      );
    }

    return ('$version ($commit)', commit);
  }

  Future<void> _checkUpdate(String currentCommit) async {
    final appState = context.read<ChameleonGUIState>();
    try {
      final latest = await latestAvailableCommit(appState.connector!.device);
      if (latest.isEmpty) {
        return;
      }
      var current = currentCommit;
      try {
        current = await resolveCommit(current);
      } catch (_) {}
      if (latest.startsWith(current) || mounted == false) {
        return;
      }
      setState(() {
        _data = HomeViewData(
          deviceName: _data.deviceName,
          device: _data.device,
          connectionType: _data.connectionType,
          portName: _data.portName,
          batteryPercent: _data.batteryPercent,
          firmwareVersion: _data.firmwareVersion,
          firmwareCommit: _data.firmwareCommit,
          updateAvailable: true,
          isReaderMode: _data.isReaderMode,
          isDemo: _data.isDemo,
          capabilitiesSupported: _data.capabilitiesSupported,
          activeSlot: _data.activeSlot,
          slotsReady: _data.slotsReady,
          slotTypes: _data.slotTypes,
          slotNames: _data.slotNames,
          enabledSlots: _data.enabledSlots,
          recentCards: _data.recentCards,
        );
      });
    } catch (_) {}
  }

  Future<void> _updateFirmware() async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    String latest;
    try {
      latest = await latestAvailableCommit(appState.connector!.device);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${localizations.update_error}: $e'),
          action: SnackBarAction(label: localizations.close, onPressed: () {}),
        ),
      );
      return;
    }

    var current = _data.firmwareCommit;
    try {
      current = await resolveCommit(current);
    } catch (_) {}
    if (latest.isEmpty) {
      return;
    }

    if (latest.startsWith(current)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            localizations.up_to_date(
              chameleonDeviceName(appState.connector!.device),
            ),
          ),
          action: SnackBarAction(label: localizations.close, onPressed: () {}),
        ),
      );
      return;
    }

    await _flashFirmware();
  }

  Future<void> _flashFirmware() async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          localizations.downloading_fw(
            chameleonDeviceName(appState.connector!.device),
          ),
        ),
        action: SnackBarAction(
          label: localizations.close,
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
    );
    try {
      await flashFirmware(appState, scaffoldMessenger: messenger);
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${localizations.update_error}: $e'),
          action: SnackBarAction(label: localizations.close, onPressed: () {}),
        ),
      );
    }
  }

  Future<void> _selectSlot(int index) async {
    final appState = context.read<ChameleonGUIState>();
    try {
      await appState.communicator!.activateSlot(index);
      if (!mounted) {
        return;
      }
      setState(() {
        _data = _data.copyWith(activeSlot: index);
      });
      appState.changesMade();
    } catch (_) {}
  }

  Future<void> _toggleReaderMode() async {
    final appState = context.read<ChameleonGUIState>();
    final next = !_data.isReaderMode;
    try {
      await appState.communicator!.setReaderDeviceMode(next);
      if (!mounted) {
        return;
      }
      setState(() {
        _data = _data.copyWith(isReaderMode: next);
      });
      appState.changesMade();
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    await showDialog<String>(
      context: context,
      builder: (_) => const ChameleonSettings(),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.copied)));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.home)),
      body: HomeOverview(
        data: _data,
        loading: _loading,
        onSelectSlot: _selectSlot,
        onOpenSavedCards: widget.onOpenSavedCards,
        onSettings: _openSettings,
        onDisconnect: () => appState.disconnect(manual: true),
        onToggleReaderMode: _toggleReaderMode,
        onUpdate: _updateFirmware,
        onCopy: _copy,
      ),
    );
  }
}
