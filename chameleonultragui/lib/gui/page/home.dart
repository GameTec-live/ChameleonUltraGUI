import 'package:chameleonultragui/gui/menu/chameleon_settings.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/gui/component/slot_changer.dart';
import 'dart:math';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int selectedSlot = 1;
  bool isLegacyFirmware = false;

  @override
  void initState() {
    super.initState();
  }

  Future<((Icon, BatteryCharge), String, List<String>, bool)>
      getFutureData() async {
    var appState = context.read<ChameleonGUIState>();
    List<SlotTypes> slotTypes = [];
    try {
      slotTypes = await appState.communicator!.getSlotTagTypes();
    } catch (e) {
      appState.log!.e(e);
    }

    return (
      await getBatteryInfo(),
      await getUsedSlotsOut8(slotTypes),
      await getVersion(),
      await isReaderDeviceMode()
    );
  }

  Future<(Icon, BatteryCharge)> getBatteryInfo() async {
    var appState = context.read<ChameleonGUIState>();
    var icon = const Icon(Icons.battery_unknown);
    BatteryCharge battery = BatteryCharge(percent: 0, voltage: 0);

    try {
      battery = await appState.communicator!.getBatteryCharge();
    } catch (_) {}

    if (battery.percent > 98) {
      icon = const Icon(Icons.battery_full);
    } else if (battery.percent > 87) {
      icon = const Icon(Icons.battery_6_bar);
    } else if (battery.percent > 75) {
      icon = const Icon(Icons.battery_5_bar);
    } else if (battery.percent > 62) {
      icon = const Icon(Icons.battery_4_bar);
    } else if (battery.percent > 50) {
      icon = const Icon(Icons.battery_3_bar);
    } else if (battery.percent > 37) {
      icon = const Icon(Icons.battery_2_bar);
    } else if (battery.percent > 10) {
      icon = const Icon(Icons.battery_1_bar);
    } else if (battery.percent > 3) {
      icon = const Icon(Icons.battery_0_bar);
    } else if (battery.percent > 0) {
      icon = const Icon(Icons.battery_alert);
    }

    return (icon, battery);
  }

  Future<String> getUsedSlotsOut8(List<SlotTypes> slotTypes) async {
    int usedSlotsOut8 = 0;

    if (slotTypes.isEmpty) {
      return AppLocalizations.of(context)!.unknown;
    }

    for (int i = 0; i < 8; i++) {
      if (slotTypes[i].notMatch()) {
        usedSlotsOut8++;
      }
    }
    return usedSlotsOut8.toString();
  }

  Future<List<String>> getVersion() async {
    var appState = context.read<ChameleonGUIState>();
    String commitHash = "";
    var firmware = await appState.communicator!.getFirmwareVersion();
    isLegacyFirmware = firmware.legacyProtocol;
    String firmwareVersion = numToVerCode(firmware.version);

    try {
      commitHash = await appState.communicator!.getGitCommitHash();
    } catch (_) {}

    if (commitHash.isEmpty) {
      if (context.mounted) {
        commitHash = AppLocalizations.of(context)!.outdated_fw;
      } else {
        commitHash = "Outdated FW";
      }
    }

    if (context.mounted && isLegacyFirmware) {
      var localizations = AppLocalizations.of(context)!;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(localizations.outdated_protocol),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(localizations.outdated_protocol_description_1),
                  Text(localizations.outdated_protocol_description_2),
                  Text(localizations.outdated_protocol_description_3),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(localizations.update),
                onPressed: () async {
                  Navigator.of(context).pop();
                  var localizations = AppLocalizations.of(context)!;
                  var scaffoldMessenger = ScaffoldMessenger.of(context);
                  var snackBar = SnackBar(
                    content: Text(localizations.downloading_fw(
                        chameleonDeviceName(appState.connector!.device))),
                    action: SnackBarAction(
                      label: localizations.close,
                      onPressed: () {
                        scaffoldMessenger.hideCurrentSnackBar();
                      },
                    ),
                  );

                  scaffoldMessenger.showSnackBar(snackBar);
                  await flashFirmware(appState,
                      scaffoldMessenger: scaffoldMessenger);
                },
              ),
              TextButton(
                child: Text(localizations.skip),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }

    return ["$firmwareVersion ($commitHash)", commitHash];
  }

  Future<bool> isReaderDeviceMode() async {
    var appState = context.read<ChameleonGUIState>();
    return await appState.communicator!.isReaderDeviceMode();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    return FutureBuilder(
        future: getFutureData(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              body: const Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            appState.connector!.performDisconnect();
            return Text('${localizations.error}: ${snapshot.error.toString()}');
          } else {
            final (
              batteryInfo,
              usedSlots,
              fwVersion,
              isReaderDeviceMode,
            ) = snapshot.data;

            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                                    appState.connector!.performDisconnect();
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
                                Expanded(
                                    flex: 1,
                                    child: FittedBox(
                                        alignment: Alignment.centerRight,
                                        fit: BoxFit.scaleDown,
                                        child: Row(children: [
                                          Text(
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              appState.connector!.portName,
                                              style:
                                                  const TextStyle(fontSize: 20))
                                        ]))),
                                Icon(appState.connector!.connectionType ==
                                        ConnectionType.ble
                                    ? Icons.bluetooth
                                    : Icons.usb),
                                Tooltip(
                                  message: localizations.battery_info(
                                      batteryInfo.$2.percent,
                                      batteryInfo.$2.voltage),
                                  child: batteryInfo.$1,
                                ),
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
                            "Chameleon ${chameleonDeviceName(appState.connector!.device)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: min(
                                MediaQuery.of(context).size.width / 25,
                                MediaQuery.of(context).size.height / 20,
                              ),
                            )),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text("${localizations.used_slots}: $usedSlots/8",
                        style: TextStyle(
                          fontSize: min(
                            MediaQuery.of(context).size.width / 35,
                            MediaQuery.of(context).size.height / 20,
                          ),
                        )),
                    const FittedBox(
                        alignment: Alignment.center,
                        fit: BoxFit.scaleDown,
                        child: SlotChanger()),
                    Expanded(
                      child: FractionallySizedBox(
                        widthFactor: 0.4,
                        child: Image.asset(
                          appState.connector!.device == ChameleonDevice.ultra
                              ? 'assets/black-ultra-standing-front.webp'
                              : 'assets/black-lite-standing-front.webp',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("${localizations.firmware_version}: ",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: min(
                                MediaQuery.of(context).size.width / 50,
                                MediaQuery.of(context).size.height / 30,
                              ),
                            )),
                        Text(fwVersion[0],
                            style: TextStyle(
                              fontSize: min(
                                MediaQuery.of(context).size.width / 50,
                                MediaQuery.of(context).size.height / 30,
                              ),
                            )),
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: IconButton(
                            onPressed: () async {
                              SnackBar snackBar;
                              String latestCommit;

                              try {
                                latestCommit = await latestAvailableCommit(
                                    appState.connector!.device);
                              } catch (e) {
                                if (context.mounted) {
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
                                return;
                              }

                              try {
                                fwVersion[1] =
                                    await resolveCommit(fwVersion[1]);
                              } catch (_) {}

                              appState.log!.i(
                                  "Latest commit: $latestCommit, current commit ${fwVersion[1]}");

                              if (latestCommit.isEmpty) {
                                return;
                              }

                              if (latestCommit.startsWith(fwVersion[1]) &&
                                  context.mounted) {
                                snackBar = SnackBar(
                                  content: Text(localizations.up_to_date(
                                      chameleonDeviceName(
                                          appState.connector!.device))),
                                  action: SnackBarAction(
                                    label: localizations.close,
                                    onPressed: () {},
                                  ),
                                );

                                scaffoldMessenger.showSnackBar(snackBar);
                              } else if (context.mounted) {
                                snackBar = SnackBar(
                                  content: Text(localizations.downloading_fw(
                                      chameleonDeviceName(
                                          appState.connector!.device))),
                                  action: SnackBarAction(
                                    label: localizations.close,
                                    onPressed: () {
                                      scaffoldMessenger.hideCurrentSnackBar();
                                    },
                                  ),
                                );

                                scaffoldMessenger.showSnackBar(snackBar);
                                try {
                                  await flashFirmware(appState,
                                      scaffoldMessenger: scaffoldMessenger);
                                } catch (e) {
                                  if (context.mounted) {
                                    scaffoldMessenger.hideCurrentSnackBar();
                                    snackBar = SnackBar(
                                      content: Text(
                                          '${localizations.update_error}: ${e.toString()}'),
                                      action: SnackBarAction(
                                        label: localizations.close,
                                        onPressed: () {
                                          scaffoldMessenger
                                              .hideCurrentSnackBar();
                                        },
                                      ),
                                    );

                                    scaffoldMessenger.showSnackBar(snackBar);
                                  }
                                }
                              }
                            },
                            tooltip: localizations.check_updates,
                            icon: const Icon(Icons.update),
                          ),
                        ),
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
                                    tooltip: localizations.emulator_mode,
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
                                    tooltip: localizations.reader_mode,
                                    icon: const Icon(Icons.barcode_reader),
                                  ),
                                ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: IconButton(
                              onPressed: () => showDialog<String>(
                                  context: context,
                                  builder: (BuildContext dialogContext) =>
                                      const ChameleonSettings()),
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
