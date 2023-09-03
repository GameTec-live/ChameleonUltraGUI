import 'package:chameleonultragui/gui/menu/chameleon_settings.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
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
  var selectedSlot = 1;

  @override
  void initState() {
    super.initState();
  }

  Future<(Icon, String, List<String>, bool)> getFutureData() async {
    var appState = context.read<ChameleonGUIState>();
    List<(TagType, TagType)> usedSlots = [];
    try {
      usedSlots = await appState.communicator!.getUsedSlots();
    } catch (e) {
      appState.log!.e(e);
    }

    return (
      await getBatteryChargeIcon(),
      await getUsedSlotsOut8(usedSlots),
      await getVersion(),
      await isReaderDeviceMode()
    );
  }

  Future<Icon> getBatteryChargeIcon() async {
    var appState = context.read<ChameleonGUIState>();
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

  Future<String> getUsedSlotsOut8(List<(TagType, TagType)> usedSlots) async {
    int usedSlotsOut8 = 0;

    if (usedSlots.isEmpty) {
      return AppLocalizations.of(context)!.unknown;
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
    var appState = context.read<ChameleonGUIState>();
    String commitHash = "";
    String firmwareVersion =
        numToVerCode(await appState.communicator!.getFirmwareVersion());

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
    return FutureBuilder(
        future: getFutureData(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(
                title: Text(localizations.home),
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            appState.connector!.performDisconnect();
            return Text('${localizations.error}: ${snapshot.error.toString()}');
          } else {
            final (
              batteryIcon,
              usedSlots,
              fwVersion,
              isReaderDeviceMode,
            ) = snapshot.data;

            return Scaffold(
              appBar: AppBar(
                title: Text(localizations.home),
              ),
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
                                Text(appState.connector!.portName,
                                    style: const TextStyle(fontSize: 20)),
                                Icon(appState.connector!.connectionType ==
                                        ConnectionType.ble
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
                            "Chameleon ${appState.connector!.device == ChameleonDevice.ultra ? "Ultra" : "Lite"}",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize:
                                    min(
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
                                      ),)),
                    const SlotChanger(),
                    Expanded(
                      child: FractionallySizedBox(
                        widthFactor: 0.4,
                        child: Image.asset(
                          appState.connector!.device == ChameleonDevice.ultra
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
                        Text("${localizations.firmware_version}: ",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize:
                                  min(
                                    MediaQuery.of(context).size.width / 50,
                                    MediaQuery.of(context).size.height / 30,
                                      ),
                                    )),
                        Text(fwVersion[0],
                            style: TextStyle(
                                fontSize:
                                    min(
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
                                  ScaffoldMessenger.of(context)
                                      .hideCurrentSnackBar();
                                  snackBar = SnackBar(
                                    content: Text(
                                        '${localizations.update_error}: ${e.toString()}'),
                                    action: SnackBarAction(
                                      label: localizations.close,
                                      onPressed: () {},
                                    ),
                                  );

                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(snackBar);
                                }
                                return;
                              }

                              appState.log!.i("Latest commit: $latestCommit");

                              if (latestCommit.isEmpty) {
                                return;
                              }

                              if (latestCommit.startsWith(fwVersion[1]) &&
                                  context.mounted) {
                                snackBar = SnackBar(
                                  content: Text(localizations.up_to_date(
                                      appState.connector!.device ==
                                              ChameleonDevice.ultra
                                          ? "Ultra"
                                          : "Lite")),
                                  action: SnackBarAction(
                                    label: localizations.close,
                                    onPressed: () {},
                                  ),
                                );

                                ScaffoldMessenger.of(context)
                                    .showSnackBar(snackBar);
                              } else if (context.mounted) {
                                snackBar = SnackBar(
                                  content: Text(localizations.downloading_fw(
                                      appState.connector!.device ==
                                              ChameleonDevice.ultra
                                          ? "Ultra"
                                          : "Lite")),
                                  action: SnackBarAction(
                                    label: localizations.close,
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
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                    snackBar = SnackBar(
                                      content: Text(
                                          '${localizations.update_error}: ${e.toString()}'),
                                      action: SnackBarAction(
                                        label: localizations.close,
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
