import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/dump_analyzer.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';

enum _Operation { read, write, increment, decrement, restore }

/// Operates on the physical card, independently of any saved dump.
class MifareValueBlockDialog extends StatefulWidget {
  final ChameleonCommunicator communicator;
  final MifareClassicType type;
  const MifareValueBlockDialog({
    super.key,
    required this.communicator,
    required this.type,
  });
  @override
  State<MifareValueBlockDialog> createState() => _MifareValueBlockDialogState();
}

class _MifareValueBlockDialogState extends State<MifareValueBlockDialog> {
  final _form = GlobalKey<FormState>();
  final _source = TextEditingController(text: '4');
  final _destination = TextEditingController(text: '4');
  final _sourceKey = TextEditingController(text: 'FFFFFFFFFFFF');
  final _destinationKey = TextEditingController(text: 'FFFFFFFFFFFF');
  final _value = TextEditingController(text: '1');
  final _address = TextEditingController(text: '4');
  int _sourceType = 0x60, _destinationType = 0x60;
  _Operation _operation = _Operation.read;
  List<int>? _capabilities;
  bool _busy = true;
  String? _error, _result;

  bool get _manipulates => [
    _Operation.increment,
    _Operation.decrement,
    _Operation.restore,
  ].contains(_operation);

  ChameleonCommand get _command => _manipulates
      ? ChameleonCommand.mf1ManipulateValueBlock
      : _operation == _Operation.read
      ? ChameleonCommand.mf1ReadBlock
      : ChameleonCommand.mf1WriteBlock;

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    try {
      final capabilities = await widget.communicator.getDeviceCapabilities();
      if (mounted) setState(() => _capabilities = capabilities);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _source,
      _destination,
      _sourceKey,
      _destinationKey,
      _value,
      _address,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _blockValidator(String? text) {
    final block = int.tryParse(text ?? '');
    if (block == null ||
        block <= 0 ||
        block >= mfClassicGetBlockCount(widget.type) ||
        block ==
            mfClassicGetSectorTrailerBlockBySector(
              mfClassicGetSectorByBlock(block),
            )) {
      return AppLocalizations.of(context)!.value_block_invalid_block;
    }
    return null;
  }

  String? _numberValidator(String? text, int min, int max) {
    final value = int.tryParse(text ?? '');
    return value == null || value < min || value > max ? '$min … $max' : null;
  }

  Future<void> _execute() async {
    if (!_form.currentState!.validate()) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final c = widget.communicator;
      final source = int.parse(_source.text);
      final sourceKey = hexToBytes(_sourceKey.text);
      await c.setReaderDeviceMode(true);
      if (_manipulates) {
        final operator = switch (_operation) {
          _Operation.increment => MifareClassicValueBlockOperator.increment,
          _Operation.decrement => MifareClassicValueBlockOperator.decrement,
          _ => MifareClassicValueBlockOperator.restore,
        };
        await c.manipulateValueBlock(
          source,
          _sourceType,
          sourceKey,
          operator,
          _operation == _Operation.restore ? 0 : int.parse(_value.text),
          int.parse(_destination.text),
          _destinationType,
          hexToBytes(_destinationKey.text),
        );
        if (mounted) setState(() => _result = l.value_block_done);
      } else if (_operation == _Operation.write) {
        final data = hexToBytes(
          MifareClassicDumpAnalyzer.intToValueBlock(
            int.parse(_value.text),
            int.parse(_address.text),
          ),
        );
        if (!await c.mf1WriteBlock(source, _sourceType, sourceKey, data)) {
          throw StateError(l.value_block_failed);
        }
        if (mounted) setState(() => _result = l.value_block_done);
      } else {
        final data = await c.mf1ReadBlock(source, _sourceType, sourceKey);
        final hex = bytesToHex(data);
        final value = MifareClassicDumpAnalyzer.valueBlockToInt(hex);
        final address = MifareClassicDumpAnalyzer.valueBlockAddress(hex);
        if (value == null || address == null) {
          throw StateError(l.value_block_invalid_data);
        }
        if (mounted) {
          setState(
            () => _result =
                '${l.value}: $value\n${l.value_block_address}: $address',
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _authentication(bool destination) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: destination ? _destination : _source,
          decoration: InputDecoration(
            labelText: destination
                ? l.value_block_destination
                : l.value_block_source,
          ),
          keyboardType: TextInputType.number,
          validator: _blockValidator,
        ),
        DropdownButtonFormField<int>(
          initialValue: destination ? _destinationType : _sourceType,
          items: const [
            DropdownMenuItem(value: 0x60, child: Text('Key A')),
            DropdownMenuItem(value: 0x61, child: Text('Key B')),
          ],
          onChanged: (value) => setState(() {
            if (destination) {
              _destinationType = value!;
            } else {
              _sourceType = value!;
            }
          }),
        ),
        TextFormField(
          controller: destination ? _destinationKey : _sourceKey,
          decoration: InputDecoration(labelText: l.key),
          validator: (text) => RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(text ?? '')
              ? null
              : l.value_block_invalid_key,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final supported = _capabilities?.contains(_command.value) ?? false;
    final labels = {
      _Operation.read: l.value_block_read,
      _Operation.write: l.value_block_write,
      _Operation.increment: l.value_block_increment,
      _Operation.decrement: l.value_block_decrement,
      _Operation.restore: l.value_block_restore,
    };
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l.live_value_blocks),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: AbsorbPointer(
              absorbing: _busy,
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.value_block_live_hint),
                    DropdownButtonFormField<_Operation>(
                      initialValue: _operation,
                      items: labels.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() {
                        _operation = value!;
                        _result = null;
                        _error = null;
                      }),
                    ),
                    _authentication(false),
                    if (_manipulates) _authentication(true),
                    if (_operation != _Operation.read &&
                        _operation != _Operation.restore)
                      TextFormField(
                        controller: _value,
                        decoration: InputDecoration(labelText: l.value),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        validator: (text) => _numberValidator(
                          text,
                          _operation == _Operation.write ? -0x80000000 : 0,
                          0x7FFFFFFF,
                        ),
                      ),
                    if (_operation == _Operation.write)
                      TextFormField(
                        controller: _address,
                        decoration: InputDecoration(
                          labelText: l.value_block_address,
                        ),
                        keyboardType: TextInputType.number,
                        validator: (text) => _numberValidator(text, 0, 255),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                    if (!_busy && !supported) Text(l.value_block_unsupported),
                    if (_result != null) SelectableText(_result!),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(l.close),
          ),
          ElevatedButton(
            onPressed: _busy || !supported ? null : _execute,
            child: Text(labels[_operation]!),
          ),
        ],
      ),
    );
  }
}
