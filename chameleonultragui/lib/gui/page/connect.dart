import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/dialogs/manual_connect.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    return FutureBuilder(
      future: (appState.connector!.connected ||
              appState.connector!.pendingConnection)
          ? Future.value([])
          : appState.connector!.availableChameleons(false),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
              appBar: AppBar(
                title: Text(localizations.connect),
              ),
              body: const Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError) {
          appState.connector!.performDisconnect();
          return Scaffold(
              appBar: AppBar(
                title: Text(localizations.connect),
              ),
              body: ErrorPage(errorMessage: snapshot.error.toString()));
        } else {
          final (result as List<Chameleon>) = snapshot.data;

          if (result.isEmpty && appState.connector is AndroidSerial) {
            final androidSerial = appState.connector as AndroidSerial;
            if (!androidSerial.hasAllPermissions) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                var scaffoldMessenger = ScaffoldMessenger.of(context);
                var localizations = AppLocalizations.of(context)!;
                SnackBar snackBar = SnackBar(
                  content: Text(localizations.android_ble_permissions_missing),
                  action: SnackBarAction(
                    label: localizations.close,
                    onPressed: () {},
                  ),
                );

                scaffoldMessenger.hideCurrentSnackBar();
                scaffoldMessenger.showSnackBar(snackBar);
              });
            }
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(localizations.connect),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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

                                            scaffoldMessenger
                                                .hideCurrentSnackBar();

                                            var snackBar = SnackBar(
                                              content: Text(
                                                  localizations.downloading_fw(
                                                      chameleonDeviceName(
                                                          chameleonDevice
                                                              .device))),
                                              action: SnackBarAction(
                                                label: localizations.close,
                                                onPressed: () {
                                                  scaffoldMessenger
                                                      .hideCurrentSnackBar();
                                                },
                                              ),
                                            );

                                            scaffoldMessenger
                                                .showSnackBar(snackBar);

                                            await flashFirmware(appState,
                                                scaffoldMessenger:
                                                    scaffoldMessenger,
                                                device: chameleonDevice.device,
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
                                    appState.connector!.pendingConnection =
                                        true;
                                    appState.changesMade();
                                  }
                                  await appState.connector!
                                      .connectSpecificDevice(
                                          chameleonDevice.port);
                                  appState.communicator = ChameleonCommunicator(
                                      appState.log!,
                                      port: appState.connector);
                                  appState.connector!.pendingConnection = false;
                                  appState.changesMade();
                                }
                              },
                              style: ButtonStyle(
                                shape: WidgetStateProperty.all<
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
                                              "Chameleon ${chameleonDeviceName(chameleonDevice.device)}",
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
                                            ? 'assets/black-ultra-standing-front.webp'
                                            : 'assets/black-lite-standing-front.webp',
                                        fit: BoxFit.fitHeight,
                                      )),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            );
                          }),
                        ]),
                  ),
                  if (appState.connector!.isManualConnectionSupported())
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Row(
                        children: [
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: IconButton(
                              onPressed: () => showDialog<String>(
                                  context: context,
                                  builder: (BuildContext dialogContext) =>
                                      const ManualConnect()),
                              icon: const Icon(Icons.add),
                            ),
                          ),
                        ],
                      ),
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
