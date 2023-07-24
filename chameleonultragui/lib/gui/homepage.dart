import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:chameleonultragui/connector/dfu.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/connector/chameleon.dart';
import 'package:chameleonultragui/comms/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';

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

  Future<(Icon, List<Icon>, String, String, String)> getFutureData() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.chameleon);
    List<bool> usedSlots = await connection.getUsedSlots();
    return (
      await getBatteryChargeIcon(connection),
      await getSlotIcons(connection, selectedSlot, usedSlots),
      await getUsedSlotsOut8(connection, usedSlots),
      await getFWversion(connection),
      await getRamusage(connection),
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
    await connection.activateSlot(selectedSlot);
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

  Future<String> getFWversion(ChameleonCom connection) async {
    int fwv = await connection.getFirmwareVersion();
    return fwv.toString();
  }

  Future<String> getRamusage(ChameleonCom connection) async {
    return await connection.getMemoryUsage();
  }

  Future<void> flashFirmware(MyAppState appState) async {
    var connection = ChameleonCom(port: appState.chameleon);
    List files = [null, null];
    final releases = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
        .body
        .toString());
    Uint8List content = Uint8List(0);
    for (var file in releases[0]["assets"]) {
      if (file["name"] ==
          "${(appState.chameleon.device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app.zip") {
        content = await http.readBytes(Uri.parse(file["browser_download_url"]));
        break;
      }
    }

    if (content.isEmpty) {
      return;
    }

    final archive = ZipDecoder().decodeBytes(content);
    for (var file in archive.files) {
      if (file.isFile) {
        if (file.name == "application.dat") {
          files[0] = file;
        } else if (file.name == "application.bin") {
          files[1] = file;
        }
      }
    }
    await connection.enterDFUMode();
    await appState.chameleon.performDisconnect();
    await asyncSleep(2000);
    appState.chameleon.connectSpecific(
        (await appState.chameleon.availableChameleons(true))[0]['port']);
    var dfu = ChameleonDFU(port: appState.chameleon);
    await dfu.setPRN();
    await dfu.getMTU();
    await dfu.flashFirmware(0x01, files[0].content);
    await dfu.flashFirmware(0x02, files[1].content);
    appState.log.i("Firmware flashed!");
    appState.chameleon.performDisconnect();
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
            return Text('Error: ${snapshot.error}');
          } else {
            final (batteryIcon, slotIcons, usedSlots, fwVersion, ramUsage) =
                snapshot.data;

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
                                    appState.chameleon.performDisconnect();
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
                                Text(appState.chameleon.portName,
                                    style: const TextStyle(fontSize: 20)),
                                Icon(appState.chameleon.connectionType ==
                                        ChameleonConnectType.usb
                                    ? Icons.usb
                                    : Icons.bluetooth),
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
                            "Chameleon ${appState.chameleon.device == ChameleonDevice.ultra ? "Ultra" : "Lite"}",
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
                          onPressed: () {
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
                          onPressed: () {
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
                          appState.chameleon.device == ChameleonDevice.ultra
                              ? 'assets/black-ultra-standing-front.png'
                              : 'assets/black-lite-standing-front.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Firmware Version: ",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize:
                                    MediaQuery.of(context).size.width / 50)),
                        Text(fwVersion,
                            style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width / 50)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Memory Usage: ",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize:
                                    MediaQuery.of(context).size.width / 50)),
                        Text(ramUsage,
                            style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width / 50)),
                      ],
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: IconButton(
                              onPressed: () => showDialog<String>(
                                context: context,
                                builder: (BuildContext context) => AlertDialog(
                                  title: const Text('Device Settings'),
                                  content: Center(
                                    child: Column(
                                      children: [
                                        const Text("Flash Firmware"),
                                        const Text("Wipe Device"),
                                        TextButton(
                                            onPressed: () async {
                                              var appState =
                                                  context.read<MyAppState>();
                                              var connection = ChameleonCom(
                                                  port: appState.chameleon);
                                              await connection.enterDFUMode();
                                              appState.chameleon
                                                  .performDisconnect();
                                            },
                                            child: const Row(
                                              children: [
                                                Icon(Icons.system_update),
                                                Text("Enter DFU Mode"),
                                              ],
                                            )),
                                        TextButton(
                                            onPressed: () async {
                                              await flashFirmware(appState);
                                            },
                                            child: const Row(
                                              children: [
                                                Icon(Icons.system_update),
                                                Text("Flash latest FW via DFU"),
                                              ],
                                            ))
                                      ],
                                    ),
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
