import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FlashingPage extends StatelessWidget {
  const FlashingPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
        appBar: AppBar(
          title: const Text('Chameleon DFU'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                appState.connector.device == ChameleonDevice.ultra
                    ? appState.easterEgg
                        ? 'assets/black-ultra-standing-front-flashing.png'
                        : 'assets/black-ultra-standing-front.png'
                    : appState.easterEgg
                        ? 'assets/black-lite-standing-front-flashing.png'
                        : 'assets/black-lite-standing-front.png',
                width: 300,
                height: 300,
              ),
              const SizedBox(height: 20),
              Text(
                appState.easterEgg
                    ? 'Your ${appState.connector.deviceName} is flashing'
                    : 'Installing firmware on your ${appState.connector.deviceName}',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Please wait...',
                style: TextStyle(fontSize: 20),
              ),
            ],
          ),
        ));
  }
}
