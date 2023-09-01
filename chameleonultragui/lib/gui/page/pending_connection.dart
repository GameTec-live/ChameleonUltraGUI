import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class PendingConnectionPage extends StatelessWidget {
  const PendingConnectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonState>();
    var localizations = AppLocalizations.of(context)!;

    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.connect),
        ),
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 25),
          Text(
            localizations.connecting_to_ble,
          ),
          const SizedBox(height: 10),
          if (!appState.connector.connected) ...[
            Text(
              localizations.default_ble_password,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              localizations.connection_might_take_some_time,
              style: const TextStyle(fontWeight: FontWeight.bold),
            )
          ],
        ])));
  }
}
