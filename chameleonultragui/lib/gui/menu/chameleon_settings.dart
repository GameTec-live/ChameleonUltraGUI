import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/component/dialog_confirm.dart';
import 'package:chameleonultragui/gui/component/dialog_device_settings.dart';
import 'package:chameleonultragui/gui/features/firmware_flasher.dart';
import 'package:chameleonultragui/helpers/files.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

class ChameleonSettings extends StatefulWidget {
  const ChameleonSettings({super.key});

  @override
  ChameleonSettingsState createState() => ChameleonSettingsState();
}

class ChameleonSettingsState extends State<ChameleonSettings> {
  late AnimationSetting animationMode;

  @override
  void initState() {
    super.initState();
  }

  Future<AnimationSetting> getAnimationMode() async {
    var appState = context.read<MyAppState>();

    try {
      return await appState.communicator!.getAnimationMode();
    } catch (_) {
      return AnimationSetting.full;
    }
  }

  Future<ButtonConfig> getButtonConfig(ButtonType type) async {
    var appState = context.read<MyAppState>();
    try {
      return await appState.communicator!.getButtonConfig(type);
    } catch (_) {
      return ButtonConfig.disable;
    }
  }

  Future<ButtonConfig> getLongButtonConfig(ButtonType type) async {
    var appState = context.read<MyAppState>();
    try {
      return await appState.communicator!.getLongButtonConfig(type);
    } catch (_) {
      return ButtonConfig.disable;
    }
  }

  Future<DeviceSettingsData> getSettingsData() async {
    return DeviceSettingsData(
      animationMode:  await getAnimationMode(),
      aButtonMode: await getButtonConfig(ButtonType.a),
      bButtonMode: await getButtonConfig(ButtonType.b),
      aLongButtonMode: await getLongButtonConfig(ButtonType.a),
      bLongButtonMode: await getLongButtonConfig(ButtonType.b)
    );
  }

  // ignore_for_file: use_build_context_synchronously
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return FutureBuilder(
      future: getSettingsData(),
      builder: (BuildContext dialogContext, AsyncSnapshot<DeviceSettingsData> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertDialog(
              title:
                  Text('Device Settings'),
              content:
                  CircularProgressIndicator());
        } else if (snapshot.hasError) {
          appState.log.e('Build error', error: snapshot.error);

          appState.connector.performDisconnect();
          return AlertDialog(
              title: const Text(
                  'Device Settings'),
              content: Text(
                  'Error: ${snapshot.error.toString()}'));
        }

        var deviceSettings = snapshot.data;
        if (deviceSettings == null) {
          // This should never happen, if data is null then
          // there should've been an error already
          throw ("Empty device settings snapshot");
        }

        onClose() {
          Navigator.pop(dialogContext, 'Cancel');
        }

        var scaffoldMessenger = ScaffoldMessenger.of(context);
        final communicator = appState.communicator!;

        var canUpdateLatest = !kIsWeb && appState.connector.connectionType != ConnectionType.ble;
        var canUpdateZip = canUpdateLatest;

        return DialogDeviceSettings(
          deviceSettings: deviceSettings,
          onClose: onClose,
          onEnterDFUMode: () async {
            onClose();

            await communicator.enterDFUMode();
            await appState.connector.performDisconnect();
            await asyncSleep(500);
            appState.changesMade();
          },
          onResetSettings: () async {
            await communicator.resetSettings();
            onClose();
            appState.changesMade();
          },
          onResetFactorySettings: () async {
            final hasConfirmed = await showConfirmDialog(
              context,
              title: 'Factory reset',
              cancelTitle: 'No',
              okTitle: 'Yes',
              content: const Text('Are you sure you want to factory reset your Chameleon?'),
            );

            if (hasConfirmed == null || !hasConfirmed) {
              return;
            }

            await communicator.factoryReset();
            await appState.connector.performDisconnect();
            onClose();
          },
          onUpdateAnimation: (animation) async {
            await communicator.setAnimationMode(animation);
            await communicator.saveSettings();

            setState(() {});
            appState.changesMade();
          },
          onUpdateButtonMode: (buttonType, mode) async {
            await communicator.setButtonConfig(
                    buttonType,
                    mode);
            await communicator.saveSettings();
            setState(() {});
            appState.changesMade();
          },
          onUpdateLongButtonMode: (buttonType, mode) async {
            await communicator.setLongButtonConfig(
                    buttonType,
                    mode);
            await communicator.saveSettings();
            setState(() {});
            appState.changesMade();
          },
          onFirmwareUpdateLatest: !canUpdateLatest ? null : () async {
            onClose();

            var snackBar = SnackBar(
              content: Text(
                  'Downloading and preparing new ${appState.connector.device.name} firmware...'),
              showCloseIcon: true,
            );

            scaffoldMessenger.showSnackBar(snackBar);
            try {
              var flasher = FirmwareFlasher.fromGithubNightly(appState.connector);
              await flasher.flash((progressUpdate) => appState.setFlashProgress(progressUpdate));
            } catch (e) {
              snackBar = SnackBar(
                content: Text('Update error: ${e.toString()}'),
                showCloseIcon: true,
              );

              scaffoldMessenger.hideCurrentSnackBar();
              scaffoldMessenger.showSnackBar(snackBar);
            }
          },
          onFirmwareUpdateFromZip: !canUpdateZip ? null : () async {
            onClose();

            try {
              FileResult? file = await pickFile(appState);
              if (file == null) {
                appState.log.d("Empty file picked");
                return;
              }

              var flasher = FirmwareFlasher.fromZipFile(appState.connector, file.bytes);
              await flasher.flash((progressUpdate) => appState.setFlashProgress(progressUpdate));

            } catch (e) {
              var snackBar = SnackBar(
                content: Text('Update error: ${e.toString()}'),
                showCloseIcon: true,
              );

              scaffoldMessenger.showSnackBar(snackBar);
            }
          }
        );
      }
    );
  }
}
