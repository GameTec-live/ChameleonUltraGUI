
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/component/dialog_confirm.dart';
import 'package:chameleonultragui/gui/component/helpers/confirm_http_proxy.dart';
import 'package:chameleonultragui/gui/features/firmware_flasher.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ButtonCheckFirmware extends StatelessWidget {
  final AbstractSerial connector;
  final String currentFirmwareVersion;
  final VoidCallback? onDeviceChange;
  final SharedPreferencesProvider sharedPreferences;

  const ButtonCheckFirmware({
    super.key,
    required this.connector,
    required this.currentFirmwareVersion,
    required this.sharedPreferences,
    this.onDeviceChange,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        SnackBar snackBar;

        var scaffoldMessenger = ScaffoldMessenger.of(context);
        final flasher = FirmwareFlasher.fromGithubNightly(connector);

        try {
          final isUpdateAvailable = await flasher.updateAvailable(currentFirmwareVersion);
          if (!isUpdateAvailable!) {
            snackBar = SnackBar(
              content: Text('Your ${connector.device.name} firmware is up to date'),
              showCloseIcon: true,
            );

            scaffoldMessenger.showSnackBar(snackBar);
            return;
          }
        } catch (e) {
          scaffoldMessenger.hideCurrentSnackBar();
          snackBar = SnackBar(
            content:
                Text('Update error: ${e.toString()}'),
            showCloseIcon: true,
          );

          scaffoldMessenger.showSnackBar(snackBar);
          return;
        }


        if (!context.mounted) {
          return;
        }

        bool? doAutomaticUpdate = await showDialog(
          context: context,
          builder: (BuildContext _) => DialogConfirm(
            title: 'Firmware update available',
            cancelTitle: 'No',
            okTitle: 'Yes',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  'A newer firmware version is available: ${flasher.availableFirmwareVersion}\n'
                  'Do you want to download & automatically update this firmware?'
                ),
              ]
            ),
          )
        );

        if (doAutomaticUpdate == null || !doAutomaticUpdate) {
          return;
        }

        if (!context.mounted) {
          return;
        }

        await confirmHttpProxy(
          context,
          sharedPreferences,
        );

        try {
          FlashFirmwareState? currentState;
          await flasher.flash((progressUpdate) {
            final state = progressUpdate.state;

            if (kIsWeb && state == FlashFirmwareState.changeDeviceMode) {
              onDeviceChange!();
              return;
            }

            if (currentState != state) {
              scaffoldMessenger.hideCurrentSnackBar();
              snackBar = SnackBar(
                content: Text(state.description),
                showCloseIcon: true,
              );

              scaffoldMessenger.showSnackBar(snackBar);
              currentState = state;
            }
          });
        } catch (e) {
          scaffoldMessenger.hideCurrentSnackBar();
          snackBar = SnackBar(
            content:
                Text('Update error: ${e.toString()}'),
            showCloseIcon: true,
          );

          scaffoldMessenger.showSnackBar(snackBar);
        }
      },
      tooltip: "Check for updates",
      icon: const Icon(Icons.update),
    );
  }
}