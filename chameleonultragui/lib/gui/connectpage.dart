import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
                        print(appState.chameleon.availableDevices());
                        appState.chameleon.connected = true;
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
                    for (var i = 0; i < appState.chameleon.availableDevices().length; i++)
                      ElevatedButton(
                        onPressed: () {
                          // Connect here
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
                  ]
              ),
            ),
          ],
        ),
      ),
    );
  }
}