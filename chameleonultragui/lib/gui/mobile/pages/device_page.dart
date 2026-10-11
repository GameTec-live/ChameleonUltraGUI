import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/menu/dialogs/chameleon_settings.dart';
import 'package:chameleonultragui/gui/mobile/controllers/device_controller.dart';
import 'package:chameleonultragui/gui/mobile/pages/slots_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/writer_page.dart';
import 'package:chameleonultragui/gui/mobile/widgets/helpers.dart';
import 'package:chameleonultragui/gui/mobile/widgets/message_view.dart';
import 'package:chameleonultragui/gui/mobile/widgets/slot_widgets.dart';
import 'package:chameleonultragui/helpers/firmware_update.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Dashboard of the connected device: status, slots, quick actions and
/// firmware information. Data comes from [MobileDeviceController], which loads
/// it once per connection (or on pull-to-refresh).
class MobileDevicePage extends StatelessWidget {
  const MobileDevicePage({super.key, required this.onOpenReader});

  /// Switches the shell to the Read tab.
  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) {
    final device = context.watch<MobileDeviceController>();
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final connector = appState.connector!;

    Widget body;
    if (device.state == DeviceLoadState.error) {
      body = MessageView(
        icon: Icons.error_outline,
        title: localizations.device_info_load_failed,
        message: device.error.toString(),
        actions: [
          FilledButton(
            onPressed: device.load,
            child: Text(localizations.retry),
          ),
          OutlinedButton(
            onPressed: () => appState.disconnect(manual: true),
            child: Text(localizations.disconnect),
          ),
        ],
      );
    } else if (device.state != DeviceLoadState.ready) {
      body = MessageView(
        icon: Icons.hourglass_empty,
        title: localizations.please_wait,
        loading: true,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: device.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(device: device, connector: connector),
            if (connector.portName == 'Demo') ...[
              const SizedBox(height: 12),
              _Banner(
                icon: Icons.error_outline,
                text: localizations.demo_firmware,
              ),
            ],
            if (device.legacyProtocol || !device.capabilitiesSupported) ...[
              const SizedBox(height: 12),
              _Banner(
                icon: Icons.system_update,
                text: device.legacyProtocol
                    ? localizations.outdated_protocol_description_1
                    : localizations.please_update_firmware,
                action: TextButton(
                  onPressed: () => _updateFirmware(context),
                  child: Text(localizations.update),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _QuickActions(onOpenReader: onOpenReader),
            const SizedBox(height: 16),
            _SlotsSection(device: device),
            const SizedBox(height: 16),
            _FirmwareSection(device: device, connector: connector),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.mobile_nav_device),
        actions: [
          IconButton(
            tooltip: localizations.disconnect,
            onPressed: () => appState.disconnect(manual: true),
            icon: const Icon(Icons.link_off),
          ),
        ],
      ),
      body: body,
    );
  }
}

Future<void> _updateFirmware(BuildContext context) async {
  final appState = context.read<ChameleonGUIState>();
  final localizations = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  messenger.hideCurrentSnackBar();
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.device, required this.connector});

  final MobileDeviceController device;
  final AbstractSerial connector;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;
    final battery = device.battery;
    final isBle = connector.connectionType == ConnectionType.ble;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 96,
              child: Image.asset(
                deviceImageAsset(connector.device == ChameleonDevice.ultra),
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const Icon(Icons.nfc, size: 48),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chameleon ${chameleonDeviceName(connector.device)}',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        avatar: Icon(
                          isBle ? Icons.bluetooth : Icons.usb,
                          size: 18,
                        ),
                        label: Text(
                          connector.portName,
                          overflow: TextOverflow.ellipsis,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      Tooltip(
                        message: battery == null
                            ? localizations.unknown
                            : localizations.battery_info(
                                battery.percent,
                                battery.voltage,
                              ),
                        child: Chip(
                          avatar: Icon(
                            batteryIcon(battery?.percent ?? 0),
                            size: 18,
                          ),
                          label: Text(
                            battery == null
                                ? localizations.unknown
                                : '${battery.percent}%',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${localizations.used_slots}: ${device.usedSlots}/8',
                    style: theme.textTheme.bodyMedium,
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

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onOpenReader});

  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    Widget action(IconData icon, String label, VoidCallback onTap) {
      return Expanded(
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(72),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          ),
          onPressed: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.quick_actions,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            action(Icons.sensors, localizations.read, onOpenReader),
            const SizedBox(width: 8),
            action(
              Icons.system_update_alt,
              localizations.write,
              () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MobileWriterPage()),
              ),
            ),
            const SizedBox(width: 8),
            action(
              Icons.widgets,
              localizations.slots,
              () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MobileSlotsPage()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SlotsSection extends StatelessWidget {
  const _SlotsSection({required this.device});

  final MobileDeviceController device;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.slots,
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (device.readerMode)
              TextButton.icon(
                onPressed: () => _setMode(context, false),
                icon: const Icon(Icons.nfc_sharp),
                label: Text(localizations.emulator_mode),
              )
            else
              TextButton.icon(
                onPressed: () => _setMode(context, true),
                icon: const Icon(Icons.barcode_reader),
                label: Text(localizations.reader_mode),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (!device.slotsLoaded)
          Text(localizations.unknown)
        else
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.1,
            children: [
              for (int slot = 0; slot < 8; slot++)
                SlotGridTile(
                  slot: slot,
                  device: device,
                  onTap: () async {
                    try {
                      await device.activateSlot(slot);
                    } catch (e) {
                      if (context.mounted) {
                        showMessage(context, '${localizations.error}: $e');
                      }
                    }
                  },
                  onLongPress: () => showSlotActions(context, slot),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _setMode(BuildContext context, bool reader) async {
    try {
      await device.setReaderMode(reader);
    } catch (e) {
      if (context.mounted) {
        showMessage(context, '${AppLocalizations.of(context)!.error}: $e');
      }
    }
  }
}

class _FirmwareSection extends StatelessWidget {
  const _FirmwareSection({required this.device, required this.connector});

  final MobileDeviceController device;
  final AbstractSerial connector;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.read<ChameleonGUIState>();
    final isDemo = connector.portName == 'Demo';
    final commit = device.commitHash.isEmpty
        ? localizations.outdated_fw
        : device.commitHash;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.memory),
        title: Text(localizations.firmware),
        subtitle: Text(
          isDemo ? localizations.demo_firmware : device.firmwareVersion,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          ListTile(
            title: Text(localizations.firmware_version),
            subtitle: Text('${device.firmwareVersion} ($commit)'),
          ),
          if (!isDemo)
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.update),
              title: Text(localizations.check_updates),
              onTap: () => checkForFirmwareUpdate(
                appState,
                ScaffoldMessenger.of(context),
                localizations,
                device.commitHash,
              ),
            ),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.settings),
            title: Text(localizations.device_settings),
            onTap: () => showDialog<String>(
              context: context,
              builder: (_) => const ChameleonSettings(),
            ),
          ),
        ],
      ),
    );
  }
}
