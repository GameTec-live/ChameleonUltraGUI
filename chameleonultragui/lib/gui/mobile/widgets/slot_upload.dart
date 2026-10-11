import 'package:chameleonultragui/gui/mobile/controllers/device_controller.dart';
import 'package:chameleonultragui/gui/mobile/widgets/helpers.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Uploads [card] to [slot] (zero based) behind a blocking progress dialog and
/// reports the result in a snack bar.
Future<void> loadCardIntoSlotWithProgress(
  BuildContext context, {
  required int slot,
  required CardSave card,
}) async {
  final controller = context.read<MobileDeviceController>();
  final localizations = AppLocalizations.of(context)!;
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => AlertDialog(
          title: Text(localizations.uploading_dump),
          content: LinearProgressIndicator(
            value: controller.uploadProgress < 0
                ? null
                : controller.uploadProgress / 100,
          ),
        ),
      ),
    ),
  );

  String message;
  try {
    final loaded = await controller.loadCardIntoSlotIndex(
      slot,
      card,
      localizations.no_name,
    );
    message = loaded
        ? localizations.card_loaded_to_slot(slot + 1)
        : localizations.card_type_not_loadable;
  } catch (e) {
    message = '${localizations.error}: $e';
  }

  navigator.pop();
  showMessageOn(messenger, message, localizations.close);
}

/// Lets the user choose one of the eight slots. Returns the zero based index.
Future<int?> showSlotPicker(BuildContext context) {
  final controller = context.read<MobileDeviceController>();
  final localizations = AppLocalizations.of(context)!;

  return showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              localizations.select_slot,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
          ),
          for (int i = 0; i < 8; i++)
            ListTile(
              minTileHeight: 56,
              leading: CircleAvatar(radius: 16, child: Text('${i + 1}')),
              title: Text('${localizations.slot} ${i + 1}'),
              subtitle: Text(
                _slotSummary(controller, i, localizations),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected: i == controller.activeSlot,
              onTap: () => Navigator.of(sheetContext).pop(i),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

String _slotSummary(
  MobileDeviceController controller,
  int slot,
  AppLocalizations l,
) {
  final names = controller.slotNames[slot];
  final parts = [
    if (names.hf.isNotEmpty) '${l.hf}: ${names.hf}',
    if (names.lf.isNotEmpty) '${l.lf}: ${names.lf}',
  ];
  return parts.isEmpty ? l.empty : parts.join('  ');
}

Future<void> pickSlotAndLoadCard(BuildContext context, CardSave card) async {
  final slot = await showSlotPicker(context);
  if (slot == null || !context.mounted) {
    return;
  }

  await loadCardIntoSlotWithProgress(context, slot: slot, card: card);
}

void showDeviceRequired(BuildContext context) {
  showMessage(context, AppLocalizations.of(context)!.connect_device_to_use);
}
