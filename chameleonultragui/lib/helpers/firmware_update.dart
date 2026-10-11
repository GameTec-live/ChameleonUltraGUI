import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Compares [currentCommit] with the latest firmware build and flashes it if
/// the device is outdated, reporting progress and errors through snack bars.
///
/// Returns the commit hash resolved from [currentCommit] (or [currentCommit]
/// itself if it could not be resolved) so callers can cache it.
Future<String> checkForFirmwareUpdate(
  ChameleonGUIState appState,
  ScaffoldMessengerState scaffoldMessenger,
  AppLocalizations localizations,
  String currentCommit,
) async {
  SnackBar snackBar;
  String latestCommit;

  try {
    latestCommit = await latestAvailableCommit(appState.connector!.device);
  } catch (e) {
    if (scaffoldMessenger.mounted) {
      scaffoldMessenger.hideCurrentSnackBar();
      snackBar = SnackBar(
        content: Text('${localizations.update_error}: ${e.toString()}'),
        action: SnackBarAction(
          label: localizations.close,
          onPressed: () {},
        ),
      );

      scaffoldMessenger.showSnackBar(snackBar);
    }
    return currentCommit;
  }

  try {
    currentCommit = await resolveCommit(currentCommit);
  } catch (_) {}

  appState.log!.i(
      "Latest commit: $latestCommit, current commit $currentCommit");

  if (latestCommit.isEmpty) {
    return currentCommit;
  }

  if (latestCommit.startsWith(currentCommit) && scaffoldMessenger.mounted) {
    snackBar = SnackBar(
      content: Text(localizations
          .up_to_date(chameleonDeviceName(appState.connector!.device))),
      action: SnackBarAction(
        label: localizations.close,
        onPressed: () {},
      ),
    );

    scaffoldMessenger.showSnackBar(snackBar);
  } else if (scaffoldMessenger.mounted) {
    snackBar = SnackBar(
      content: Text(localizations
          .downloading_fw(chameleonDeviceName(appState.connector!.device))),
      action: SnackBarAction(
        label: localizations.close,
        onPressed: () {
          scaffoldMessenger.hideCurrentSnackBar();
        },
      ),
    );

    scaffoldMessenger.showSnackBar(snackBar);
    try {
      await flashFirmware(appState, scaffoldMessenger: scaffoldMessenger);
    } catch (e) {
      if (scaffoldMessenger.mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        snackBar = SnackBar(
          content: Text('${localizations.update_error}: ${e.toString()}'),
          action: SnackBarAction(
            label: localizations.close,
            onPressed: () {
              scaffoldMessenger.hideCurrentSnackBar();
            },
          ),
        );

        scaffoldMessenger.showSnackBar(snackBar);
      }
    }
  }

  return currentCommit;
}
