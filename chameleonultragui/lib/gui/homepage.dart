import 'dart:io';
import 'dart:typed_data';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:toggle_switch/toggle_switch.dart';

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

  Future<
      (
        Icon,
        List<Icon>,
        String,
        List<String>,
        String,
        int,
        bool,
        ChameleonAnimation
      )> getFutureData() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);
    List<bool> usedSlots = await connection.getUsedSlots();
    return (
      await getBatteryChargeIcon(connection),
      await getSlotIcons(connection, selectedSlot, usedSlots),
      await getUsedSlotsOut8(connection, usedSlots),
      await getFWversion(connection),
      await getRamusage(connection),
      await getActivatedSlot(connection),
      await isReaderDeviceMode(connection),
      await getAnimationMode(connection),
    );
  }

  Future<Icon> getBatteryChargeIcon(ChameleonCom connection) async {
    int charge = await connection.getBatteryCharge();
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

  Future<List<Icon>> getSlotIcons(
      ChameleonCom connection, int selectedSlot, List<bool> usedSlots) async {
    await connection.activateSlot(selectedSlot - 1);
    List<Icon> icons = [];
    for (int i = 1; i < 9; i++) {
      if (i == selectedSlot) {
        icons.add(const Icon(
          Icons.circle_outlined,
          color: Colors.red,
        ));
      } else if (usedSlots[i - 1]) {
        icons.add(const Icon(Icons.circle));
      } else {
        icons.add(const Icon(Icons.circle_outlined));
      }
    }
    return icons;
  }

  Future<String> getUsedSlotsOut8(
      ChameleonCom connection, List<bool> usedSlots) async {
    int usedSlotsOut8 = 0;
    for (int i = 0; i < 8; i++) {
      if (usedSlots[i]) {
        usedSlotsOut8++;
      }
    }
    return usedSlotsOut8.toString();
  }

  Future<List<String>> getFWversion(ChameleonCom connection) async {
    String commitHash = "";
    String firmwareVersion =
        numToVerCode(await connection.getFirmwareVersion());

    try {
      commitHash = await connection.getGitCommitHash();
    } catch (_) {}

    if (commitHash.isEmpty) {
      commitHash = "Outdated FW";
    }

    return ["$firmwareVersion ($commitHash)", commitHash];
  }

  Future<String> getRamusage(ChameleonCom connection) async {
    return await connection.getMemoryUsage();
  }

  Future<int> getActivatedSlot(ChameleonCom connection) async {
    return await connection.getActivatedSlot();
  }

  Future<bool> isReaderDeviceMode(ChameleonCom connection) async {
    return await connection.isReaderDeviceMode();
  }

  Future<ChameleonAnimation> getAnimationMode(ChameleonCom connection) async {
    try {
      return await connection.getAnimationMode();
    } catch (_) {
      return ChameleonAnimation.full;
    }
  }

  Future<void> flashFirmware(MyAppState appState) async {
    var connection = ChameleonCom(port: appState.connector);
    Uint8List applicationDat, applicationBin;

    Uint8List content = await fetchFirmware(appState.connector.device);

    (applicationDat, applicationBin) = await unpackFirmware(content);

    flashFile(connection, appState, applicationDat, applicationBin,
        (progress) => appState.setProgressBar(progress / 100),
        firmwareZip: content);
  }

  Future<void> flashFirmwareZip(MyAppState appState) async {
    var connection = ChameleonCom(port: appState.connector);
    Uint8List applicationDat, applicationBin;

    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);

      (applicationDat, applicationBin) =
          await unpackFirmware(await file.readAsBytes());

      flashFile(connection, appState, applicationDat, applicationBin,
          (progress) => appState.setProgressBar(progress / 100),
          firmwareZip: await file.readAsBytes());
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<MyAppState>();

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
              slotIcons,
              usedSlots,
              fwVersion,
              ramUsage,
              slot,
              isReaderDeviceMode,
              animationMode
            ) = snapshot.data;
            // selectedSlot = slot;

            return Scaffold(
              appBar: AppBar(
                title: const Text('Home'),
              ),
              body: Center(
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
                                    MediaQuery.of(context).size.width / 25)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text("Used Slots: $usedSlots/8",
                        style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width / 50)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () async {
                            if (selectedSlot > 1) {
                              selectedSlot--;
                            }
                            setState(() {});
                            appState.changesMade();
                          },
                          icon: const Icon(Icons.arrow_back),
                        ),
                        ...slotIcons,
                        IconButton(
                          onPressed: () async {
                            if (selectedSlot < 8) {
                              selectedSlot++;
                            }
                            setState(() {});
                            appState.changesMade();
                          },
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
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
                                    MediaQuery.of(context).size.width / 50)),
                        Text(fwVersion[0],
                            style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width / 50)),
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: IconButton(
                            onPressed: () async {
                              var snackBar;
                              var latestCommit;

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
                                    content:
                                        Text('Update error: ${e.toString()}'),
                                    action: SnackBarAction(
                                      label: 'Close',
                                      onPressed: () {},
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
                    // Row(
                    //   mainAxisAlignment: MainAxisAlignment.center,
                    //   children: [
                    //     Text("Memory Usage: ",
                    //         style: TextStyle(
                    //             fontWeight: FontWeight.bold,
                    //             fontSize:
                    //                 MediaQuery.of(context).size.width / 50)),
                    //     Text(ramUsage,
                    //         style: TextStyle(
                    //             fontSize:
                    //                 MediaQuery.of(context).size.width / 50)),
                    //   ],
                    // ),
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
                                      var connection = ChameleonCom(
                                          port: appState.connector);
                                      await connection
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
                                      var connection = ChameleonCom(
                                          port: appState.connector);
                                      await connection
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
                                builder: (BuildContext dialogContext) =>
                                    AlertDialog(
                                  title: const Text('Device Settings'),
                                  content: Column(
                                    children: [
                                      const Text("Firmware management:"),
                                      const SizedBox(height: 10),
                                      TextButton(
                                          onPressed: () async {
                                            var connection = ChameleonCom(
                                                port: appState.connector);
                                            await connection.enterDFUMode();
                                            appState.connector
                                                .preformDisconnect();
                                            Navigator.pop(
                                                dialogContext, 'Cancel');
                                            appState.changesMade();
                                          },
                                          child: const Row(
                                            children: [
                                              Icon(Icons.medical_services),
                                              Text("Enter DFU Mode"),
                                            ],
                                          )),
                                      ...(appState.connector.connectionType !=
                                              ChameleonConnectType.ble)
                                          ? [
                                              TextButton(
                                                  onPressed: () async {
                                                    Navigator.pop(dialogContext,
                                                        'Cancel');
                                                    var snackBar = SnackBar(
                                                      content: Text(
                                                          'Downloading and preparing new Chameleon ${appState.connector.device == ChameleonDevice.ultra ? "Ultra" : "Lite"} firmware...'),
                                                      action: SnackBarAction(
                                                        label: 'Close',
                                                        onPressed: () {},
                                                      ),
                                                    );

                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(snackBar);
                                                    try {
                                                      await flashFirmware(
                                                          appState);
                                                    } catch (e) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .hideCurrentSnackBar();
                                                      snackBar = SnackBar(
                                                        content: Text(
                                                            'Update error: ${e.toString()}'),
                                                        action: SnackBarAction(
                                                          label: 'Close',
                                                          onPressed: () {},
                                                        ),
                                                      );

                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              snackBar);
                                                    }
                                                  },
                                                  child: const Row(
                                                    children: [
                                                      Icon(Icons
                                                          .system_security_update),
                                                      Text(
                                                          "Flash latest FW via DFU"),
                                                    ],
                                                  )),
                                              TextButton(
                                                  onPressed: () async {
                                                    Navigator.pop(dialogContext,
                                                        'Cancel');
                                                    await flashFirmwareZip(
                                                        appState);
                                                  },
                                                  child: const Row(
                                                    children: [
                                                      Icon(Icons
                                                          .system_security_update_good),
                                                      Text(
                                                          "Flash .zip FW via DFU"),
                                                    ],
                                                  ))
                                            ]
                                          : [],
                                      const SizedBox(height: 10),
                                      const Text("Animations:"),
                                      const SizedBox(height: 10),
                                      ToggleSwitch(
                                        minWidth: 70.0,
                                        cornerRadius: 10.0,
                                        activeFgColor: Colors.white,
                                        inactiveBgColor: Colors.grey,
                                        inactiveFgColor: Colors.white,
                                        initialLabelIndex: animationMode.value,
                                        totalSwitches: 3,
                                        labels: const ['Full', 'Mini', 'None'],
                                        radiusStyle: true,
                                        onToggle: (index) async {
                                          var animation =
                                              ChameleonAnimation.full;
                                          if (index == 1) {
                                            animation =
                                                ChameleonAnimation.minimal;
                                          } else if (index == 2) {
                                            animation = ChameleonAnimation.none;
                                          }

                                          var connection = ChameleonCom(
                                              port: appState.connector);
                                          await connection
                                              .setAnimationMode(animation);
                                          await connection.saveSettings();
                                          setState(() {});
                                          appState.changesMade();
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      const Text("Other:"),
                                      const SizedBox(height: 10),
                                      TextButton(
                                          onPressed: () async {
                                            var connection = ChameleonCom(
                                                port: appState.connector);
                                            await connection.resetSettings();
                                            Navigator.pop(
                                                dialogContext, 'Cancel');
                                            appState.changesMade();
                                          },
                                          child: const Row(
                                            children: [
                                              Icon(Icons.lock_reset),
                                              Text("Reset settings"),
                                            ],
                                          )),
                                    ],
                                  ),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, 'Cancel'),
                                      child: const Text('Cancel'),
                                    ),
                                  ],
                                ),
                              ),
                              icon: const Icon(Icons.settings),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        });
  }
}
