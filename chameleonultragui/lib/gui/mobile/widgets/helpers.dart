import 'package:chameleonultragui/gui/menu/dialogs/confirm_delete.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

void showMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  final localizations = AppLocalizations.of(context)!;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: localizations.close,
        onPressed: messenger.hideCurrentSnackBar,
      ),
    ),
  );
}

/// Asks for confirmation before deleting [name], unless the user turned
/// deletion confirmations off in the settings.
Future<bool> confirmDeletion(BuildContext context, String name) async {
  final appState = context.read<ChameleonGUIState>();
  if (!appState.sharedPreferencesProvider.getConfirmDelete()) {
    return true;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => ConfirmDeletionMenu(thingBeingDeleted: name),
  );
  return confirmed == true;
}

IconData batteryIcon(int percent) {
  if (percent > 98) return Icons.battery_full;
  if (percent > 87) return Icons.battery_6_bar;
  if (percent > 75) return Icons.battery_5_bar;
  if (percent > 62) return Icons.battery_4_bar;
  if (percent > 50) return Icons.battery_3_bar;
  if (percent > 37) return Icons.battery_2_bar;
  if (percent > 10) return Icons.battery_1_bar;
  if (percent > 3) return Icons.battery_0_bar;
  if (percent > 0) return Icons.battery_alert;
  return Icons.battery_unknown;
}

String deviceImageAsset(bool ultra) => ultra
    ? 'assets/black-ultra-standing-front.webp'
    : 'assets/black-lite-standing-front.webp';
