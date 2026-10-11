import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/mobile/widgets/helpers.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Shown while the device is in DFU mode (firmware flashing). Navigation is
/// hidden, like on desktop, so the update can't be interrupted by accident.
class MobileDfuPage extends StatelessWidget {
  const MobileDfuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final isUltra = appState.connector!.device == ChameleonDevice.ultra;
    final model = chameleonDeviceName(ChameleonDevice.ultra);

    return Scaffold(
      appBar: AppBar(title: const Text('Chameleon DFU')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            LinearProgressIndicator(value: appState.progress),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: Image.asset(
                          appState.easterEgg
                              ? (isUltra
                                    ? 'assets/black-ultra-standing-front-flashing.webp'
                                    : 'assets/black-lite-standing-front-flashing.webp')
                              : deviceImageAsset(isUltra),
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        appState.easterEgg
                            ? localizations.chameleon_flashing_title_easter_egg(
                                model,
                              )
                            : localizations.chameleon_flashing_title(model),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        localizations.please_wait,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
