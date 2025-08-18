import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class ChameleonSettings extends StatefulWidget {
  const ChameleonSettings({super.key});

  @override
  ChameleonSettingsState createState() => ChameleonSettingsState();
}

class ChameleonSettingsState extends State<ChameleonSettings> {
  int? currentLongPressThreshold;

  @override
  void initState() {
    super.initState();
    // Fetch the current long press threshold when the widget initializes
    _updateLongPressThreshold();
  }

  Future<void> _updateLongPressThreshold() async {
    if (!mounted) return;
    
    var appState = context.read<ChameleonGUIState>();
    
    // Don't attempt to fetch if not connected
    if (!appState.connector!.connected || appState.communicator == null) return;
    
    try {
      int threshold = await appState.communicator!.getLongPressThreshold();
      if (mounted) {
        setState(() {
          currentLongPressThreshold = threshold;
        });
      }
    } catch (e) {
      // Log the error but don't display it to the user, we'll use the default value
      appState.log?.w("Error getting long press threshold: $e");
      
      // If this was a timeout or busy error, try again once after a short delay
      if (e.toString().contains("Timeout") && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          int threshold = await appState.communicator!.getLongPressThreshold();
          if (mounted) {
            setState(() {
              currentLongPressThreshold = threshold;
            });
          }
        } catch (retryError) {
          // Just use the default from settings
          appState.log?.w("Retry failed: $retryError");
        }
      }
    }
  }

  Future<DeviceSettings> getSettingsData() async {
    var appState = context.read<ChameleonGUIState>();
    try {
      return await appState.communicator!.getDeviceSettings();
    } catch (_) {
      return DeviceSettings();
    }
  }

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
                content: ErrorPage(errorMessage: snapshot.error.toString()));
          } else {
            DeviceSettings settings = snapshot.data;
            TextEditingController bleKeyController =
                TextEditingController(text: settings.key);
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
                        child: ElevatedButton(
                            onPressed: () async {
                              await appState.communicator!.enterDFUMode();
                              appState.connector!.performDisconnect();
                              if (buildContext.mounted) {
                                Navigator.pop(buildContext);
                              }
                              appState.changesMade();
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.medical_services_outlined),
                                Text(localizations.enter_dfu),
                              ],
                            ))),
                    const SizedBox(height: 10),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(buildContext);
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
                    const SizedBox(height: 10),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(buildContext);
                              try {
                                await flashFirmwareZip(appState,
                                    scaffoldMessenger: scaffoldMessenger);
                              } catch (e) {
                                scaffoldMessenger.hideCurrentSnackBar();
                                var snackBar = SnackBar(
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
                        selectedValue: settings.animation.value,
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
                        textScaler: const TextScaler.linear(0.8)),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.disable,
                          localizations.forward,
                          localizations.backward,
                          localizations.clone_uid,
                          localizations.charge
                        ],
                        selectedValue: settings.aPress.value,
                        onChange: (int index) async {
                          var mode = ButtonConfig.disable;
                          if (index == 1) {
                            mode = ButtonConfig.cycleForward;
                          } else if (index == 2) {
                            mode = ButtonConfig.cycleBackward;
                          } else if (index == 3) {
                            mode = ButtonConfig.cloneUID;
                          } else if (index == 4) {
                            mode = ButtonConfig.chargeStatus;
                          }

                          await appState.communicator!
                              .setButtonConfig(ButtonType.a, mode);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    const SizedBox(height: 7),
                    Text("${localizations.button_x("B")}:",
                        textScaler: const TextScaler.linear(0.8)),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.disable,
                          localizations.forward,
                          localizations.backward,
                          localizations.clone_uid,
                          localizations.charge
                        ],
                        selectedValue: settings.bPress.value,
                        onChange: (int index) async {
                          var mode = ButtonConfig.disable;
                          if (index == 1) {
                            mode = ButtonConfig.cycleForward;
                          } else if (index == 2) {
                            mode = ButtonConfig.cycleBackward;
                          } else if (index == 3) {
                            mode = ButtonConfig.cloneUID;
                          } else if (index == 4) {
                            mode = ButtonConfig.chargeStatus;
                          }

                          await appState.communicator!
                              .setButtonConfig(ButtonType.b, mode);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    const SizedBox(height: 7),
                    Text(localizations.long_press,
                        textScaler: const TextScaler.linear(0.9)),
                    const SizedBox(height: 7),
                    Text("${localizations.button_x("A")}:",
                        textScaler: const TextScaler.linear(0.8)),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.disable,
                          localizations.forward,
                          localizations.backward,
                          localizations.clone_uid,
                          localizations.charge
                        ],
                        selectedValue: settings.aLongPress.value,
                        onChange: (int index) async {
                          var mode = ButtonConfig.disable;
                          if (index == 1) {
                            mode = ButtonConfig.cycleForward;
                          } else if (index == 2) {
                            mode = ButtonConfig.cycleBackward;
                          } else if (index == 3) {
                            mode = ButtonConfig.cloneUID;
                          } else if (index == 4) {
                            mode = ButtonConfig.chargeStatus;
                          }

                          await appState.communicator!
                              .setLongButtonConfig(ButtonType.a, mode);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    const SizedBox(height: 7),
                    Text("${localizations.button_x("B")}:",
                        textScaler: const TextScaler.linear(0.8)),
                    const SizedBox(height: 7),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.disable,
                          localizations.forward,
                          localizations.backward,
                          localizations.clone_uid,
                          localizations.charge
                        ],
                        selectedValue: settings.bLongPress.value,
                        onChange: (int index) async {
                          var mode = ButtonConfig.disable;
                          if (index == 1) {
                            mode = ButtonConfig.cycleForward;
                          } else if (index == 2) {
                            mode = ButtonConfig.cycleBackward;
                          } else if (index == 3) {
                            mode = ButtonConfig.cloneUID;
                          } else if (index == 4) {
                            mode = ButtonConfig.chargeStatus;
                          }

                          await appState.communicator!
                              .setLongButtonConfig(ButtonType.b, mode);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    const SizedBox(height: 10),
                    Text("Buttons Long Press Threshold:",
                        textScaler: const TextScaler.linear(0.9)),
                    const SizedBox(height: 7),
                    Builder(
                      builder: (context) {
                        // Use the directly fetched value if available, otherwise fall back to settings
                        final threshold = currentLongPressThreshold ?? settings.longPressThreshold;
                        
                        // Create the controller outside of setState to persist the value
                        final TextEditingController thresholdController = 
                          TextEditingController(text: threshold.toString());
                        final GlobalKey<FormFieldState> fieldKey = GlobalKey<FormFieldState>();
                        
                        return Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: fieldKey,
                                controller: thresholdController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Threshold (ms)",
                                  helperText: "200-65535 ms",
                                  hintText: "1000",
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return "Please enter a value";
                                  }
                                  int? threshold = int.tryParse(value);
                                  if (threshold == null) {
                                    return "Please enter a valid number";
                                  }
                                  if (threshold < 200) {
                                    return "Minimum is 200ms";
                                  }
                                  if (threshold > 65535) {
                                    return "Maximum is 65535ms";
                                  }
                                  return null;
                                },
                              ),
                            ),
                            ElevatedButton(
                              child: const Text("Save"),
                              onPressed: () async {
                                if (fieldKey.currentState!.validate()) {
                                  try {
                                    int threshold = int.parse(thresholdController.text);
                                    bool success = await appState.communicator!.setLongPressThreshold(threshold);
                                    
                                    if (success) {
                                      await appState.communicator!.saveSettings();
                                      
                                      setState(() {
                                        currentLongPressThreshold = threshold;
                                      });
                                      
                                      appState.changesMade();
                                      
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text("Failed to set threshold"),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("Error saving threshold: ${e.toString()}"),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    
                                    if (!appState.connector!.connected) {
                                      Navigator.of(context).pop();
                                    }
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.info_outline),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) => AlertDialog(
                                    title: const Text("Long Press Threshold"),
                                    content: const Text(
                                        "Sets the time in milliseconds for how long a button needs to be pressed to be considered a 'long press'.\n\nDefault: 1000ms (1 second)"),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(localizations.close),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      }
                    ),
                    const SizedBox(height: 10),
                    const Text("BLE:"),
                    const SizedBox(height: 10),
                    Text('${localizations.ble_pairing}:'),
                    const SizedBox(height: 10),
                    ToggleButtonsWrapper(
                        items: [
                          localizations.enabled,
                          localizations.disabled,
                        ],
                        selectedValue: settings.pairingEnabled ? 0 : 1,
                        onChange: (int index) async {
                          await appState.communicator!
                              .setBLEPairEnabled(index == 0);
                          await appState.communicator!.saveSettings();
                          setState(() {});
                          appState.changesMade();
                        }),
                    ...(settings.pairingEnabled)
                        ? [
                            const SizedBox(height: 10),
                            FittedBox(
                                alignment: Alignment.centerRight,
                                fit: BoxFit.scaleDown,
                                child: ElevatedButton(
                                    onPressed: () async {
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext context) =>
                                            AlertDialog(
                                          title: Text(
                                              localizations.clear_ble_bonds),
                                          content: Text(localizations
                                              .clear_ble_bonds_confirmation),
                                          actions: <Widget>[
                                            TextButton(
                                              onPressed: () async {
                                                await appState.communicator!
                                                    .clearBLEBoundedDevices();
                                                if (appState.connector!
                                                        .connectionType ==
                                                    ConnectionType.ble) {
                                                  await appState.connector!
                                                      .performDisconnect();
                                                }

                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }

                                                appState.changesMade();
                                              },
                                              child: Text(localizations.yes),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
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
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
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
                                                double.tryParse(value) ==
                                                    null) {
                                              return localizations
                                                  .pin_must_be_6_digits;
                                            }

                                            if (0 < double.tryParse(value)! &&
                                                double.tryParse(value)! >
                                                    0xFFFFFFFF) {
                                              return localizations
                                                  .pin_must_be_6_digits;
                                            }

                                            return null;
                                          },
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                                RegExp(r'[0-9]'))
                                          ],
                                          decoration: InputDecoration(
                                            labelText: localizations.ble_pin,
                                            hintText: localizations.enter_pin,
                                          )),
                                    ),
                                    ElevatedButton(
                                      onPressed: () async {
                                        if (formKey.currentState!.validate()) {
                                          await appState.communicator!
                                              .setBLEConnectKey(
                                                  bleKeyController.text);
                                          await appState.communicator!
                                              .saveSettings();

                                          if (context.mounted) {
                                            Navigator.pop(context);
                                          }

                                          appState.changesMade();
                                        }
                                      },
                                      child: Text(localizations.save),
                                    ),
                                  ],
                                )),
                          ]
                        : [],
                    const SizedBox(height: 10),
                    Text("${localizations.other}:"),
                    const SizedBox(height: 10),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: ElevatedButton(
                            onPressed: () async {
                              await appState.communicator!.resetSettings();

                              if (context.mounted) {
                                Navigator.pop(context);
                              }

                              appState.changesMade();
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.lock_reset),
                                Text(localizations.reset_settings),
                              ],
                            ))),
                    const SizedBox(height: 10),
                    FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: ElevatedButton(
                            onPressed: () async {
                              // Ask for confirmation
                              Navigator.pop(context);
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

                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }

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
