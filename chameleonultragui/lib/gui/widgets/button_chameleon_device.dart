import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:flutter/material.dart';

class ButtonChameleonDevice extends StatelessWidget {
  final ChameleonDevicePort devicePort;
  final VoidCallback onSelectDevice;

  const ButtonChameleonDevice({
    super.key,
    required this.devicePort,
    required this.onSelectDevice,
  }); 

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        onSelectDevice();
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
                      devicePort.type ==
                        ChameleonConnectType.ble
                          ? const Icon(Icons.bluetooth)
                          : const Icon(Icons.usb),
                      Text(devicePort.port),
                      if (devicePort.type ==
                        ChameleonConnectType.dfu)
                          const Text(" (DFU)"),
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
                      devicePort.device.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                ],
              )),
          const SizedBox(height: 8),
          Expanded(
              flex: 1,
              child: Image.asset(
                devicePort.device == ChameleonDevice.unknown
                  ? 'assets/black-both-standing-front.png'
                  : devicePort.device == ChameleonDevice.ultra
                  ? 'assets/black-ultra-standing-front.png'
                  : 'assets/black-lite-standing-front.png',
                fit: BoxFit.fitHeight,
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}