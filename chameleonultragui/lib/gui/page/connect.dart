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
    var appState = context.watch<ChameleonState>(); // Get State
    var localizations = AppLocalizations.of(context)!;
    return FutureBuilder(
      future:
          (appState.connector.connected || appState.connector.pendingConnection)
              ? Future.value([])
              : appState.connector.availableChameleons(false),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
              appBar: AppBar(
                title: Text(localizations.connect),
              ),
              body: const Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError) {
          appState.connector.performDisconnect();
          return Text('${localizations.error}: ${snapshot.error}');
        } else {
          final (result as List<Chameleon>) = snapshot.data;

          return Scaffold(
            appBar: AppBar(
              title: Text(localizations.connect),
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
                                      title:
                                          Text(localizations.chameleon_is_dfu),
                                      content: Text(
                                          localizations.firmware_is_corrupted),
                                      actions: <Widget>[
                                        TextButton(
                                          onPressed: () => Navigator.pop(
                                              context, localizations.cancel),
                                          child: Text(localizations.cancel),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.pop(
                                                context, localizations.flash);
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
                                          child: Text(localizations.flash),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  if (chameleonDevice.type ==
                                      ConnectionType.ble) {
                                    appState.connector.pendingConnection = true;
                                    appState.changesMade();
                                  }
                                  await appState.connector
                                      .connectSpecificDevice(
                                          chameleonDevice.port);
                                  appState.communicator = ChameleonCommunicator(
                                      port: appState.connector);
                                  appState.connector.pendingConnection = false;
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
                                                Text(localizations.dfu),
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
