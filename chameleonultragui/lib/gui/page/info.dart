import 'dart:io';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({Key? key}) : super(key: key);

  @override
  InfoPageState createState() => InfoPageState();
}

class InfoPageState extends State<InfoPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.watch<ChameleonGUIState>();
    return Scaffold(
      body: Column(
        children: [
          Center(child: 
            AlertDialog(title: Text("Hardware Info"),
                    content: Text("● ${localizations.platform} -> ${Platform.operatingSystem}\n● ${AppLocalizations.of(context)!.serial_protocol} -> ${appState.connector}\n● ${AppLocalizations.of(context)!.chameleon_connected} -> ${appState.connector!.connected}\n● ${AppLocalizations.of(context)!.chameleon_device_type} -> ${appState.connector!.device}\n● ${AppLocalizations.of(context)!.shared_preferences_logging} -> ${appState.sharedPreferencesProvider.isDebugLogging()} with ${appState.sharedPreferencesProvider.getLogLines().length} lines")),
          ),
        ],
      ),
    );
  }
}
