import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';

class HomePage extends StatelessWidget {
  // Home Page
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // Center
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              onPressed: () {
                // Disconnect
                appState.chameleon.performDisconnect();
                appState.changesMade();
              },
              icon: const Icon(Icons.close),
            ),
          ),
          const Text('Chameleon Ultra GUI'), // Display dummy / debug info
          Text('Platform: ${Platform.operatingSystem}'),
          Text('Android: ${appState.onAndroid}'),
          Text('Serial protocol : ${appState.chameleon}'),
          Text('Serial devices: ${appState.chameleon.availableDevices()}'),
          Text('Chameleon connected: ${appState.chameleon.connected}'),
          Text('Chameleon device type: ${appState.chameleon.device}'),
          ElevatedButton(
            // Connect Button
            onPressed: () {
              appState.chameleon.preformConnection();
              appState.changesMade();
            },
            child: const Text('Connect'),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () {
              appState.chameleon.sendCommand("test");
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

