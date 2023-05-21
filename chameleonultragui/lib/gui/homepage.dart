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
          Text('Chameleon Ultra GUI'), // Display dummy / debug info
          Text('Platform: ${Platform.operatingSystem}'),
          Text('Android: ${appState.onandroid}'),
          Text('Chameleon: ${appState.chameleon}'),
          Text('Serial Ports: ${appState.chameleon.availableDevices()}'),
          Text('Serial Port: ${appState.chameleon.port}'),
          Text('Device: ${appState.chameleon.device}'),
          ElevatedButton(
            // Connect Button
            onPressed: () {
              appState.chameleon
                  .connectDevice(appState.chameleon.availableDevices()[0]);
            },
            child: const Text('Connect'),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () {
              appState.chameleon.sendcommand("test");
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}