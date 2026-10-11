import 'package:chameleonultragui/gui/menu/dialogs/slot/settings.dart';
import 'package:chameleonultragui/gui/mobile/controllers/device_controller.dart';
import 'package:chameleonultragui/gui/mobile/pages/library_page.dart';
import 'package:chameleonultragui/gui/mobile/widgets/action_sheet.dart';
import 'package:chameleonultragui/gui/mobile/widgets/helpers.dart';
import 'package:chameleonultragui/gui/mobile/widgets/message_view.dart';
import 'package:chameleonultragui/gui/mobile/widgets/slot_upload.dart';
import 'package:chameleonultragui/gui/mobile/widgets/slot_widgets.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Runs [action] and reports a failure in a snack bar.
Future<void> showErrorOnFailure(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      showMessage(context, '${AppLocalizations.of(context)!.error}: $e');
    }
  }
}

/// Contextual actions for one slot: activate, load a saved card, and the
/// existing slot settings dialog for advanced configuration.
Future<void> showSlotActions(BuildContext context, int slot) {
  final device = context.read<MobileDeviceController>();
  final localizations = AppLocalizations.of(context)!;

  Future<void> loadCard() async {
    final card = await Navigator.of(context).push<CardSave>(
      MaterialPageRoute(
        builder: (_) => const MobileLibraryPage(pickMode: true),
      ),
    );
    if (card == null || !context.mounted) {
      return;
    }

    await loadCardIntoSlotWithProgress(context, slot: slot, card: card);
  }

  Future<void> openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => SlotSettings(slot: slot, refresh: () {}),
    );
    // The dialog talks to the device itself (and activates the slot).
    await device.slotsChangedExternally();
  }

  return showActionSheet(
    context,
    title: '${localizations.slot} ${slot + 1}',
    subtitle: slotFrequencyLabel(device, slot, TagFrequency.hf, localizations),
    actions: [
      SheetAction(
        icon: Icons.check_circle_outline,
        label: localizations.activate,
        enabled: device.activeSlot != slot,
        onTap: () =>
            showErrorOnFailure(context, () => device.activateSlot(slot)),
      ),
      SheetAction(
        icon: Icons.nfc,
        label: localizations.load_into_slot,
        onTap: loadCard,
      ),
      SheetAction(
        icon: Icons.tune,
        label: localizations.slot_settings,
        onTap: openSettings,
      ),
    ],
  );
}

/// Slot manager: all eight slots with their HF/LF contents.
class MobileSlotsPage extends StatelessWidget {
  const MobileSlotsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final device = context.watch<MobileDeviceController>();
    final localizations = AppLocalizations.of(context)!;

    Widget body;
    if (!device.isConnected) {
      body = MessageView(
        icon: Icons.usb_off,
        title: localizations.connect_device_to_use,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(localizations.go_to_device),
          ),
        ],
      );
    } else if (device.state == DeviceLoadState.loading && !device.slotsLoaded) {
      body = MessageView(
        icon: Icons.hourglass_empty,
        title: localizations.please_wait,
        loading: true,
      );
    } else if (!device.slotsLoaded) {
      body = MessageView(
        icon: Icons.error_outline,
        title: localizations.device_info_load_failed,
        actions: [
          FilledButton(
            onPressed: device.refresh,
            child: Text(localizations.retry),
          ),
        ],
      );
    } else {
      body = Column(
        children: [
          if (device.isUploading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: device.refreshSlots,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: 8,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, slot) => SlotCard(
                  slot: slot,
                  device: device,
                  onTap: () => showSlotActions(context, slot),
                  onToggle: (frequency, enabled) => showErrorOnFailure(
                    context,
                    () => device.setSlotEnabled(slot, frequency, enabled),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(localizations.slot_manager)),
      body: SafeArea(top: false, child: body),
    );
  }
}
