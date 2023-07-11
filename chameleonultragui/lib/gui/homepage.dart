import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../comms/serial_abstract.dart';
import '../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}
class HomePageState extends State<HomePage> {
  late Future<(Icon, List<Icon>, String, String, String)> dataFuture;

  @override
  void initState() {
    super.initState();
    dataFuture = getFutureData();
  }

  Future<(Icon, List<Icon>, String, String, String)> getFutureData() async {
    var appState = context.read<MyAppState>();
    return (
      await getBatteryChargeIcon(appState),
      await getSlotIcons(appState),
      await getUsedSlotsOut8(appState),
      await getFWversion(appState),
      await getRamusage(appState),
    );
  }


  Future<Icon> getBatteryChargeIcon(appState) async {
    int charge = await appState.chameleon.getBatteryCharge();
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

  Future<List<Icon>> getSlotIcons(appState) async {
    int selectedSlot = await appState.chameleon.getSelectedSlot();
    List<bool> usedSlots = await appState.chameleon.getUsedSlots();
    List<Icon> icons = [];
    for (int i = 0; i < 8; i++) {
      if (i == selectedSlot) {
        icons.add(const Icon(Icons.circle_outlined, color: Colors.red,));
      } else if (usedSlots[i]) {
        icons.add(const Icon(Icons.circle));
      } else {
        icons.add(const Icon(Icons.circle_outlined));
      }
    }
    return icons;
  }

  Future<String> getUsedSlotsOut8(appState) async {
    List<bool> usedSlots = await appState.chameleon.getUsedSlots();
    int usedSlotsOut8 = 0;
    for (int i = 0; i < 8; i++) {
      if (usedSlots[i]) {
        usedSlotsOut8++;
      }
    }
    return usedSlotsOut8.toString();
  }

  Future<String> getFWversion(appState) async {
    return await appState.chameleon.getFirmwareVersion();
  }

  Future<String> getRamusage(appState) async {
    return await appState.chameleon.getMemoryUsage();
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
              title: const Text('Home Page'),
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
                              Icon(appState.chameleon.usbConnected ? Icons.usb : Icons.bluetooth),
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
                          appState.chameleon.pressAbutton();
                          appState.changesMade();
                        },
                        icon: const Icon(Icons.arrow_back),
                      ),
                      ...slotIcons,
                      IconButton(
                        onPressed: () {
                          appState.chameleon.pressBbutton();
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
                                content: const Center(
                                  child: Column(
                                    children: [
                                      Text("Flash Firmware"),
                                      Text("Wipe Device"),
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
