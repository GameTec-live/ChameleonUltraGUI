import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/em4x05.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class EM4X05ReaderMenu extends StatefulWidget {
  const EM4X05ReaderMenu({super.key});

  @override
  State<EM4X05ReaderMenu> createState() => _EM4X05ReaderMenuState();
}

class _EM4X05ReaderMenuState extends State<EM4X05ReaderMenu> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController(text: '00000000');
  bool _reading = false;
  bool _unsupported = false;
  String? _error;
  EM4X05Scan? _scan;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (!_formKey.currentState!.validate()) return;
    final password = int.parse(_password.text, radix: 16);
    final communicator = context.read<ChameleonGUIState>().communicator;
    setState(() {
      _reading = true;
      _scan = null;
      _error = null;
    });
    try {
      if (communicator == null) throw StateError('Device disconnected');
      final capabilities = await communicator.getDeviceCapabilities();
      if (!capabilities.contains(ChameleonCommand.scanEM4X05Tag.value)) {
        if (mounted) setState(() => _unsupported = true);
        return;
      }
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }
      final scan = await communicator.scanEM4X05(password: password);
      if (mounted) setState(() => _scan = scan);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scan = _scan;
    return PopScope(
      canPop: !_reading,
      child: AlertDialog(
        title: Text(l10n.em4x05_reader),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.em4x05_place_tag),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    enabled: !_reading,
                    decoration: InputDecoration(
                      labelText: l10n.password,
                      helperText: l10n.em4x05_password_hint,
                      helperMaxLines: 2,
                    ),
                    validator: (value) =>
                        RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(value ?? '')
                        ? null
                        : l10n.invalid_password,
                  ),
                  const SizedBox(height: 16),
                  if (_reading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(l10n.em4x05_reading),
                  ],
                  if (_unsupported) Text(l10n.em4x05_unsupported),
                  if (_error != null)
                    SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (scan != null)
                    SelectableText(
                      [
                        scan.tagType,
                        'UID: ${scan.uidHex}',
                        '${l10n.em4x05_config}: ${scan.configHex}',
                        '${l10n.em4x05_uid_block}: ${scan.uidBlock}',
                        if (scan.loginUsed) l10n.em4x05_login_used,
                      ].join('\n'),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _reading ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
          FilledButton(
            onPressed: _reading || _unsupported ? null : _read,
            child: Text(l10n.read_card),
          ),
        ],
      ),
    );
  }
}
