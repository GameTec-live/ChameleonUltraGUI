import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/chameleon/connector.dart';
import 'package:chameleonultragui/comms/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}
class HomePageState extends State<HomePage> {
  late Future<(Icon, List<Icon>, String, String, String)> dataFuture;
  var selectedSlot = 1;

  @override
  void initState() {
    super.initState();
  }

  Future<(Icon, List<Icon>, String, String, String)> getFutureData() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.chameleon);
    List<bool> used_slots = await connection.getUsedSlots();
    return (
      await getBatteryChargeIcon(connection),
      await getSlotIcons(connection, selectedSlot, used_slots),
      await getUsedSlotsOut8(connection, used_slots),
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
    } else if (charge > 50)  {
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

  Future<List<Icon>> getSlotIcons(ChameleonCom connection, int selectedSlot, List<bool> usedSlots) async {
    await connection.activateSlot(selectedSlot);
    List<Icon> icons = [];
    for (int i = 1; i < 9; i++) {
      if (i == selectedSlot) {
        icons.add(const Icon(Icons.circle_outlined, color: Colors.red,));
      } else if (usedSlots[i-1]) {
        icons.add(const Icon(Icons.circle));
      } else {
        icons.add(const Icon(Icons.circle_outlined));
      }
    }
    return icons;
  }

  Future<String> getUsedSlotsOut8(ChameleonCom connection, List<bool> usedSlots) async {
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
          final (batteryIcon, slotIcons, usedSlots, fwVersion, ramUsage) = snapshot.data;

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
                              Text(appState.chameleon.portName,style: const TextStyle(fontSize: 20)),
                              Icon(appState.chameleon.connectionType == ChameleonConnectType.usb ? Icons.usb : Icons.bluetooth),
                              batteryIcon,
                            ],
                          ),

                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text("Chameleon ${appState.chameleon.device == ChameleonDevice.ultra ? "Ultra" : "Lite"}",style: TextStyle(fontWeight: FontWeight.bold, fontSize: MediaQuery.of(context).size.width / 25)),],
                  ),
                  const SizedBox(height: 20),
                  Text("Used Slots: $usedSlots/8",style: TextStyle(fontSize: MediaQuery.of(context).size.width / 50)),
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
                  Expanded(child: FractionallySizedBox(
                    widthFactor: 0.4,
                    child: Image.asset(appState.chameleon.device == ChameleonDevice.ultra ? 'assets/black-ultra-standing-front.png' : 'assets/black-lite-standing-front.png' , fit: BoxFit.contain,),
                  ),),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Firmware Version: ",style: TextStyle(fontWeight: FontWeight.bold, fontSize: MediaQuery.of(context).size.width / 50)),
                      Text(fwVersion,style: TextStyle(fontSize: MediaQuery.of(context).size.width / 50)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Memory Usage: ",style: TextStyle(fontWeight: FontWeight.bold, fontSize: MediaQuery.of(context).size.width / 50)),
                      Text(ramUsage,style: TextStyle(fontSize: MediaQuery.of(context).size.width / 50)),
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
                                content:  Center(
                                  child: Column(
                                    children: [
                                      const Text("Flash Firmware"),
                                      const Text("Wipe Device"),
                                      TextButton(
                                        onPressed: () async {
                                          var appState = context.read<MyAppState>();
                                          var connection = ChameleonCom(port: appState.chameleon);
                                          await connection.enterDFUMode();
                                          // TODO: Make this cleaner, app freezes
                                        },
                                        child: const Row(
                                          children: [
                                            Icon(Icons.system_update),
                                            Text("Enter DFU Mode"),
                                          ],
                                        )
                                      )
                                    ],
                                  ),
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, 'Cancel'),
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
      }
    );
  }
}
