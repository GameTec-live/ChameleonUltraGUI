import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class FlashingPage extends StatelessWidget {
  const FlashingPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
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
                appState.connector!.device == ChameleonDevice.ultra
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
                    ? localizations.chameleon_flashing_title_easter_egg(
                        chameleonDeviceName(ChameleonDevice.ultra))
                    : localizations.chameleon_flashing_title(
                        chameleonDeviceName(ChameleonDevice.ultra)),
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                localizations.please_wait,
                style: const TextStyle(fontSize: 20),
              ),
            ],
          ),
        ));
  }
}
