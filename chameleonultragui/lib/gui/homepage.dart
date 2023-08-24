import 'dart:io' show File;
import 'dart:typed_data';
import 'package:chameleonultragui/gui/components/togglebuttons.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/gui/components/slotchanger.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  var selectedSlot = 1;

  @override
  void initState() {
    super.initState();
  }

  Future<(Icon, String, List<String>, bool)> getFutureData() async {
    var appState = context.read<MyAppState>();
    List<(TagType, TagType)> usedSlots;
    try {
      usedSlots = await appState.communicator!.getUsedSlots();
    } catch (_) {
      usedSlots = [];
    }

    return (
      await getBatteryChargeIcon(),
      await getUsedSlotsOut8(usedSlots),
      await getVersion(),
      await isReaderDeviceMode()
    );
  }

  Future<(AnimationSetting, ButtonPress, ButtonPress)> getSettingsData() async {
    return (
      await getAnimationMode(),
      await getButtonConfig(ButtonType.a),
      await getButtonConfig(ButtonType.b)
    );
  }

  Future<Icon> getBatteryChargeIcon() async {
    var appState = context.read<MyAppState>();
    int charge = 0;

    try {
      (_, charge) = await appState.communicator!.getBatteryCharge();
    } catch (_) {}

    if (charge > 98) {
      return const Icon(Icons.battery_full);
    } else if (charge > 87) {
      return const Icon(Icons.battery_6_bar);
    } else if (charge > 75) {
      return const Icon(Icons.battery_5_bar);
    } else if (charge > 62) {
      return const Icon(Icons.battery_4_bar);
    } else if (charge > 50) {
      return const Icon(Icons.battery_3_bar);
    } else if (charge > 37) {
      return const Icon(Icons.battery_2_bar);
    } else if (charge > 10) {
      return const Icon(Icons.battery_1_bar);
    } else if (charge > 3) {
      return const Icon(Icons.battery_0_bar);
    } else if (charge > 0) {
      return const Icon(Icons.battery_alert);
    }

    return const Icon(Icons.battery_unknown);
  }

  Future<ButtonPress> getButtonConfig(ButtonType type) async {
    var appState = context.read<MyAppState>();
    return await appState.communicator!.getButtonConfig(type);
  }

  Future<String> getUsedSlotsOut8(List<(TagType, TagType)> usedSlots) async {
    int usedSlotsOut8 = 0;

    if (usedSlots.isEmpty) {
      return "Unknown";
    }

    for (int i = 0; i < 8; i++) {
      if (usedSlots[i].$1 != TagType.unknown ||
          usedSlots[i].$2 != TagType.unknown) {
        usedSlotsOut8++;
      }
    }
    return usedSlotsOut8.toString();
  }

  Future<List<String>> getVersion() async {
    var appState = context.read<MyAppState>();
    String commitHash = "";
    String firmwareVersion =
        numToVerCode(await appState.communicator!.getFirmwareVersion());

    try {
      commitHash = await appState.communicator!.getGitCommitHash();
    } catch (_) {}

    if (commitHash.isEmpty) {
      commitHash = "Outdated FW";
    }

    return ["$firmwareVersion ($commitHash)", commitHash];
  }

  Future<bool> isReaderDeviceMode() async {
    var appState = context.read<MyAppState>();
    return await appState.communicator!.isReaderDeviceMode();
  }

  Future<AnimationSetting> getAnimationMode() async {
    var appState = context.read<MyAppState>();

    try {
      return await appState.communicator!.getAnimationMode();
    } catch (_) {
      return AnimationSetting.full;
    }
  }

  Future<void> flashFirmware(MyAppState appState) async {
    Uint8List applicationDat, applicationBin;

    Uint8List content = await fetchFirmware(appState.connector.device);

    (applicationDat, applicationBin) = await unpackFirmware(content);

    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (_) {}

    flashFile(appState.communicator, appState, applicationDat, applicationBin,
        (progress) => appState.setProgressBar(progress / 100),
        firmwareZip: content);
  }

  Future<void> flashFirmwareZip(MyAppState appState) async {
    Uint8List applicationDat, applicationBin;

    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);

      (applicationDat, applicationBin) =
          await unpackFirmware(await file.readAsBytes());

      flashFile(appState.communicator, appState, applicationDat, applicationBin,
          (progress) => appState.setProgressBar(progress / 100),
          firmwareZip: await file.readAsBytes());
    }
  }

  // ignore_for_file: use_build_context_synchronously
  @override
  Widget build(BuildContext context) {
    var appState = context.read<MyAppState>();
    //var connection = ChameleonCom(port: appState.connector);

    return FutureBuilder(
        future: getFutureData(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Home'),
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            appState.connector.preformDisconnect();
            return Text('Error: ${snapshot.error.toString()}');
          } else {
            final (
              batteryIcon,
              usedSlots,
              fwVersion,
              isReaderDeviceMode,
            ) = snapshot.data;

            return Scaffold(
                appBar: AppBar(
                  title: const Text('Home'),
                ),
                body: Center(
                  child: Card(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center, // Center
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        // Disconnect
                                        appState.connector.preformDisconnect();
                                        appState.changesMade();
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(appState.connector.portName,
                                        style: const TextStyle(fontSize: 20)),
                                    Icon(appState.connector.connectionType ==
                                            ChameleonConnectType.ble
                                        ? Icons.bluetooth
                                        : Icons.usb),
                                    batteryIcon,
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                "Chameleon ${appState.connector.device == ChameleonDevice.ultra ? "Ultra" : "Lite"}",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize:
                                        MediaQuery.of(context).size.width /
                                            25)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text("Used Slots: $usedSlots/8",
                            style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width / 50)),
                        const SlotChanger(),
                        Expanded(
                          child: FractionallySizedBox(
                            widthFactor: 0.4,
                            child: Image.asset(
                              appState.connector.device == ChameleonDevice.ultra
                                  ? 'assets/black-ultra-standing-front.png'
                                  : 'assets/black-lite-standing-front.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Firmware Version: ",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize:
                                        MediaQuery.of(context).size.width /
                                            50)),
                            Text(fwVersion[0],
                                style: TextStyle(
                                    fontSize:
                                        MediaQuery.of(context).size.width /
                                            50)),
                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: IconButton(
                                onPressed: () async {
                                  SnackBar snackBar;
                                  String latestCommit;

                                  try {
                                    latestCommit = await latestAvailableCommit(
                                        appState.connector.device);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                    snackBar = SnackBar(
                                      content:
                                          Text('Update error: ${e.toString()}'),
                                      action: SnackBarAction(
                                        label: 'Close',
                                        onPressed: () {},
                                      ),
                                    );

                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(snackBar);
                                    return;
                                  }

                                  appState.log
                                      .i("Latest commit: $latestCommit");

                                  if (latestCommit.isEmpty) {
                                    return;
                                  }

                                  if (latestCommit.startsWith(fwVersion[1])) {
                                    snackBar = SnackBar(
                                      content: Text(
                                          'Your Chameleon ${appState.connector.device == ChameleonDevice.ultra ? "Ultra" : "Lite"} firmware is up to date'),
                                      action: SnackBarAction(
                                        label: 'Close',
                                        onPressed: () {},
                                      ),
                                    );

                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(snackBar);
                                  } else {
                                    snackBar = SnackBar(
                                      content: Text(
                                          'Downloading and preparing new Chameleon ${appState.connector.device == ChameleonDevice.ultra ? "Ultra" : "Lite"} firmware...'),
                                      action: SnackBarAction(
                                        label: 'Close',
                                        onPressed: () {
                                          ScaffoldMessenger.of(context)
                                              .hideCurrentSnackBar();
                                        },
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
                                        content: Text(
                                            'Update error: ${e.toString()}'),
                                        action: SnackBarAction(
                                          label: 'Close',
                                          onPressed: () {
                                            ScaffoldMessenger.of(context)
                                                .hideCurrentSnackBar();
                                          },
                                        ),
                                      );

                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(snackBar);
                                    }
                                  }
                                },
                                tooltip: "Check for updates",
                                icon: const Icon(Icons.update),
                              ),
                            )
                          ],
                        ),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Row(
                            children: [
                              const Spacer(),
                              (isReaderDeviceMode)
                                  ? Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: IconButton(
                                        onPressed: () async {
                                          await appState.communicator!
                                              .setReaderDeviceMode(false);
                                          setState(() {});
                                          appState.changesMade();
                                        },
                                        tooltip: "Go to emulator mode",
                                        icon: const Icon(Icons.nfc_sharp),
                                      ),
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: IconButton(
                                        onPressed: () async {
                                          await appState.communicator!
                                              .setReaderDeviceMode(true);
                                          setState(() {});
                                          appState.changesMade();
                                        },
                                        tooltip: "Go to reader mode",
                                        icon: const Icon(Icons.barcode_reader),
                                      ),
                                    ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: IconButton(
                                  onPressed: () => showDialog<String>(
                                      context: context,
                                      builder:
                                          (BuildContext dialogContext) =>
                                              FutureBuilder(
                                                  future: getSettingsData(),
                                                  builder: (BuildContext
                                                          context,
                                                      AsyncSnapshot snapshot) {
                                                    if (snapshot
                                                            .connectionState ==
                                                        ConnectionState
                                                            .waiting) {
                                                      return const AlertDialog(
                                                          title: Text(
                                                              'Device Settings'),
                                                          content:
                                                              CircularProgressIndicator());
                                                    } else if (snapshot
                                                        .hasError) {
                                                      appState.connector
                                                          .preformDisconnect();
                                                      return AlertDialog(
                                                          title: const Text(
                                                              'Device Settings'),
                                                          content: Text(
                                                              'Error: ${snapshot.error.toString()}'));
                                                    } else {
                                                      final (
                                                        animationMode,
                                                        aButtonMode,
                                                        bButtonMode
                                                      ) = snapshot.data;

                                                      return AlertDialog(
                                                        title: const Text(
                                                            'Device Settings'),
                                                        content: Column(
                                                          children: [
                                                            const Text(
                                                                "Firmware management:"),
                                                            const SizedBox(
                                                                height: 10),
                                                            TextButton(
                                                                onPressed:
                                                                    () async {
                                                                  await appState
                                                                      .communicator!
                                                                      .enterDFUMode();
                                                                  appState
                                                                      .connector
                                                                      .preformDisconnect();
                                                                  Navigator.pop(
                                                                      dialogContext,
                                                                      'Cancel');
                                                                  appState
                                                                      .changesMade();
                                                                },
                                                                child:
                                                                    const Row(
                                                                  children: [
                                                                    Icon(Icons
                                                                        .medical_services_outlined),
                                                                    Text(
                                                                        "Enter DFU Mode"),
                                                                  ],
                                                                )),
                                                            ...(appState.connector
                                                                        .connectionType !=
                                                                    ChameleonConnectType
                                                                        .ble)
                                                                ? [
                                                                    TextButton(
                                                                        onPressed:
                                                                            () async {
                                                                          Navigator.pop(
                                                                              dialogContext,
                                                                              'Cancel');
                                                                          var snackBar =
                                                                              SnackBar(
                                                                            content:
                                                                                Text('Downloading and preparing new Chameleon ${appState.connector.device == ChameleonDevice.ultra ? "Ultra" : "Lite"} firmware...'),
                                                                            action:
                                                                                SnackBarAction(
                                                                              label: 'Close',
                                                                              onPressed: () {},
                                                                            ),
                                                                          );

                                                                          ScaffoldMessenger.of(context)
                                                                              .showSnackBar(snackBar);
                                                                          try {
                                                                            await flashFirmware(appState);
                                                                          } catch (e) {
                                                                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                                                            snackBar =
                                                                                SnackBar(
                                                                              content: Text('Update error: ${e.toString()}'),
                                                                              action: SnackBarAction(
                                                                                label: 'Close',
                                                                                onPressed: () {},
                                                                              ),
                                                                            );

                                                                            ScaffoldMessenger.of(context).showSnackBar(snackBar);
                                                                          }
                                                                        },
                                                                        child:
                                                                            const Row(
                                                                          children: [
                                                                            Icon(Icons.system_security_update),
                                                                            Text("Flash latest FW via DFU"),
                                                                          ],
                                                                        )),
                                                                    TextButton(
                                                                        onPressed:
                                                                            () async {
                                                                          Navigator.pop(
                                                                              dialogContext,
                                                                              'Cancel');
                                                                          await flashFirmwareZip(
                                                                              appState);
                                                                        },
                                                                        child:
                                                                            const Row(
                                                                          children: [
                                                                            Icon(Icons.system_security_update_good),
                                                                            Text("Flash .zip FW via DFU"),
                                                                          ],
                                                                        ))
                                                                  ]
                                                                : [],
                                                            const SizedBox(
                                                                height: 10),
                                                            const Text(
                                                                "Animations:"),
                                                            const SizedBox(
                                                                height: 10),
                                                            ToggleButtonsWrapper(
                                                                items: const [
                                                                  'Full',
                                                                  'Mini',
                                                                  'None'
                                                                ],
                                                                selectedValue:
                                                                    animationMode
                                                                        .value,
                                                                onChange: (int
                                                                    index) async {
                                                                  var animation =
                                                                      AnimationSetting
                                                                          .full;
                                                                  if (index ==
                                                                      1) {
                                                                    animation =
                                                                        AnimationSetting
                                                                            .minimal;
                                                                  } else if (index ==
                                                                      2) {
                                                                    animation =
                                                                        AnimationSetting
                                                                            .none;
                                                                  }

                                                                  await appState
                                                                      .communicator!
                                                                      .setAnimationMode(
                                                                          animation);
                                                                  await appState
                                                                      .communicator!
                                                                      .saveSettings();
                                                                  setState(
                                                                      () {});
                                                                  appState
                                                                      .changesMade();
                                                                }),
                                                            const SizedBox(
                                                                height: 10),
                                                            const Text(
                                                                "Button config:"),
                                                            const SizedBox(
                                                                height: 7),
                                                            const Text(
                                                                "A button:",
                                                                textScaleFactor:
                                                                    0.8),
                                                            const SizedBox(
                                                                height: 7),
                                                            ToggleButtonsWrapper(
                                                                items: const [
                                                                  'Disable',
                                                                  'Forward',
                                                                  'Backward',
                                                                  'Clone UID'
                                                                ],
                                                                selectedValue:
                                                                    aButtonMode
                                                                        .value,
                                                                onChange: (int
                                                                    index) async {
                                                                  var mode =
                                                                      ButtonPress
                                                                          .disable;
                                                                  if (index ==
                                                                      1) {
                                                                    mode = ButtonPress
                                                                        .cycleForward;
                                                                  } else if (index ==
                                                                      2) {
                                                                    mode = ButtonPress
                                                                        .cycleBackward;
                                                                  } else if (index ==
                                                                      3) {
                                                                    mode = ButtonPress
                                                                        .cloneUID;
                                                                  }

                                                                  await appState
                                                                      .communicator!
                                                                      .setButtonConfig(
                                                                          ButtonType
                                                                              .a,
                                                                          mode);
                                                                  await appState
                                                                      .communicator!
                                                                      .saveSettings();
                                                                  setState(
                                                                      () {});
                                                                  appState
                                                                      .changesMade();
                                                                }),
                                                            const SizedBox(
                                                                height: 7),
                                                            const Text(
                                                                "B button:",
                                                                textScaleFactor:
                                                                    0.8),
                                                            const SizedBox(
                                                                height: 7),
                                                            ToggleButtonsWrapper(
                                                                items: const [
                                                                  'Disable',
                                                                  'Forward',
                                                                  'Backward',
                                                                  'Clone UID'
                                                                ],
                                                                selectedValue:
                                                                    bButtonMode
                                                                        .value,
                                                                onChange: (int
                                                                    index) async {
                                                                  var mode =
                                                                      ButtonPress
                                                                          .disable;
                                                                  if (index ==
                                                                      1) {
                                                                    mode = ButtonPress
                                                                        .cycleForward;
                                                                  } else if (index ==
                                                                      2) {
                                                                    mode = ButtonPress
                                                                        .cycleBackward;
                                                                  } else if (index ==
                                                                      3) {
                                                                    mode = ButtonPress
                                                                        .cloneUID;
                                                                  }

                                                                  await appState
                                                                      .communicator!
                                                                      .setButtonConfig(
                                                                          ButtonType
                                                                              .b,
                                                                          mode);
                                                                  await appState
                                                                      .communicator!
                                                                      .saveSettings();
                                                                  setState(
                                                                      () {});
                                                                  appState
                                                                      .changesMade();
                                                                }),
                                                            const SizedBox(
                                                                height: 10),
                                                            const Text(
                                                                "Other:"),
                                                            const SizedBox(
                                                                height: 10),
                                                            TextButton(
                                                                onPressed:
                                                                    () async {
                                                                  await appState
                                                                      .communicator!
                                                                      .resetSettings();
                                                                  Navigator.pop(
                                                                      dialogContext,
                                                                      'Cancel');
                                                                  appState
                                                                      .changesMade();
                                                                },
                                                                child:
                                                                    const Row(
                                                                  children: [
                                                                    Icon(Icons
                                                                        .lock_reset),
                                                                    Text(
                                                                        "Reset settings"),
                                                                  ],
                                                                )),
                                                            TextButton(
                                                                onPressed:
                                                                    () async {
                                                                  // Ask for confirmation
                                                                  Navigator.pop(
                                                                      dialogContext,
                                                                      'Cancel');
                                                                  showDialog(
                                                                    context:
                                                                        context,
                                                                    builder: (BuildContext
                                                                            context) =>
                                                                        AlertDialog(
                                                                      title: const Text(
                                                                          'Factory reset'),
                                                                      content:
                                                                          const Text(
                                                                              'Are you sure you want to factory reset your Chameleon?'),
                                                                      actions: <Widget>[
                                                                        TextButton(
                                                                          onPressed:
                                                                              () async {
                                                                            await appState.communicator!.factoryReset();
                                                                            await appState.connector.preformDisconnect();
                                                                            Navigator.pop(context,
                                                                                'Cancel');
                                                                            appState.changesMade();
                                                                          },
                                                                          child:
                                                                              const Text('Yes'),
                                                                        ),
                                                                        TextButton(
                                                                          onPressed: () => Navigator.pop(
                                                                              context,
                                                                              'Cancel'),
                                                                          child:
                                                                              const Text('No'),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  );
                                                                },
                                                                child:
                                                                    const Row(
                                                                  children: [
                                                                    Icon(Icons
                                                                        .restore_from_trash_outlined),
                                                                    Text(
                                                                        "Factory reset"),
                                                                  ],
                                                                )),
                                                          ],
                                                        ),
                                                        actions: <Widget>[
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context,
                                                                    'Cancel'),
                                                            child: const Text(
                                                                'Cancel'),
                                                          ),
                                                        ],
                                                      );
                                                    }
                                                  })),
                                  icon: const Icon(Icons.settings),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ));
          }
        });
  }
}
