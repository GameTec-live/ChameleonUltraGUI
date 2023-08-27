import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/card_web_pair_devices.dart';
import 'package:chameleonultragui/gui/component/button_chameleon_device.dart';
import 'package:chameleonultragui/gui/component/button_dfu_device.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/component/helpers/confirm_http_proxy.dart';
import 'package:chameleonultragui/gui/features/firmware_flasher.dart';
import 'package:chameleonultragui/helpers/files.dart';
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
    var scaffoldMessenger = ScaffoldMessenger.of(context);

    var connector = appState.connector;

    return FutureBuilder<List<Chameleon>>(
      future: connector.connected
          ? Future.value([])
          : connector.availableChameleons(false),
      builder: (BuildContext context, AsyncSnapshot<List<Chameleon>> snapshot) {
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
                child: 
                  kIsWeb && result!.isEmpty
                  ? Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 300,
                        child: CardWebPairDevices(onPairDevices: () async {
                          await connector.pairDevices();
                          appState.changesMade();
                        })
                      ),
                    )
                  : GridView(
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
                        ...result.map<Widget>((chameleonDevice) {
                          if (chameleonDevice.dfu) {
                            return ButtonDfuDevice(
                              devicePort: chameleonDevice,
                              onFirmwareUpdate: (fromZipFile) async {
                                try {
                                  if (fromZipFile) {
                                    FileResult? file = await pickFile(appState);
                                    if (file == null) {
                                      appState.log.d("Empty file picked");
                                      return;
                                    }

                                    var flasher = FirmwareFlasher.fromZipFile(connector, file.bytes);
                                    await connector.connectSpecificDevice(chameleonDevice.port);
                                    await flasher.flash((progressUpdate) => appState.setFlashProgress(progressUpdate));
                                  } else {
                                    if (context.mounted) {
                                      final canContinue = await confirmHttpProxy(context, appState.sharedPreferencesProvider);
                                      if (canContinue == false) {
                                        return;
                                      }
                                    }

                                    var flasher = FirmwareFlasher.fromGithubNightly(connector);
                                    await connector.connectSpecificDevice(chameleonDevice.port);
                                    await flasher.flash((progressUpdate) => appState.setFlashProgress(progressUpdate));
                                  }
                                } catch (e) {
                                  appState.log.e(e);
                                  await appState.connector.performDisconnect();

                                  var snackBar = SnackBar(
                                    content: Text('Update error: ${e.toString()}'),
                                    showCloseIcon: true,
                                  );

                                  scaffoldMessenger.hideCurrentSnackBar();
                                  scaffoldMessenger.showSnackBar(snackBar);
                                } finally {
                                  appState.changesMade();
                                }
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
                      ]
                    ),
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
