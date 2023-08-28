import 'dart:typed_data';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State

    return FutureBuilder(
      future: appState.connector.connected
          ? Future.value([])
          : appState.connector.availableChameleons(false),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
              appBar: AppBar(
                title: Text(AppLocalizations.of(context)!.connect),
              ),
              body: const Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError) {
          appState.connector.performDisconnect();
          return Text('${AppLocalizations.of(context)!.error}: ${snapshot.error}');
        } else {
          final (result as List<Chameleon>) = snapshot.data;

          return Scaffold(
            appBar: AppBar(
              title: Text(AppLocalizations.of(context)!.connect),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, // Center
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: () {
                        // Refresh
                        appState.changesMade();
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  Expanded(
                    child: GridView(
                        padding: const EdgeInsets.all(20),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1,
                        ),
                        scrollDirection: Axis.vertical,
                        children: [
                          ...result.map<Widget>((chameleonDevice) {
                            return ElevatedButton(
                              onPressed: () async {
                                if (chameleonDevice.dfu) {
                                  showDialog<String>(
                                    context: context,
                                    builder: (BuildContext context) =>
                                        AlertDialog(
                                      title: Text(
                                          AppLocalizations.of(context)!.chamaleon_is_dfu),
                                      content: Text(
                                          AppLocalizations.of(context)!.firmware_is_corrupted),
                                      actions: <Widget>[
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, AppLocalizations.of(context)!.cancel),
                                          child: Text(AppLocalizations.of(context)!.cancel),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.pop(context, AppLocalizations.of(context)!.flash);
                                            appState.changesMade();
                                            Uint8List applicationDat,
                                                applicationBin;

                                            Uint8List content =
                                                await fetchFirmware(
                                                    chameleonDevice.device);

                                            (applicationDat, applicationBin) =
                                                await unpackFirmware(content);

                                            flashFile(
                                                null,
                                                appState,
                                                applicationDat,
                                                applicationBin,
                                                (progress) =>
                                                    appState.setProgressBar(
                                                        progress / 100),
                                                enterDFU: false);

                                            appState.changesMade();
                                          },
                                          child: Text(AppLocalizations.of(context)!.flash),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  await appState.connector
                                      .connectSpecificDevice(
                                          chameleonDevice.port);
                                  appState.communicator = ChameleonCommunicator(
                                      port: appState.connector);
                                  appState.changesMade();
                                }
                              },
                              style: ButtonStyle(
                                shape: MaterialStateProperty.all<
                                    RoundedRectangleBorder>(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18.0),
                                  ),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: FittedBox(
                                      alignment: Alignment.centerRight,
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment
                                            .end, // Align the inner Row's children to the right
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              chameleonDevice.type ==
                                                      ConnectionType.ble
                                                  ? const Icon(Icons.bluetooth)
                                                  : const Icon(Icons.usb),
                                              Text(chameleonDevice.port ?? ""),
                                              if (chameleonDevice.dfu)
                                                Text(AppLocalizations.of(context)!.dfu),
                                            ],
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                  FittedBox(
                                      alignment: Alignment.topRight,
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: [
                                          Text(
                                              "Chameleon ${(chameleonDevice.device == ChameleonDevice.ultra) ? 'Ultra' : 'Lite'}",
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 20)),
                                        ],
                                      )),
                                  const SizedBox(height: 8),
                                  Expanded(
                                      flex: 1,
                                      child: Image.asset(
                                        chameleonDevice.device ==
                                                ChameleonDevice.ultra
                                            ? 'assets/black-ultra-standing-front.png'
                                            : 'assets/black-lite-standing-front.png',
                                        fit: BoxFit.fitHeight,
                                      )),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            );
                          }).toList(),
                        ]),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}
