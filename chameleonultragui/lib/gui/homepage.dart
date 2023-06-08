import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:chameleonultragui/chameleon/connector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';

class HomePage extends StatelessWidget {
  // Home Page
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State
    var cml = ChameleonCom(port: appState.chameleon);

    return Center( // Todo: Implement Homepage
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
          const CircularProgressIndicator.adaptive(),
        ]
      ),
    );
  }
}
