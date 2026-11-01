import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Advanced command tools. Device commands do not change mode automatically.
class RawCommandsMenu extends StatefulWidget {
  final bool hf;
  const RawCommandsMenu({super.key, this.hf = false});

  @override
  State<RawCommandsMenu> createState() => _RawCommandsMenuState();
}

class _RawCommandsMenuState extends State<RawCommandsMenu> {
  final _form = GlobalKey<FormState>();
  final _command = TextEditingController(text: '1000');
  final _payload = TextEditingController();
  final _timeout = TextEditingController(text: '1000');
  final _bits = TextEditingController();
  // Firmware option bits, ordered from bit 7 through bit 2.
  final _options = [true, true, true, true, false, true];
  bool _busy = false;
  String? _result;

  @override
  void dispose() {
    for (final controller in [_command, _payload, _timeout, _bits]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _number(String text) => int.tryParse(text.trim());
  String _hex(String value) => value.replaceAll(RegExp(r'\s'), '');

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<ChameleonGUIState>();
    final l = AppLocalizations.of(context)!;
    final communicator = app.communicator;
    if (communicator == null || app.connector?.connected != true) {
      setState(() => _result = l.device_required);
      return;
    }
    final hex = _hex(_payload.text);
    final payload = Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    final timeout = _number(_timeout.text)!;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      var data = payload;
      var command = _number(_command.text)!;
      if (widget.hf) {
        if (!await communicator.isReaderDeviceMode()) {
          await communicator.setReaderDeviceMode(true);
        }
        command = ChameleonCommand.hf14ARawCommand.value;
        final flags = [
          for (var i = 0; i < _options.length; i++)
            if (_options[i]) 1 << (7 - i),
        ].fold(0, (a, b) => a | b);
        data = Uint8List.fromList([
          flags,
          ...u16ToBytes(timeout),
          ...u16ToBytes(
            _bits.text.trim().isEmpty
                ? payload.length * 8
                : _number(_bits.text)!,
          ),
          ...payload,
        ]);
      }
      final response = await communicator.sendRawCmd(
        command,
        data: data,
        timeout: Duration(milliseconds: timeout + (widget.hf ? 5000 : 0)),
      );
      if (!mounted) return;
      setState(
        () => _result =
            'CMD 0x${response!.command.toRadixString(16).padLeft(4, '0')}\n'
            '${l.raw_status}: 0x${response.status.toRadixString(16).padLeft(4, '0')}\n'
            'RX (${response.data.length} B): ${bytesToHex(response.data)}',
      );
    } catch (error) {
      if (mounted) setState(() => _result = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<ChameleonGUIState>();
    final l = AppLocalizations.of(context)!;
    final connected = app.connector?.connected == true;
    final hfSupported = app.connector?.device == ChameleonDevice.ultra;
    final optionLabels = [
      l.raw_activate_rf,
      l.raw_wait_response,
      l.raw_append_crc,
      l.raw_auto_select,
      l.raw_keep_rf,
      l.raw_check_crc,
    ];
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.hf ? l.raw_hf : l.raw_device),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.hf ? l.raw_hf_help : l.raw_device_help),
                  if (!connected) Text(l.device_required),
                  if (widget.hf && connected && !hfSupported)
                    Text(l.raw_ultra_required),
                  if (!widget.hf)
                    TextFormField(
                      controller: _command,
                      enabled: !_busy,
                      decoration: InputDecoration(labelText: l.raw_command),
                      validator: (v) {
                        final n = _number(v!);
                        return n == null || n < 0 || n > 65535
                            ? l.raw_invalid_number(0, 65535)
                            : null;
                      },
                    ),
                  TextFormField(
                    controller: _payload,
                    enabled: !_busy,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: l.raw_payload,
                      hintText: '60 00',
                    ),
                    validator: (v) {
                      final hex = _hex(v!);
                      return hex.length.isOdd ||
                              !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex) ||
                              hex.length >
                                  (widget.hf ? (_options[2] ? 62 : 64) : 4096) *
                                      2
                          ? l.raw_invalid_hex(
                              widget.hf ? (_options[2] ? 62 : 64) : 4096,
                            )
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: _timeout,
                    enabled: !_busy,
                    decoration: InputDecoration(labelText: l.raw_timeout),
                    validator: (v) {
                      final n = _number(v!);
                      return n == null || n < 1 || n > 65535
                          ? l.raw_invalid_number(1, 65535)
                          : null;
                    },
                  ),
                  if (widget.hf) ...[
                    TextFormField(
                      controller: _bits,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: l.raw_bits,
                        hintText: l.raw_bits_help,
                      ),
                      validator: (v) {
                        if (v!.trim().isEmpty) {
                          return _options[2] && _hex(_payload.text).isEmpty
                              ? l.raw_crc_bytes
                              : null;
                        }
                        final n = _number(v);
                        final max = _hex(_payload.text).length ~/ 2 * 8;
                        if (_options[2] &&
                            n != null &&
                            (n == 0 || n % 8 != 0)) {
                          return l.raw_crc_bytes;
                        }
                        final min = max == 0 ? 0 : max - 7;
                        return n == null || n < min || n > max
                            ? l.raw_invalid_number(min, max)
                            : null;
                      },
                    ),
                    for (var i = 0; i < optionLabels.length; i++)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(optionLabels[i]),
                        value: _options[i],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _options[i] = value!),
                      ),
                  ],
                  if (_busy) const LinearProgressIndicator(),
                  if (_result != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(_result!),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(l.close),
          ),
          FilledButton(
            onPressed: _busy || !connected || (widget.hf && !hfSupported)
                ? null
                : _send,
            child: Text(l.raw_send),
          ),
        ],
      ),
    );
  }
}
