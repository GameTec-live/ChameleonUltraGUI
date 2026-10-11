import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/menu/dialogs/manual_connect.dart';
import 'package:chameleonultragui/gui/mobile/controllers/connection_controller.dart';
import 'package:chameleonultragui/gui/mobile/widgets/helpers.dart';
import 'package:chameleonultragui/gui/mobile/widgets/message_view.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Compact list of Chameleons that can be connected to.
class MobileConnectionPage extends StatefulWidget {
  const MobileConnectionPage({
    super.key,
    this.autoScanInterval = const Duration(seconds: 3),
  });

  final Duration autoScanInterval;

  @override
  State<MobileConnectionPage> createState() => _MobileConnectionPageState();
}

class _MobileConnectionPageState extends State<MobileConnectionPage> {
  late final MobileConnectionController _controller;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller = MobileConnectionController(
      context.read<ChameleonGUIState>(),
      autoScanInterval: widget.autoScanInterval,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible) {
        _controller.start();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // The shell keeps tabs alive but disables tickers of hidden ones, so this
    // pauses scanning while another tab is shown.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible != _visible) {
      _visible = visible;
      if (visible) {
        _controller.start();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect(Chameleon device) async {
    final localizations = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final result = await _controller.connect(device);
    if (!mounted) {
      return;
    }

    if (result == ConnectResult.dfu) {
      await _showDfuDialog(device);
    } else if (result == ConnectResult.failed && _controller.error != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${localizations.error}: ${_controller.error}'),
          action: SnackBarAction(
            label: localizations.close,
            onPressed: messenger.hideCurrentSnackBar,
          ),
        ),
      );
    }
  }

  Future<void> _showDfuDialog(Chameleon device) async {
    final localizations = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final flash = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.chameleon_is_dfu),
        content: Text(localizations.firmware_is_corrupted),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.flash),
          ),
        ],
      ),
    );

    if (flash != true) {
      return;
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          localizations.downloading_fw(chameleonDeviceName(device.device)),
        ),
        action: SnackBarAction(
          label: localizations.close,
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
    );

    try {
      await _controller.flashDfuDevice(device, messenger);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${localizations.update_error}: $e'),
          action: SnackBarAction(
            label: localizations.close,
            onPressed: messenger.hideCurrentSnackBar,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final busy =
            _controller.scanInProgress || _controller.connectionInProgress;

        return Scaffold(
          appBar: AppBar(
            title: Text(localizations.connect),
            actions: [
              if (_controller.manualConnectionSupported)
                IconButton(
                  tooltip: localizations.connect_manually,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const ManualConnect(),
                  ),
                  icon: const Icon(Icons.add),
                ),
              IconButton(
                tooltip: localizations.scan_again,
                onPressed: busy ? null : _controller.scan,
                icon: const Icon(Icons.refresh),
              ),
            ],
            bottom: busy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(4),
                    child: LinearProgressIndicator(),
                  )
                : null,
          ),
          body: SafeArea(top: false, child: _buildBody(context, localizations)),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations localizations) {
    if (_controller.error != null && _controller.devices.isEmpty) {
      return MessageView(
        icon: Icons.error_outline,
        title: localizations.error,
        message: _controller.error.toString(),
        actions: [
          FilledButton(
            onPressed: _controller.scan,
            child: Text(localizations.retry),
          ),
        ],
      );
    }

    if (!_controller.initialScanCompleted) {
      return MessageView(
        icon: Icons.bluetooth_searching,
        title: localizations.searching_devices,
        loading: true,
      );
    }

    if (_controller.devices.isEmpty) {
      return MessageView(
        icon: Icons.bluetooth_disabled,
        title: localizations.no_devices_found,
        message: _controller.permissionsMissing
            ? localizations.android_ble_permissions_missing
            : localizations.no_devices_found_hint,
        actions: [
          FilledButton.tonal(
            onPressed: _controller.scanInProgress ? null : _controller.scan,
            child: Text(localizations.scan_again),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _controller.devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final device = _controller.devices[index];
        return _DeviceTile(
          device: device,
          enabled: !_controller.connectionInProgress,
          onTap: () => _connect(device),
        );
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.enabled,
    required this.onTap,
  });

  final Chameleon device;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final isBle = device.type == ConnectionType.ble;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 72,
        enabled: enabled,
        onTap: onTap,
        leading: SizedBox(
          width: 48,
          child: Image.asset(
            deviceImageAsset(device.device == ChameleonDevice.ultra),
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const Icon(Icons.nfc),
          ),
        ),
        title: Text(
          'Chameleon ${chameleonDeviceName(device.device)}'
          '${device.dfu ? localizations.dfu : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${device.port ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          isBle ? Icons.bluetooth : Icons.usb,
          color: scheme.primary,
        ),
      ),
    );
  }
}

/// Shown while a BLE connection is being established.
class MobileConnectingView extends StatelessWidget {
  const MobileConnectingView({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final boldStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.bold);

    return Scaffold(
      appBar: AppBar(title: Text(localizations.connect)),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  localizations.connecting_to_ble,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  localizations.default_ble_password,
                  textAlign: TextAlign.center,
                  style: boldStyle,
                ),
                const SizedBox(height: 8),
                Text(
                  localizations.connection_might_take_some_time,
                  textAlign: TextAlign.center,
                  style: boldStyle,
                ),
                const SizedBox(height: 8),
                Text(
                  localizations.ble_need_to_remove_pair,
                  textAlign: TextAlign.center,
                  style: boldStyle,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => context.read<ChameleonGUIState>().disconnect(
                    manual: true,
                  ),
                  child: Text(localizations.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
