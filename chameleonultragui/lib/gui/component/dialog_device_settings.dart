

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'toggle_buttons.dart';

class DeviceSettingsData {
  AnimationSetting animationMode;
  ButtonPress aButtonMode;
  ButtonPress bButtonMode;

  DeviceSettingsData({
    required this.animationMode,
    required this.aButtonMode,
    required this.bButtonMode
  });
}

class DialogDeviceSettings extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback? onEnterDFUMode;
  final VoidCallback? onFirmwareUpdateLatest;
  final VoidCallback? onFirmwareUpdateFromZip;
  final VoidCallback? onResetSettings;
  final VoidCallback? onResetFactorySettings;
  final DeviceSettingsData deviceSettings;
  final Function(AnimationSetting animation)? onUpdateAnimation;
  final Function(ButtonType buttonType, ButtonPress mode)? onUpdateButtonMode;

  const DialogDeviceSettings({
    super.key,
    required this.deviceSettings,
    required this.onClose,
    this.onEnterDFUMode,
    this.onFirmwareUpdateLatest,
    this.onFirmwareUpdateFromZip,
    this.onResetSettings,
    this.onResetFactorySettings,
    this.onUpdateAnimation,
    this.onUpdateButtonMode
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
            ToggleButtonsWrapper(
              items: const [
                'Full',
                'Mini',
                'None'
              ],
              selectedValue:
                  deviceSettings.animationMode.value,
              onChange: (int index) async {
                var animation =
                    AnimationSetting.full;
                if (index == 1) {
                  animation =
                      AnimationSetting.minimal;
                } else if (index == 2) {
                  animation = AnimationSetting.none;
                }

                onUpdateAnimation!(animation);
              },
            ),
          if (onUpdateAnimation != null)
            const SizedBox(height: 10),
          if (onUpdateButtonMode != null)
            const Text(
                "Button config:"),
          if (onUpdateButtonMode != null)
            const SizedBox(height: 7),
          if (onUpdateButtonMode != null)
            const Text("A button:",
                textScaleFactor: 0.8),
          if (onUpdateButtonMode != null)
            const SizedBox(height: 7),
          if (onUpdateButtonMode != null)
            ToggleButtonsWrapper(
                items: const [
                  'Disable',
                  'Forward',
                  'Backward',
                  'Clone UID'
                ],
                selectedValue:
                    deviceSettings.aButtonMode.value,
                onChange:
                    (int index) async {
                  var mode = ButtonPress
                      .disable;
                  if (index == 1) {
                    mode = ButtonPress
                        .cycleForward;
                  } else if (index ==
                      2) {
                    mode = ButtonPress
                        .cycleBackward;
                  } else if (index ==
                      3) {
                    mode = ButtonPress
                        .cloneUID;
                  }

                  onUpdateButtonMode!(ButtonType.a, mode);
                }),
          if (onUpdateButtonMode != null)
            const SizedBox(height: 7),
          if (onUpdateButtonMode != null)
            const Text("B button:",
                textScaleFactor: 0.8),
          if (onUpdateButtonMode != null)
            const SizedBox(height: 7),
          if (onUpdateButtonMode != null)
            ToggleButtonsWrapper(
                items: const [
                  'Disable',
                  'Forward',
                  'Backward',
                  'Clone UID'
                ],
                selectedValue:
                    deviceSettings.bButtonMode.value,
                onChange:
                    (int index) async {
                  var mode = ButtonPress
                      .disable;
                  if (index == 1) {
                    mode = ButtonPress
                        .cycleForward;
                  } else if (index ==
                      2) {
                    mode = ButtonPress
                        .cycleBackward;
                  } else if (index ==
                      3) {
                    mode = ButtonPress
                        .cloneUID;
                  }

                  onUpdateButtonMode!(ButtonType.b, mode);
                }),
          if (onUpdateButtonMode != null)
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
              )
          ),
          TextButton(
            onPressed: () async {
              onResetFactorySettings!();
            },
            child: const Row(
              children: [
                Icon(Icons
                    .restore_from_trash_outlined),
                Text(
                    "Factory reset"),
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
