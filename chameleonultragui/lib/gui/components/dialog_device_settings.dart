

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:toggle_switch/toggle_switch.dart';

class DialogDeviceSettings extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback? onEnterDFUMode;
  final VoidCallback? onFirmwareUpdateLatest;
  final VoidCallback? onFirmwareUpdateFromZip;
  final VoidCallback? onResetSettings;
  final ChameleonAnimation currentAnimation;
  final Function(ChameleonAnimation animation)? onUpdateAnimation;

  const DialogDeviceSettings({
    super.key,
    required this.currentAnimation,
    required this.onClose,
    this.onEnterDFUMode,
    this.onFirmwareUpdateLatest,
    this.onFirmwareUpdateFromZip,
    this.onResetSettings,
    this.onUpdateAnimation
  }); 

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Device Settings'),
      
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Firmware management:"),
          const SizedBox(height: 10),
          if (onFirmwareUpdateLatest != null)
            FilledButton(
              onPressed: () {
                onFirmwareUpdateLatest!();
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.system_security_update),
                  SizedBox(width: 8),
                  Text("Flash latest FW via DFU"),
                ],
              )
            ),
          if (onFirmwareUpdateLatest != null)
            const SizedBox(height: 8),
          if (onFirmwareUpdateFromZip != null)
            FilledButton(
              onPressed: () {
                onFirmwareUpdateFromZip!();
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons
                      .system_security_update_good),
                  SizedBox(width: 8),
                  Text(
                      "Flash .zip FW via DFU"),
                ],
              )
            ),
          if (onFirmwareUpdateFromZip != null)
            const SizedBox(height: 8),
          if (onEnterDFUMode != null)
            FilledButton(
              onPressed: () {
                onEnterDFUMode!();
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.medical_services),
                  SizedBox(width: 8),
                  Text("Enter DFU Mode"),
                ],
              )),
          if (kIsWeb)
            const SizedBox(height: 5),
          if (kIsWeb)
            const SizedBox(
              width: 300,
              child: Text('After entering DFU mode, pair the new DFU device (if needed) and select a download firmware zip', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 10),
          if (onUpdateAnimation != null)
            const Text("Animations:"),
          if (onUpdateAnimation != null)
            const SizedBox(height: 10),
          if (onUpdateAnimation != null)
            ToggleSwitch(
              minWidth: 70.0,
              cornerRadius: 10.0,
              activeFgColor: Colors.white,
              inactiveBgColor: Colors.grey,
              inactiveFgColor: Colors.white,
              initialLabelIndex: currentAnimation.value,
              totalSwitches: 3,
              labels: const ['Full', 'Mini', 'None'],
              radiusStyle: true,
              onToggle: (index) async {
                var animation =
                    ChameleonAnimation.full;
                if (index == 1) {
                  animation =
                      ChameleonAnimation.minimal;
                } else if (index == 2) {
                  animation = ChameleonAnimation.none;
                }

                onUpdateAnimation!(animation);
              },
            ),
          if (onUpdateAnimation != null)
            const SizedBox(height: 10),
          const Text("Other:"),
          const SizedBox(height: 10),
          TextButton(
              onPressed: () {
                onResetSettings!();
              },
              child: const Row(
                children: [
                  Icon(Icons.lock_reset),
                  Text("Reset settings"),
                ],
              )),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => onClose(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
