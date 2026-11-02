import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/helpers/wipe_card.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class WipeCardMenu extends StatefulWidget {
  const WipeCardMenu({super.key});

  @override
  State<WipeCardMenu> createState() => _WipeCardMenuState();
}

class _WipeCardMenuState extends State<WipeCardMenu> {
  final _form = GlobalKey<FormState>();
  final _key = TextEditingController();
  WipeTarget? _target;
  bool _busy = false;
  bool _t55xx = false;
  bool _wipeData = true;
  bool _confirmed = false;
  String? _message;
  int _progress = 0;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _run(bool wipe) async {
    if (wipe && !_form.currentState!.validate()) return;
    final app = context.read<ChameleonGUIState>();
    final l = AppLocalizations.of(context)!;
    final communicator = app.communicator;
    if (communicator == null) return;
    final wiper = CardWiper(communicator);
    setState(() {
      _busy = true;
      _message = null;
      _progress = 0;
      if (!wipe) {
        _target = null;
        _confirmed = false;
      }
    });
    void progress(int value) {
      if (mounted) setState(() => _progress = value);
    }

    try {
      if (!wipe) {
        final target = await wiper.detect();
        if (mounted) {
          setState(() {
            _target = target;
            _confirmed = false;
            _message = target == null ? l.wipe_no_hf : null;
          });
        }
        return;
      }
      if (_t55xx) {
        await wiper.wipeT55xx(
          password: _key.text.isEmpty ? null : hexToBytes(_key.text),
          wipeData: _wipeData,
        );
        if (mounted) setState(() => _message = l.wipe_t55xx_sent);
      } else {
        final target = _target!;
        final List<int> failed;
        if (target.classicType != MifareClassicType.none) {
          await wiper.checkTarget(target);
          final recovery = MifareClassicRecovery(
            appState: app,
            localizations: l,
            update: () {
              if (mounted) setState(() {});
            },
            selectedDictionary: Dictionary(
              id: 'wipe',
              name: 'wipe',
              color: Colors.grey,
              keys: app.sharedPreferencesProvider
                  .getDictionaries(keyLength: 12)
                  .expand((dictionary) => dictionary.keys)
                  .toList(),
            ),
          );
          await recovery.initialize();
          await recovery.checkKeys();
          if (!recovery.allKeysExists) await recovery.recoverKeys();
          failed = await wiper.wipeClassic(target, recovery, progress);
        } else {
          failed = await wiper.wipeUltralight(
            target,
            _key.text.isEmpty ? null : hexToBytes(_key.text),
            progress,
          );
        }
        if (mounted) {
          setState(
            () => _message = failed.isEmpty
                ? l.wipe_complete
                : l.wipe_incomplete(failed.join(', ')),
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _message = l.wipe_error(error.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (wipe) {
            _confirmed = false;
            _target = null;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final connected = context.watch<ChameleonGUIState>().communicator != null;
    final classic =
        _target?.classicType != null &&
        _target!.classicType != MifareClassicType.none;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l.wipe_card),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.wipe_warning),
                  const SizedBox(height: 16),
                  if (!connected) Text(l.device_required),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.wipe_t55xx),
                    subtitle: Text(l.wipe_t55xx_warning),
                    value: _t55xx,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _t55xx = value;
                            _target = null;
                            _confirmed = false;
                            _key.clear();
                            _message = null;
                          }),
                  ),
                  if (!_t55xx) ...[
                    OutlinedButton(
                      onPressed: connected && !_busy ? () => _run(false) : null,
                      child: Text(l.wipe_detect),
                    ),
                    if (_target != null)
                      Text(
                        '${_target!.name} · ${bytesToHexSpace(_target!.card.uid)}',
                      ),
                  ],
                  if (_t55xx || (_target != null && !classic))
                    TextFormField(
                      controller: _key,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: l.wipe_current_key,
                      ),
                      inputFormatters: hexFormatter,
                      validator: (value) => validateHex(
                        value,
                        l,
                        exactBytes: _target?.type == TagType.ultralightC
                            ? 16
                            : 4,
                        fieldName: l.key,
                      ),
                    ),
                  if (_t55xx)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.wipe_t55xx_data),
                      value: _wipeData,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _wipeData = value!),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.wipe_confirm),
                    value: _confirmed,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _confirmed = value!),
                  ),
                  if (_busy) ...[
                    LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress / 100,
                    ),
                    Text(l.wipe_working),
                  ],
                  if (_message != null) Text(_message!),
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
            onPressed:
                connected && !_busy && _confirmed && (_t55xx || _target != null)
                ? () => _run(true)
                : null,
            child: Text(l.wipe_card),
          ),
        ],
      ),
    );
  }
}
