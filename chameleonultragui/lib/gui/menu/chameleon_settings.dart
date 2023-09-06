import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
    var appState = context.read<ChameleonGUIState>();

    try {
      return await appState.communicator!.getAnimationMode();
    } catch (_) {
      return AnimationSetting.full;
    }
  }

  Future<ButtonConfig> getButtonConfig(ButtonType type) async {
    var appState = context.read<ChameleonGUIState>();
    try {
      return await appState.communicator!.getButtonConfig(type);
    } catch (_) {
      return ButtonConfig.disable;
    }
  }

  Future<ButtonConfig> getLongButtonConfig(ButtonType type) async {
    var appState = context.read<ChameleonGUIState>();
    try {
      return await appState.communicator!.getLongButtonConfig(type);
    } catch (_) {
      return ButtonConfig.disable;
    }
  }

  Future<String> getBLEConnectionKey() async {
    var appState = context.read<ChameleonGUIState>();

    try {
      return await appState.communicator!.getBLEConnectionKey();
    } catch (_) {
      return "123456";
    }
  }

  Future<
      (
        AnimationSetting,
        ButtonConfig,
        ButtonConfig,
        ButtonConfig,
        ButtonConfig,
        String
      )> getSettingsData() async {
    return (
      await getAnimationMode(),
      await getButtonConfig(ButtonType.a),
      await getButtonConfig(ButtonType.b),
      await getLongButtonConfig(ButtonType.a),
      await getLongButtonConfig(ButtonType.b),
      await getBLEConnectionKey()
    );
  }

  // ignore_for_file: use_build_context_synchronously
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    return FutureBuilder(
        future: getSettingsData(),
        builder: (BuildContext buildContext, AsyncSnapshot snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AlertDialog(
                title: Text(localizations.device_settings),
                content: const Column(children: [CircularProgressIndicator()]));
          } else if (snapshot.hasError) {
            appState.connector!.performDisconnect();
            return AlertDialog(
                title: Text(localizations.device_settings),
                content: Text(
                    '${localizations.error}: ${snapshot.error.toString()}'));
          } else {
            var (
              animationMode,
              aButtonMode,
              bButtonMode,
              aLongButtonMode,
              bLongButtonMode,
              connectionKey
            ) = snapshot.data;
            TextEditingController bleKeyController =
                TextEditingController(text: connectionKey);
            return AlertDialog(
                title: Text(localizations.device_settings),
                content: SingleChildScrollView(
                    child: Column(
                  children: [
                    Text("${localizations.firmware_management}:"),
                    const SizedBox(height: 10),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: TextButton(
                            onPressed: () async {
                              await appState.communicator!.enterDFUMode();
                              appState.connector!.performDisconnect();
                              Navigator.pop(buildContext, localizations.cancel);
                              appState.changesMade();
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.medical_services_outlined),
                                Text(localizations.enter_dfu),
                              ],
                            ))),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: TextButton(
                            onPressed: () async {
                              Navigator.pop(buildContext, localizations.cancel);
                              var snackBar = SnackBar(
                                content: Text(localizations.downloading_fw(
                                    chameleonDeviceName(
                                        appState.connector!.device))),
                                action: SnackBarAction(
                                  label: localizations.close,
                                  onPressed: () {},
                                ),
                              );

                              scaffoldMessenger.showSnackBar(snackBar);
                              try {
                                await flashFirmware(appState,
                                    scaffoldMessenger: scaffoldMessenger);
                              } catch (e) {
                                scaffoldMessenger.hideCurrentSnackBar();
                                snackBar = SnackBar(
                                  content: Text(
                                      '${localizations.update_error}: ${e.toString()}'),
                                  action: SnackBarAction(
                                    label: localizations.close,
                                    onPressed: () {},
                                  ),
                                );

                                scaffoldMessenger.showSnackBar(snackBar);
                              }
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.system_security_update),
                                Text(localizations.flash_via_dfu),
                              ],
                            ))),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: TextButton(
                            onPressed: () async {
                              Navigator.pop(buildContext, localizations.cancel);
                              await flashFirmwareZip(appState,
                                  scaffoldMessenger: scaffoldMessenger);
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.system_security_update_good),
                                Text(localizations.flash_zip_dfu),
                              ],
                            ))),
                    const SizedBox(height: 10),
                    Text("${localizations.animations}:"),
                    const SizedBox(height: 10),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.full,
                          localizations.mini,
                          localizations.none
                        ],
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
                    Text("${localizations.button_config}:"),
                    const SizedBox(height: 7),
                    Text("${localizations.button_x("A")}:",
                        textScaleFactor: 0.8),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.disable,
                          localizations.forward,
                          localizations.backward,
                          localizations.clone_uid
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
                    Text("${localizations.button_x("B")}:",
                        textScaleFactor: 0.8),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.disable,
                          localizations.forward,
                          localizations.backward,
                          localizations.clone_uid
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
                    Text(localizations.long_press, textScaleFactor: 0.9),
                    const SizedBox(height: 7),
                    Text("${localizations.button_x("A")}:",
                        textScaleFactor: 0.8),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.disable,
                          localizations.forward,
                          localizations.backward,
                          localizations.clone_uid
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
                    Text("${localizations.button_x("B")}:",
                        textScaleFactor: 0.8),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.disable,
                          localizations.forward,
                          localizations.backward,
                          localizations.clone_uid
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
                    const Text("BLE:"),
                    const SizedBox(height: 10),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: TextButton(
                            onPressed: () async {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) => AlertDialog(
                                  title: Text(localizations.clear_ble_bonds),
                                  content: Text(localizations
                                      .clear_ble_bonds_confirmation),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () async {
                                        await appState.communicator!
                                            .clearBLEBoundedDevices();
                                        if (appState
                                                .connector!.connectionType ==
                                            ConnectionType.ble) {
                                          await appState.connector!
                                              .performDisconnect();
                                        }
                                        Navigator.pop(
                                            context, localizations.cancel);
                                        appState.changesMade();
                                      },
                                      child: Text(localizations.yes),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(
                                          context, localizations.cancel),
                                      child: Text(localizations.no),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.settings_bluetooth),
                                Text(localizations.clear_ble_bonds),
                              ],
                            ))),
                    Form(
                        key: formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                  controller: bleKeyController,
                                  maxLength: 6,
                                  validator: (value) {
                                    if (value == null ||
                                        value.isEmpty ||
                                        value.length != 6 ||
                                        double.tryParse(value) == null) {
                                      return localizations.pin_must_be_6_digits;
                                    }

                                    if (0 < double.tryParse(value)! &&
                                        double.tryParse(value)! > 0xFFFFFFFF) {
                                      return localizations.pin_must_be_6_digits;
                                    }

                                    return null;
                                  },
                                  decoration: InputDecoration(
                                    labelText: localizations.ble_pin,
                                    hintText: localizations.enter_pin,
                                  )),
                            ),
                            TextButton(
                              onPressed: () async {
                                if (formKey.currentState!.validate()) {
                                  await appState.communicator!
                                      .setBLEConnectKey(bleKeyController.text);
                                  await appState.communicator!.saveSettings();
                                  Navigator.pop(context, localizations.cancel);
                                  appState.changesMade();
                                }
                              },
                              child: Text(localizations.save),
                            ),
                          ],
                        )),
                    const SizedBox(height: 10),
                    Text("${localizations.other}:"),
                    const SizedBox(height: 10),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: TextButton(
                            onPressed: () async {
                              await appState.communicator!.resetSettings();
                              Navigator.pop(context, localizations.cancel);
                              appState.changesMade();
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.lock_reset),
                                Text(localizations.reset_settings),
                              ],
                            ))),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: TextButton(
                            onPressed: () async {
                              // Ask for confirmation
                              Navigator.pop(context, localizations.cancel);
                              showDialog(
                                context: context,
                                builder: (BuildContext context) => AlertDialog(
                                  title: Text(localizations.factory_reset),
                                  content: Text(
                                      localizations.factory_reset_confirmation),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () async {
                                        await appState.communicator!
                                            .factoryReset();
                                        await appState.connector!
                                            .performDisconnect();
                                        Navigator.pop(
                                            context, localizations.cancel);
                                        appState.changesMade();
                                      },
                                      child: Text(localizations.yes),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(
                                          context, localizations.cancel),
                                      child: Text(localizations.no),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.restore_from_trash_outlined),
                                Text(localizations.factory_reset),
                              ],
                            ))),
                  ],
                )));
          }
        });
  }
}
