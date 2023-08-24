import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/card_web_pair_devices.dart';
import 'package:chameleonultragui/gui/component/button_chameleon_device.dart';
import 'package:chameleonultragui/gui/component/button_dfu_device.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/features/flash_firmware_latest.dart';
import 'package:chameleonultragui/gui/features/flash_firmware_zip.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          appState.log.e('${snapshot.error}', error: snapshot.error, stackTrace: snapshot.stackTrace);
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
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (kIsWeb)
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
                    ]
                  )
                )
              ),
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
                      if (result.isEmpty)
                        Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 300,
                            child: CardWebPairDevices(onPairDevices: () async {
                              await connector.pairDevices();
                              appState.changesMade();
                            })
                          ),
                        ),
                      ...result.map<Widget>((chameleonDevice) {
                        if (chameleonDevice.type == ConnectionType.dfu) {
                          return ButtonDfuDevice(
                            devicePort: chameleonDevice,
                            onFirmwareUpdate: (fromZipFile) async {
                              await connector.connectSpecificDevice(chameleonDevice.port);

                              if (fromZipFile) {
                                await flashFirmwareZip(appState);
                              } else {
                                await flashFirmwareLatest(appState);
                              }

                              // Give the device some time to restart/reconnect
                              await asyncSleep(500);

                              appState.changesMade();
                            },
                          );
                        }

                        return ButtonChameleonDevice(
                          devicePort: chameleonDevice,
                          onSelectDevice: () async {
                            await connector.connectSpecificDevice(chameleonDevice.port);
                            appState.communicator = ChameleonCommunicator(port: appState.connector);
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
              ),
              body: Center(child: page),
        );
      },
    );
  }
}
