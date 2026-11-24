import 'package:chameleonultragui/gui/component/connection_status.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class PendingConnectionPage extends StatelessWidget {
  const PendingConnectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.connect)),
      body: ConnectionStatus(
        connected: appState.connector!.connected,
        connecting: !appState.connector!.connected,
      ),
    );
  }
}
