import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../comms/serial_abstract.dart';
import '../main.dart';

class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () {
                  // Refresh
                  appState.changesMade();
                },
                icon: const Icon(Icons.refresh),
              ),
            ),
            Expanded(
              child: GridView(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  scrollDirection: Axis.vertical,
                  children: [
                    // "Add" Button for Bluetooth
                    ElevatedButton(
                      onPressed: () {
                        showDialog<String>(context: context, builder: (BuildContext context) => const AlertDialog(content: Text('Identifies as BLE Dialog'),),);
                        // Connect via BLE here
                        appState.chameleon.connected = true; // Bypass / Dummy for testing
                        appState.changesMade();
                      },
                      style: ButtonStyle(
                        shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                      ),
                      child: const Icon(Icons.add),
                    ),
                    for (var i = 0; i < appState.chameleon.availableChameleons().length; i++)
                      ElevatedButton(
                        onPressed: () {
                          // Connect here
                          appState.chameleon.connectSpecific(appState.chameleon.availableChameleons()[i]['port']);
                          appState.changesMade();
                        },
                        style: ButtonStyle(
                          shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18.0),
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  const Icon(Icons.usb),
                                  Text(appState.chameleon.availableChameleons()[i]['port']),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Text("Chameleon ${appState.chameleon.availableChameleons()[i]['device'] == ChameleonDevice.ultra ? 'Ultra' : 'Lite'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: FractionallySizedBox(
                                widthFactor: 0.4,
                                child: Image.asset(appState.chameleon.availableChameleons()[i]['device'] == ChameleonDevice.ultra ? 'assets/black-ultra-standing-front.png' : 'assets/black-lite-standing-front.png', fit: BoxFit.contain,),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ]
              ),
            ),
          ],
        ),
      ),
    );
  }
}