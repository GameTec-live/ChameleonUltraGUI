import 'dart:async';
import 'dart:io';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const _winrtChannel = MethodChannel('flutter_blue_plus/methods');
final _handledPorts = <String>{};

/// Pairs the connected Chameleon when the device reports that BLE pairing is
/// enabled and no bond exists yet. The PIN is never stored by the app.
Future<void> ensureBlePairing(
  BuildContext context,
  ChameleonGUIState appState,
) async {
  final connector = appState.connector;
  if (connector == null || !connector.connected || connector.isDFU) {
    return;
  }
  if (connector.connectionType != ConnectionType.ble) {
    return;
  }
  if (!Platform.isWindows && !Platform.isAndroid) {
    return;
  }

  final port = connector.activeDevicePort?.toString();
  if (port == null || port.isEmpty || _handledPorts.contains(port)) {
    return;
  }
  _handledPorts.add(port);

  final communicator = appState.communicator;
  if (communicator == null) {
    return;
  }

  DeviceSettings settings;
  try {
    settings = await communicator.getDeviceSettings();
  } catch (_) {
    return;
  }
  if (!settings.pairingEnabled) {
    return;
  }
  if (await _isBonded(port)) {
    return;
  }

  if (Platform.isWindows) {
    if (!context.mounted) {
      return;
    }
    final pin = await _askPin(context);
    if (pin == null) {
      await appState.disconnect(manual: true);
      return;
    }

    var paired = false;
    try {
      paired =
          await _winrtChannel.invokeMethod<bool>('createBondWithPin', {
            'remote_id': port,
            'pin': pin,
          }) ==
          true;
    } catch (_) {
      paired = false;
    }

    if (!paired) {
      if (context.mounted) {
        _showError(context);
      }
      await appState.disconnect(manual: true);
    }
    return;
  }

  // Android: the operating system owns the PIN prompt.
  try {
    await BluetoothDevice.fromId(port).createBond(timeout: 30);
  } catch (_) {
    if (context.mounted) {
      _showError(context);
    }
    await appState.disconnect(manual: true);
  }
}

void forgetBlePairingPort() {
  _handledPorts.clear();
}

Future<bool> _isBonded(String port) async {
  if (Platform.isWindows) {
    try {
      final result = await _winrtChannel.invokeMethod<dynamic>(
        'getBondState',
        port,
      );
      if (result is Map) {
        return result['bond_state'] == 2;
      }
    } catch (_) {}
    return false;
  }

  if (Platform.isAndroid) {
    try {
      final state = await BluetoothDevice.fromId(port).bondState.first
          .timeout(const Duration(seconds: 5));
      return state == BluetoothBondState.bonded;
    } catch (_) {}
  }
  return false;
}

Future<String?> _askPin(BuildContext context) async {
  final localizations = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final key = GlobalKey<FormState>();

  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(localizations.ble_pin),
        content: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(hintText: localizations.enter_pin),
            validator: (value) {
              if (value == null || value.length != 6) {
                return localizations.pin_must_be_6_digits;
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text);
              }
            },
            child: Text(localizations.connect),
          ),
        ],
      );
    },
  );

  controller.dispose();
  return result;
}

void _showError(BuildContext context) {
  final localizations = AppLocalizations.of(context)!;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(localizations.invalid_password)));
}
