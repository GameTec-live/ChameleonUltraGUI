import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Reset T55xx to open (no-password) blank-ish state so other tools can rewrite it.
///
/// After Chameleon EM410x clone writes, the tag has PWD enabled (default
/// 20206666). Cheap cloners only do open writes and then fail. This tool
/// disables the password bit and wipes data blocks.
class T55XXResetMenu extends StatefulWidget {
  const T55XXResetMenu({super.key});

  @override
  T55XXResetMenuState createState() => T55XXResetMenuState();
}

class T55XXResetMenuState extends State<T55XXResetMenu> {
  final TextEditingController passwordController =
      TextEditingController(text: '20206666');
  bool isProcessing = false;
  bool wipeData = true;
  bool tryCommonPasswords = true;
  String? statusMessage;
  bool? success;

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _runReset() async {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    final pwdText = passwordController.text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (pwdText.length != 8) {
      setState(() {
        success = false;
        statusMessage = localizations.t55xx_reset_invalid_password;
      });
      return;
    }

    setState(() {
      isProcessing = true;
      success = null;
      statusMessage = localizations.t55xx_reset_in_progress;
    });

    try {
      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      final passwords = <Uint8List>[hexToBytes(pwdText)];
      if (tryCommonPasswords) {
        // Built-in common cloner / CU passwords (in addition to user field).
        passwords.addAll([
          Uint8List.fromList([0x20, 0x20, 0x66, 0x66]),
          Uint8List.fromList([0x00, 0x00, 0x00, 0x00]),
          Uint8List.fromList([0x51, 0x24, 0x36, 0x48]),
          Uint8List.fromList([0x19, 0x92, 0x04, 0x27]),
          Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]),
        ]);
      }

      final used = await appState.communicator!.resetT55xxToOpen(
        passwords: passwords,
        wipeDataBlocks: wipeData,
      );

      if (!mounted) return;
      setState(() {
        isProcessing = false;
        success = true;
        // Firmware cannot confirm which password stuck; show primary tried.
        statusMessage = used != null
            ? localizations.t55xx_reset_success_with_password(used)
            : localizations.t55xx_reset_success_open;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isProcessing = false;
        success = false;
        statusMessage = '${localizations.t55xx_reset_failed}: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.t55xx_reset_title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.orange.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        localizations.t55xx_reset_description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              localizations.t55xx_reset_password_label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: passwordController,
              enabled: !isProcessing,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '20206666',
                helperText: localizations.t55xx_reset_password_hint,
              ),
              inputFormatters: hexFormatter,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: tryCommonPasswords,
              onChanged: isProcessing
                  ? null
                  : (v) => setState(() => tryCommonPasswords = v ?? true),
              title: Text(localizations.t55xx_reset_try_common),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: wipeData,
              onChanged: isProcessing
                  ? null
                  : (v) => setState(() => wipeData = v ?? true),
              title: Text(localizations.t55xx_reset_wipe_data),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (isProcessing) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(localizations.t55xx_reset_in_progress),
            ],
            if (statusMessage != null && !isProcessing) ...[
              const SizedBox(height: 16),
              Card(
                color: (success == true
                        ? Colors.green
                        : success == false
                            ? Colors.red
                            : Colors.grey)
                    .withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(statusMessage!),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isProcessing ? null : () => Navigator.of(context).pop(),
          child: Text(localizations.close),
        ),
        ElevatedButton.icon(
          onPressed: isProcessing ? null : _runReset,
          icon: const Icon(Icons.restart_alt),
          label: Text(localizations.t55xx_reset_start),
        ),
      ],
    );
  }
}
