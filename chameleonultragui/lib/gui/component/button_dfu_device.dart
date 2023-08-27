import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:flutter/material.dart';

class ButtonDfuDevice extends StatelessWidget {
  final Chameleon devicePort;
  final Function(bool fromZipFile)? onFirmwareUpdate;

  const ButtonDfuDevice({
    super.key, 
    required this.devicePort,
    this.onFirmwareUpdate
  }); 

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
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
                      Icon(
                        devicePort.type == ConnectionType.ble
                          ? Icons.bluetooth
                          : Icons.usb,
                        color: Theme.of(context).primaryColor
                      ),
                      Text(devicePort.port, style: TextStyle(color: Theme.of(context).primaryColor)),
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
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                      devicePort.device.name,
                      style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                ],
              )),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
            child: ListTile(
              leading: Icon(Icons.warning, color: theme.colorScheme.error),
              title: const Text('Chameleon is in DFU mode', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                'If the device never exits DFU mode by itself, then the firmware is probably corrupt',
                style: TextStyle(fontSize: 12)
              ),
              tileColor: theme.colorScheme.errorContainer,
              textColor: theme.colorScheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.0),
              )
            )
          ),
          Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Image.asset(
                      devicePort.device == ChameleonDevice.unknown
                        ? 'assets/black-both-standing-front.png'
                        : devicePort.device == ChameleonDevice.ultra
                        ? 'assets/black-ultra-standing-front.png'
                        : 'assets/black-lite-standing-front.png',
                      fit: BoxFit.fitHeight,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          FilledButton(
                            onPressed: () async {
                              await onFirmwareUpdate!(false);
                            },
                            child: const Text('Flash latest firmware')
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: () async {
                              await onFirmwareUpdate!(true);
                            },
                            child: const Text('Flash firmware from .zip')
                          )
                        ]
                      )
                    ),
                  ]
                )
              ),
            ),
        ],
      )
    );
  }
}