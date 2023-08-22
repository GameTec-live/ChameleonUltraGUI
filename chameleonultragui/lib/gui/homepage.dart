
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:sizer_pro/sizer.dart';

import 'components/dialog_device_settings.dart';
import 'features/flash_firmware_latest.dart';
import 'features/flash_firmware_zip.dart';
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

  Future<(bool, Icon, String, List<String>, bool, ChameleonAnimation)>
      getFutureData() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);
    List<(ChameleonTag, ChameleonTag)> usedSlots;
    try {
      usedSlots = await connection.getUsedSlots();
    } catch (_) {
      usedSlots = [];
    }

    var getIsChameleonUltra = Future.value(appState.connector.device == ChameleonDevice.ultra);
    if (appState.onWeb) {
      // Serial on Web doesnt provide device/manufacture names, so detect the device type instead
      getIsChameleonUltra = detectChameleonUltra(connection).then((isChameleonUltra) {
        // Also update device type in SerialConnection
        appState.connector.device = isChameleonUltra ? ChameleonDevice.ultra : ChameleonDevice.lite;
        return isChameleonUltra;
      });
    }

    return (
      await getIsChameleonUltra,
      await getBatteryChargeIcon(connection),
      await getUsedSlotsOut8(connection, usedSlots),
      await getFWversion(connection),
      await isReaderDeviceMode(connection),
      await getAnimationMode(connection),
    );
  }

  Future<bool> detectChameleonUltra(ChameleonCom connection) async {
    return await connection.detectChameleonUltra();
  }

  Future<Icon> getBatteryChargeIcon(ChameleonCom connection) async {
    int charge = 0;
    try {
      (_, charge) = await connection.getBatteryCharge();
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

  Future<String> getUsedSlotsOut8(ChameleonCom connection,
      List<(ChameleonTag, ChameleonTag)> usedSlots) async {
    int usedSlotsOut8 = 0;

    if (usedSlots.isNotEmpty) {
      for (int i = 0; i < 8; i++) {
        if (usedSlots[i].$1 != ChameleonTag.unknown ||
            usedSlots[i].$2 != ChameleonTag.unknown) {
          usedSlotsOut8++;
        }
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

  @override
  Widget build(BuildContext context) {
    var appState = context.read<MyAppState>();
    //var connection = ChameleonCom(port: appState.connector);

    return FutureBuilder(
        future: getFutureData(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            appState.log.e('Error ${snapshot.error}', snapshot.error);
            appState.connector.performDisconnect();
            return Text('Error: ${snapshot.error.toString()}');
          } else {
            final (
              isChameleonUltra,
              batteryIcon,
              usedSlots,
              fwVersion,
              isReaderDeviceMode,
              animationMode
            ) = snapshot.data;

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
                                  onPressed: () async {
                                    // Disconnect
                                    await appState.connector.performDisconnect();
                                    appState.changesMade();
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                              ]
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(appState.connector.portName,
                                    style: const TextStyle(fontSize: 20)),
                                IconButton(
                                  onPressed: null,
                                  padding: EdgeInsets.zero,
                                  disabledColor: Theme.of(context).textTheme.bodyLarge!.color,
                                  icon: Icon(appState.connector.connectionType ==
                                          ChameleonConnectType.ble
                                      ? Icons.bluetooth
                                      : Icons.usb),
                                ),
                                batteryIcon
                              ]
                            )
                          ]
                        )
                      )
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                            appState.connector.deviceName,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: SizerUtil.width / 25)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text("Used Slots: $usedSlots/8",
                        style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width / 50)),
                    const SlotChanger(),
                    Expanded(
                      child: FractionallySizedBox(
                        widthFactor: 0.4,
                        child: Image.asset(
                          isChameleonUltra
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
                              SnackBar snackBar;
                              String latestCommit;

                              var scaffoldMessenger = ScaffoldMessenger.of(context);

                              try {
                                latestCommit = await latestAvailableCommit(
                                    appState.connector.device);
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

                              if (latestCommit.startsWith(fwVersion[1])) {
                                snackBar = SnackBar(
                                  content: Text(
                                      'Your ${appState.connector.deviceName} firmware is up to date'),
                                  showCloseIcon: true,
                                );

                                scaffoldMessenger.showSnackBar(snackBar);
                              } else {
                                var message = 'Downloading and preparing new ${appState.connector.deviceName} firmware...';
                                if (appState.onWeb) {
                                  message = 'Your ${appState.connector.deviceName} firmware is out of date! Automatic updating is not supported on web, download manually and then update by clicking on the Settings icon';
                                }

                                snackBar = SnackBar(
                                  content: Text(message),
                                  showCloseIcon: true,
                                );

                                scaffoldMessenger.showSnackBar(snackBar);

                                if (!appState.onWeb) {
                                  try {
                                    await flashFirmwareLatest(appState);
                                  } catch (e) {
                                    scaffoldMessenger.hideCurrentSnackBar();
                                    snackBar = SnackBar(
                                      content:
                                          Text('Update error: ${e.toString()}'),
                                      showCloseIcon: true,
                                    );

                                    scaffoldMessenger
                                        .showSnackBar(snackBar);
                                  }
                                }
                              }
                            },
                            tooltip: "Check for updates",
                            icon: const Icon(Icons.update),
                          ),
                        )
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isChameleonUltra)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: IconButton(
                              onPressed: () async {
                                var connection = ChameleonCom(
                                    port: appState.connector);
                                await connection.setReaderDeviceMode(!isReaderDeviceMode);
                                setState(() {});
                                appState.changesMade();
                              },
                              tooltip: isReaderDeviceMode ? 'Go to emulator mode' : 'Go to reader mode',
                              icon: Icon(isReaderDeviceMode ? Icons.nfc_sharp : Icons.barcode_reader),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: IconButton(
                            onPressed: () => showDialog<String>(
                              context: context,
                              builder: (BuildContext dialogContext) {
                                onClose() {
                                  Navigator.pop(dialogContext, 'Cancel');
                                }

                                var scaffoldMessenger = ScaffoldMessenger.of(context);
                                var connection = ChameleonCom(port: appState.connector);

                                var canUpdateLatest = !kIsWeb && appState.connector.connectionType != ChameleonConnectType.ble;
                                var canUpdateZip = canUpdateLatest;

                                return DialogDeviceSettings(
                                  currentAnimation: animationMode,
                                  onClose: onClose,
                                  onEnterDFUMode: () async {
                                    onClose();

                                    await connection.enterDFUMode();
                                    await appState.connector.performDisconnect();
                                    await asyncSleep(500);
                                    appState.changesMade();
                                  },
                                  onResetSettings: () async {
                                    await connection.resetSettings();
                                    onClose();
                                    appState.changesMade();
                                  },
                                  onUpdateAnimation: (animation) async {
                                    await connection.setAnimationMode(animation);
                                    await connection.saveSettings();

                                    setState(() {});
                                    appState.changesMade();
                                  },
                                  onFirmwareUpdateLatest: !canUpdateLatest ? null : () async {
                                    onClose();

                                    var snackBar = SnackBar(
                                      content: Text(
                                          'Downloading and preparing new ${appState.connector.deviceName} firmware...'),
                                      showCloseIcon: true,
                                    );

                                    scaffoldMessenger.showSnackBar(snackBar);
                                    try {
                                      await flashFirmwareLatest(appState);
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
                                      await flashFirmwareZip(appState);
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
                            ),
                            icon: const Icon(Icons.settings),
                            tooltip: 'Device Settings',
                          ),
                        )
                      ]
                    )
                  ],
                ),
              ),
            );
          }
        });
  }
}
