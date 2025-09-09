import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class ManualConnect extends StatefulWidget {
  const ManualConnect({super.key});

  @override
  State<ManualConnect> createState() => ManualConnectState();
}

class ManualConnectState extends State<ManualConnect> {
  TextEditingController portController = TextEditingController();
  ChameleonDevice type = ChameleonDevice.ultra;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.connect_manually),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: portController,
            decoration: InputDecoration(
              labelText: localizations.port,
              hintText: localizations.port_hint,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
            if (portController.text.isEmpty) {
              return;
            }

            await appState.connector!
                .connectSpecificDevice(portController.text);
            appState.communicator =
                ChameleonCommunicator(appState.log!, port: appState.connector);
            appState.connector!.pendingConnection = false;
            appState.changesMade();
          },
          child: Text(localizations.connect),
        )
      ],
    );
  }
}
