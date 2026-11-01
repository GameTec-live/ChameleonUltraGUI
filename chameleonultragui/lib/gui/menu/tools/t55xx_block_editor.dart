import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class T55xxBlockEditorMenu extends StatefulWidget {
  const T55xxBlockEditorMenu({super.key});
  @override
  State<T55xxBlockEditorMenu> createState() => _T55xxBlockEditorMenuState();
}

class _T55xxBlockEditorMenuState extends State<T55xxBlockEditorMenu> {
  final _formKey = GlobalKey<FormState>();
  final _data = TextEditingController();
  final _password = TextEditingController();
  int _page = 0;
  int _block = 0;
  bool _usePassword = false;
  bool _busy = false;
  bool? _supported;
  String? _message;

  @override
  void initState() {
    super.initState();
    _checkCapabilities();
  }

  Future<void> _checkCapabilities() async {
    try {
      final communicator = context.read<ChameleonGUIState>().communicator;
      final capabilities = await communicator?.getDeviceCapabilities();
      if (mounted) {
        setState(
          () => _supported =
              capabilities?.contains(ChameleonCommand.writeT55XX.value) ??
              false,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _supported = false;
          _message = error.toString();
        });
      }
    }
  }

  Future<void> _write() async {
    if (!_formKey.currentState!.validate()) return;
    final l = AppLocalizations.of(context)!;
    final communicator = context.read<ChameleonGUIState>().communicator;
    if (communicator == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }
      await communicator.writeT55XX(
        _block,
        hexToBytes(_data.text),
        page1: _page == 1,
        password: _usePassword ? hexToBytes(_password.text) : null,
      );
      if (mounted) setState(() => _message = l.t55xx_block_editor_sent);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _data.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final connected = context.watch<ChameleonGUIState>().communicator != null;
    final enabled = connected && _supported == true && !_busy;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l.t55xx_block_editor),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t55xx_block_editor_notice),
                  const SizedBox(height: 16),
                  if (!connected)
                    Text(l.device_required)
                  else if (_supported == null)
                    Text(l.t55xx_block_editor_checking)
                  else if (_supported == false)
                    Text(l.t55xx_block_editor_unsupported),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _page,
                          decoration: InputDecoration(
                            labelText: l.t55xx_block_editor_page,
                          ),
                          items: [
                            for (final page in [0, 1])
                              DropdownMenuItem(
                                value: page,
                                child: Text('$page'),
                              ),
                          ],
                          onChanged: enabled
                              ? (page) => setState(() {
                                  _page = page!;
                                  _block = 0;
                                  _message = null;
                                })
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey(_page),
                          initialValue: _block,
                          decoration: InputDecoration(labelText: l.block),
                          items: [
                            for (
                              var block = 0;
                              block < (_page == 0 ? 8 : 4);
                              block++
                            )
                              DropdownMenuItem(
                                value: block,
                                child: Text('$block'),
                              ),
                          ],
                          onChanged: enabled
                              ? (block) => setState(() {
                                  _block = block!;
                                  _message = null;
                                })
                              : null,
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _data,
                    enabled: enabled,
                    decoration: InputDecoration(
                      labelText: l.t55xx_block_editor_data,
                    ),
                    validator: (value) => validateHex(
                      value,
                      l,
                      exactBytes: 4,
                      required: true,
                      fieldName: l.block,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.t55xx_block_editor_use_password),
                    value: _usePassword,
                    onChanged: enabled
                        ? (value) => setState(() => _usePassword = value)
                        : null,
                  ),
                  if (_usePassword)
                    TextFormField(
                      controller: _password,
                      enabled: enabled,
                      decoration: InputDecoration(labelText: l.password),
                      validator: (value) => validateHex(
                        value,
                        l,
                        exactBytes: 4,
                        required: true,
                        fieldName: l.password,
                      ),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(_message!),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l.close),
          ),
          FilledButton(
            onPressed: enabled ? _write : null,
            child: Text(l.write),
          ),
        ],
      ),
    );
  }
}
