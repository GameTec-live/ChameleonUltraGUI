import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/features/flash_firmware_zip.dart';
import 'package:chameleonultragui/gui/widgets/card_web_pair_devices.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/flash_firmware_latest.dart';
import 'widgets/button_chameleon_device.dart';
import 'widgets/button_dfu_device.dart';

class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State

    var connector = appState.connector;

    return FutureBuilder<List<ChameleonDevicePort>>(
      future: connector.connected
          ? Future.value([])
          : connector.availableChameleons(false),
      builder: (BuildContext context, AsyncSnapshot<List<ChameleonDevicePort>> snapshot) {
        Widget? page;

        if (snapshot.connectionState == ConnectionState.waiting) {
          page = const CircularProgressIndicator();
        } else if (snapshot.hasError) {
          appState.log.e('${snapshot.error}', snapshot.error, snapshot.stackTrace);
          connector.performDisconnect();

          page = Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: ${snapshot.error}')
            ]
          );
        } else if (snapshot.hasData) {
          final result = snapshot.data;

          page = Column(
            mainAxisAlignment: MainAxisAlignment.center, // Center
            children: [
              Expanded(
                child: GridView(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: result!.isEmpty ? 1 : calculateCrossAxisCount(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1,
                    ),
                    scrollDirection: Axis.vertical,
                    children: [
                      if (result!.isEmpty)
                        Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 300,
                            child: CardWebPairDevices(onPairDevices: () async {
                              await appState.connector.pairDevices();
                              appState.changesMade();
                            })
                          ),
                        ),
                      ...result.map<Widget>((chameleonDevice) {
                        if (chameleonDevice.type == ChameleonConnectType.dfu) {
                          return ButtonDfuDevice(
                            devicePort: chameleonDevice,
                            onFirmwareUpdate: (fromZipFile) async {
                              await appState.connector.connectSpecific(chameleonDevice.port);

                              if (fromZipFile) {
                                await flashFirmwareZip(appState);
                              } else {
                                await flashFirmwareLatest(appState);
                              }

                              // Give the device some time to restart/reconnect
                              await asyncSleep(250);

                              appState.changesMade();
                            },
                          );
                        }

                        return ButtonChameleonDevice(
                          devicePort: chameleonDevice,
                          onSelectDevice: () async {
                            await connector.connectSpecific(chameleonDevice.port);
                            appState.changesMade();
                          }
                        );
                      }),
                    ]),
              ),
            ],
          );
        }

        return Scaffold(
              appBar: AppBar(
                title: const Text('Connect'),
                actions: [
                  if (appState.onWeb)
                    IconButton(
                      onPressed: () async {
                        // Refresh
                        await connector.pairDevices();
                        appState.changesMade();
                      },
                      icon: const Icon(Icons.handshake_outlined),
                      tooltip: "Pair devices",
                    ),
                  IconButton(
                    onPressed: () {
                      // Refresh
                      appState.changesMade();
                    },
                    icon: const Icon(Icons.refresh),
                    tooltip: "Refresh devices",
                  ),
                ],
              ),
              body: Center(child: page),
        );
      },
    );
  }
}
