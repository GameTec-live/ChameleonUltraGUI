

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'toggle_buttons.dart';

class DeviceSettingsData {
  AnimationSetting animationMode;
  ButtonConfig aButtonMode;
  ButtonConfig bButtonMode;
  ButtonConfig aLongButtonMode;
  ButtonConfig bLongButtonMode;

  DeviceSettingsData({
    required this.animationMode,
    required this.aButtonMode,
    required this.bButtonMode,
    required this.aLongButtonMode,
    required this.bLongButtonMode,
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
  final Function(ButtonType buttonType, ButtonConfig mode)? onUpdateButtonMode;
  final Function(ButtonType buttonType, ButtonConfig mode)? onUpdateLongButtonMode;

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
    this.onUpdateButtonMode,
    this.onUpdateLongButtonMode
  }); 

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Device Settings'),
      
      content: SingleChildScrollView(
        child: Column(
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
                child: Text('After entering DFU mode, pair the new DFU device (if needed) and select an update method', style: TextStyle(fontSize: 12)),
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
              ...[
                const Text(
                    "Button config:"),
                const SizedBox(height: 7),
                const Text("A button:",
                    textScaleFactor: 0.8),
                const SizedBox(height: 7),
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
                      var mode = ButtonConfig
                          .disable;
                      if (index == 1) {
                        mode = ButtonConfig.cycleForward;
                      } else if (index ==
                          2) {
                        mode = ButtonConfig.cycleBackward;
                      } else if (index ==
                          3) {
                        mode = ButtonConfig.cloneUID;
                      }

                      onUpdateButtonMode!(ButtonType.a, mode);
                    }),
                const SizedBox(height: 7),
                const Text("B button:",
                  textScaleFactor: 0.8),
                const SizedBox(height: 7),
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
                      var mode = ButtonConfig.disable;
                      if (index == 1) {
                        mode = ButtonConfig.cycleForward;
                      } else if (index ==
                          2) {
                        mode = ButtonConfig.cycleBackward;
                      } else if (index ==
                          3) {
                        mode = ButtonConfig.cloneUID;
                      }

                      onUpdateButtonMode!(ButtonType.b, mode);
                    }),
                const SizedBox(height: 7),
                const Text("Long press", textScaleFactor: 0.9),
                const SizedBox(height: 7),
                const Text("A button:", textScaleFactor: 0.8),
                const SizedBox(height: 7),
                ToggleButtonsWrapper(
                    items: const [
                      'Disable',
                      'Forward',
                      'Backward',
                      'Clone UID'
                    ],
                    selectedValue: deviceSettings.aLongButtonMode.value,
                    onChange: (int index) async {
                      var mode = ButtonConfig.disable;
                      if (index == 1) {
                        mode = ButtonConfig.cycleForward;
                      } else if (index == 2) {
                        mode = ButtonConfig.cycleBackward;
                      } else if (index == 3) {
                        mode = ButtonConfig.cloneUID;
                      }

                      onUpdateLongButtonMode!(ButtonType.a, mode);
                    }),
                const SizedBox(height: 7),
                const Text("B button:", textScaleFactor: 0.8),
                const SizedBox(height: 7),
                ToggleButtonsWrapper(
                    items: const [
                      'Disable',
                      'Forward',
                      'Backward',
                      'Clone UID'
                    ],
                    selectedValue: deviceSettings.bLongButtonMode.value,
                    onChange: (int index) async {
                      var mode = ButtonConfig.disable;
                      if (index == 1) {
                        mode = ButtonConfig.cycleForward;
                      } else if (index == 2) {
                        mode = ButtonConfig.cycleBackward;
                      } else if (index == 3) {
                        mode = ButtonConfig.cloneUID;
                      }

                      onUpdateLongButtonMode!(ButtonType.b, mode);
                    }),
                const SizedBox(height: 10),
              ],
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
