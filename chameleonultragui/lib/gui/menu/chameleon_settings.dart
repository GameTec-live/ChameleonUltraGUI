import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/helpers/flash.dart';
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

  Future<
      (
        AnimationSetting,
        ButtonConfig,
        ButtonConfig,
        ButtonConfig,
        ButtonConfig
      )> getSettingsData() async {
    return (
      await getAnimationMode(),
      await getButtonConfig(ButtonType.a),
      await getButtonConfig(ButtonType.b),
      await getLongButtonConfig(ButtonType.a),
      await getLongButtonConfig(ButtonType.b)
    );
  }

  // ignore_for_file: use_build_context_synchronously
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return FutureBuilder(
        future: getSettingsData(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
                title: Text('Device Settings'),
                content: Column(children: [CircularProgressIndicator()]));
          } else if (snapshot.hasError) {
            appState.connector.performDisconnect();
            return AlertDialog(
                title: const Text('Device Settings'),
                content: Text('Error: ${snapshot.error.toString()}'));
          } else {
            var (
              animationMode,
              aButtonMode,
              bButtonMode,
              aLongButtonMode,
              bLongButtonMode
            ) = snapshot.data;

            return AlertDialog(
                title: const Text('Device Settings'),
                content: SingleChildScrollView(
                    child: Column(
                  children: [
                    const Text("Firmware management:"),
                    const SizedBox(height: 10),
                    TextButton(
                        onPressed: () async {
                          await appState.communicator!.enterDFUMode();
                          appState.connector.performDisconnect();
                          Navigator.pop(context, 'Cancel');
                          appState.changesMade();
                        },
                        child: const Row(
                          children: [
                            Icon(Icons.medical_services_outlined),
                            Text("Enter DFU Mode"),
                          ],
                        )),
                    if (appState.connector.connectionType !=
                        ConnectionType.ble) ...[
                      TextButton(
                          onPressed: () async {
                            Navigator.pop(context, 'Cancel');
                            var snackBar = SnackBar(
                              content: Text(
                                  'Downloading and preparing new Chameleon ${appState.connector.device == ChameleonDevice.ultra ? "Ultra" : "Lite"} firmware...'),
                              action: SnackBarAction(
                                label: 'Close',
                                onPressed: () {},
                              ),
                            );

                            ScaffoldMessenger.of(context)
                                .showSnackBar(snackBar);
                            try {
                              await flashFirmware(appState);
                            } catch (e) {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
                              snackBar = SnackBar(
                                content: Text('Update error: ${e.toString()}'),
                                action: SnackBarAction(
                                  label: 'Close',
                                  onPressed: () {},
                                ),
                              );

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(snackBar);
                            }
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.system_security_update),
                              Text("Flash latest FW via DFU"),
                            ],
                          )),
                      TextButton(
                          onPressed: () async {
                            Navigator.pop(context, 'Cancel');
                            await flashFirmwareZip(appState);
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.system_security_update_good),
                              Text("Flash .zip FW via DFU"),
                            ],
                          ))
                    ],
                    const SizedBox(height: 10),
                    const Text("Animations:"),
                    const SizedBox(height: 10),
                    ToggleButtonsWrapper(
                        items: const ['Full', 'Mini', 'None'],
                        selectedValue: animationMode.value,
                        onChange: (int index) async {
                          var animation = AnimationSetting.full;
                          if (index == 1) {
                            animation = AnimationSetting.minimal;
                          } else if (index == 2) {
                            animation = AnimationSetting.none;
                          }

                          await appState.communicator!
                              .setAnimationMode(animation);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    const SizedBox(height: 10),
                    const Text("Button config:"),
                    const SizedBox(height: 7),
                    const Text("A button:", textScaleFactor: 0.8),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: const [
                          'Disable',
                          'Forward',
                          'Backward',
                          'Clone UID'
                        ],
                        selectedValue: aButtonMode.value,
                        onChange: (int index) async {
                          var mode = ButtonConfig.disable;
                          if (index == 1) {
                            mode = ButtonConfig.cycleForward;
                          } else if (index == 2) {
                            mode = ButtonConfig.cycleBackward;
                          } else if (index == 3) {
                            mode = ButtonConfig.cloneUID;
                          }

                          await appState.communicator!
                              .setButtonConfig(ButtonType.a, mode);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    const SizedBox(height: 7),
                    const Text("B button:", textScaleFactor: 0.8),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: const [
                          'Disable',
                          'Forward',
                          'Backward',
                          'Clone UID'
                        ],
                        selectedValue: bButtonMode.value,
                        onChange: (int index) async {
                          var mode = ButtonConfig.disable;
                          if (index == 1) {
                            mode = ButtonConfig.cycleForward;
                          } else if (index == 2) {
                            mode = ButtonConfig.cycleBackward;
                          } else if (index == 3) {
                            mode = ButtonConfig.cloneUID;
                          }

                          await appState.communicator!
                              .setButtonConfig(ButtonType.b, mode);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    const SizedBox(height: 7),
                    const Text("Long press", textScaleFactor: 0.9),
                    const SizedBox(height: 7),
                    const Text("A button:", textScaleFactor: 0.8),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: const [
                          'Disable',
                          'Forward',
                          'Backward',
                          'Clone UID'
                        ],
                        selectedValue: aLongButtonMode.value,
                        onChange: (int index) async {
                          var mode = ButtonConfig.disable;
                          if (index == 1) {
                            mode = ButtonConfig.cycleForward;
                          } else if (index == 2) {
                            mode = ButtonConfig.cycleBackward;
                          } else if (index == 3) {
                            mode = ButtonConfig.cloneUID;
                          }

                          await appState.communicator!
                              .setLongButtonConfig(ButtonType.a, mode);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    const SizedBox(height: 7),
                    const Text("B button:", textScaleFactor: 0.8),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: const [
                          'Disable',
                          'Forward',
                          'Backward',
                          'Clone UID'
                        ],
                        selectedValue: bLongButtonMode.value,
                        onChange: (int index) async {
                          var mode = ButtonConfig.disable;
                          if (index == 1) {
                            mode = ButtonConfig.cycleForward;
                          } else if (index == 2) {
                            mode = ButtonConfig.cycleBackward;
                          } else if (index == 3) {
                            mode = ButtonConfig.cloneUID;
                          }

                          await appState.communicator!
                              .setLongButtonConfig(ButtonType.b, mode);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    const SizedBox(height: 10),
                    const Text("Other:"),
                    const SizedBox(height: 10),
                    TextButton(
                        onPressed: () async {
                          await appState.communicator!.resetSettings();
                          Navigator.pop(context, 'Cancel');
                          appState.changesMade();
                        },
                        child: const Row(
                          children: [
                            Icon(Icons.lock_reset),
                            Text("Reset settings"),
                          ],
                        )),
                    TextButton(
                        onPressed: () async {
                          // Ask for confirmation
                          Navigator.pop(context, 'Cancel');
                          showDialog(
                            context: context,
                            builder: (BuildContext context) => AlertDialog(
                              title: const Text('Factory reset'),
                              content: const Text(
                                  'Are you sure you want to factory reset your Chameleon?'),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () async {
                                    await appState.communicator!.factoryReset();
                                    await appState.connector
                                        .performDisconnect();
                                    Navigator.pop(context, 'Cancel');
                                    appState.changesMade();
                                  },
                                  child: const Text('Yes'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, 'Cancel'),
                                  child: const Text('No'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Row(
                          children: [
                            Icon(Icons.restore_from_trash_outlined),
                            Text("Factory reset"),
                          ],
                        )),
                  ],
                )));
          }
        });
  }
}
