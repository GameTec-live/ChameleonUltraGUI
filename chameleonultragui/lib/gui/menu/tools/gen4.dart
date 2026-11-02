import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/mifare_classic/gen4.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Gen4Menu extends StatefulWidget {
  const Gen4Menu({super.key});

  @override
  State<Gen4Menu> createState() => _Gen4MenuState();
}

class _Gen4MenuState extends State<Gen4Menu> {
  final _password = TextEditingController(text: '00000000');
  final _newPassword = TextEditingController();
  final _ats = TextEditingController();
  final _atqa = TextEditingController();
  final _sak = TextEditingController();
  final _maxBlock = TextEditingController();
  final _uid = TextEditingController();
  final _block = TextEditingController(text: '00');
  final _blockData = TextEditingController();
  final _memoryData = TextEditingController();
  int _memoryTarget = 0;
  final _form = GlobalKey<FormState>();
  Gen4Configuration? _config;
  int _protocol = 0, _uidSize = 0, _shadow = 2, _ulMode = 0, _block0 = 2;
  bool _busy = false;
  String? _status;
  String? _version;
  int? _packPage;
  bool _failed = false;

  @override
  void dispose() {
    for (final c in [
      _password,
      _newPassword,
      _ats,
      _atqa,
      _sak,
      _maxBlock,
      _uid,
      _block,
      _blockData,
      _memoryData,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Gen4Client> _client() async {
    final password = gen4ParseHex(_password.text, length: 4);
    final state = context.read<ChameleonGUIState>();
    final communicator = state.communicator;
    if (communicator == null || state.connector?.connected != true) {
      throw StateError(AppLocalizations.of(context)!.device_required);
    }
    if (state.connector!.device != ChameleonDevice.ultra) {
      throw StateError(AppLocalizations.of(context)!.gen4_ultra_required);
    }
    if (!await communicator.isReaderDeviceMode()) {
      await communicator.setReaderDeviceMode(true);
    }
    return Gen4Client(
      (data) => communicator.send14ARaw(
        data,
        respTimeoutMs: 1000,
        checkResponseCrc: false,
      ),
      password,
    );
  }

  Future<void> _run(Future<void> Function(Gen4Client) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
      _failed = false;
    });
    try {
      await action(await _client());
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = e.toString();
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _load(Gen4Configuration config) {
    _config = config;
    _memoryTarget = 0;
    _memoryData.clear();
    _protocol = config.protocol;
    _uidSize = config.bytes[1];
    _shadow = config.shadowMode;
    _ulMode = config.ultralightMode;
    _block0 = config.block0Mode;
    _newPassword.text = gen4Hex(config.password);
    _ats.text = gen4Hex(config.ats);
    _atqa.text = gen4Hex(config.atqa);
    _sak.text = gen4Hex([config.sak]);
    _maxBlock.text = gen4Hex([config.maxBlock]);
  }

  Future<void> _read(Gen4Client client) async {
    setState(() {
      _config = null;
      _version = null;
      _packPage = null;
    });
    final config = await client.readConfiguration();
    if (!mounted) return;
    setState(() {
      _load(config);
      _version = null;
    });
    // Version info is optional on older cards; a failed query must not hide C6.
    try {
      final version = await client.readVersion();
      if (mounted) {
        setState(() {
          _version = gen4Hex(version);
          _packPage = gen4PackPage(version);
        });
      }
    } catch (_) {}
  }

  Gen4Configuration _editedConfiguration() {
    final bytes = Uint8List.fromList(_config!.bytes);
    bytes[0] = _protocol;
    bytes[1] = _uidSize;
    bytes.setRange(2, 6, gen4ParseHex(_newPassword.text, length: 4));
    bytes[6] = _shadow;
    final ats = gen4ParseHex(_ats.text, maxLength: 16);
    bytes[7] = ats.length;
    // Retain unused ATS bytes from the card for a lossless round trip.
    bytes.setRange(8, 8 + ats.length, ats);
    final atqa = gen4ParseHex(_atqa.text, length: 2);
    bytes[24] = atqa[1];
    bytes[25] = atqa[0];
    bytes[26] = gen4ParseHex(_sak.text, length: 1).single;
    bytes[27] = _ulMode;
    bytes[28] = gen4ParseHex(_maxBlock.text, length: 1).single;
    bytes[29] = _block0;
    return Gen4Configuration(bytes);
  }

  Future<bool> _confirm(String message) async {
    final l = AppLocalizations.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.mifare_classic_gen4),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.gen4_confirm_write),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _apply({bool permanent = false}) async {
    if (!_form.currentState!.validate()) return;
    final l = AppLocalizations.of(context)!;
    final config = _editedConfiguration();
    if (!await _confirm(
      permanent ? l.gen4_fuse_warning : l.gen4_apply_warning,
    )) {
      return;
    }
    if (!mounted) return;
    await _run((client) async {
      await client.writeConfiguration(config, permanent: permanent);
      if (!mounted) return;
      // Keep the new credential even if the readback fails after a successful write.
      setState(() {
        _password.text = gen4Hex(config.password);
        _config = null;
        _status = l.gen4_written_read_failed;
      });
      final actual = await client.readConfiguration();
      if (!mounted) return;
      setState(() {
        _load(actual);
        _failed = gen4Hex(actual.bytes) != gen4Hex(config.bytes);
        _status = _failed ? l.gen4_verify_failed : l.gen4_verified;
      });
    });
  }

  Widget _hex(
    TextEditingController controller,
    String label, {
    int? length,
    int? maxLength,
    String? help,
    bool validate = true,
  }) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          helperMaxLines: 4,
          border: const OutlineInputBorder(),
        ),
        autocorrect: false,
        validator: validate
            ? (text) {
                try {
                  gen4ParseHex(
                    text ?? '',
                    length: length,
                    maxLength: maxLength,
                  );
                  return null;
                } catch (_) {
                  return l.gen4_hex_required(
                    length?.toString() ?? '0–$maxLength',
                  );
                }
              }
            : null,
      ),
    );
  }

  Widget _select(
    String label,
    int value,
    List<String> labels,
    ValueChanged<int> change,
  ) {
    final entries = <int, String>{
      for (var i = 0; i < labels.length; i++) i: labels[i],
    };
    entries.putIfAbsent(value, () => '0x${gen4Hex([value])}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$label:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: entries.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text('${gen4Hex([e.key])} · ${e.value}'),
              ),
            )
            .toList(),
        onChanged: _busy ? null : (v) => setState(() => change(v!)),
      ),
    );
  }

  Widget _memoryEditor() {
    final l = AppLocalizations.of(context)!;
    final ul = _config!.protocol == 1;
    final settings = [
      if (ul) ...[
        (label: l.gen4_otp, address: 0x03, length: 4, stride: 4),
        (label: l.gen4_ntag_password, address: 0xE5, length: 4, stride: 4),
        (label: 'PACK', address: _packPage ?? 0x13, length: 2, stride: 4),
        (label: l.version, address: 0xFA, length: 8, stride: 4),
      ],
      (
        label: l.gen4_signature,
        address: ul ? 0xF2 : 0x45,
        length: 32,
        stride: ul ? 4 : 16,
      ),
    ];
    final setting = settings[_memoryTarget];
    final isPack = ul && _memoryTarget == 2;
    final needsPackPage = isPack && _packPage == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _select(
          l.gen4_memory_setting,
          _memoryTarget,
          settings.map((s) => s.label).toList(),
          (v) {
            _memoryTarget = v;
            _memoryData.clear();
          },
        ),
        if (isPack)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: DropdownButtonFormField<int>(
              key: ValueKey('pack:$_packPage'),
              initialValue: _packPage,
              decoration: InputDecoration(
                labelText: l.gen4_pack_page,
                helperText: l.gen4_pack_page_help,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 0x13, child: Text('13 · 06A0 / 6666')),
                DropdownMenuItem(value: 0xE6, child: Text('E6')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _packPage = value;
                      _memoryData.clear();
                    }),
            ),
          ),
        _hex(
          _memoryData,
          setting.label,
          validate: false,
          help: l.gen4_memory_value_help(
            setting.length,
            gen4Hex([setting.address]),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy || needsPackPage
                  ? null
                  : () => _run((client) async {
                      final data = await client.readMemory(
                        setting.address,
                        setting.length,
                        setting.stride,
                      );
                      if (mounted) {
                        setState(() => _memoryData.text = gen4Hex(data));
                      }
                    }),
              child: Text(l.gen4_read_setting),
            ),
            OutlinedButton(
              onPressed: _busy || needsPackPage
                  ? null
                  : () async {
                      Uint8List data;
                      try {
                        data = gen4ParseHex(
                          _memoryData.text,
                          length: setting.length,
                        );
                      } catch (e) {
                        setState(() {
                          _status = e.toString();
                          _failed = true;
                        });
                        return;
                      }
                      if (!await _confirm(l.gen4_block_warning) || !mounted) {
                        return;
                      }
                      _run((client) async {
                        await client.writeMemory(
                          setting.address,
                          data,
                          setting.stride,
                        );
                        final actual = await client.readMemory(
                          setting.address,
                          setting.length,
                          setting.stride,
                        );
                        if (mounted) {
                          setState(() {
                            _failed = gen4Hex(actual) != gen4Hex(data);
                            _status = _failed
                                ? l.gen4_verify_failed
                                : l.gen4_verified;
                          });
                        }
                      });
                    },
              child: Text(l.gen4_write_setting),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l.mifare_classic_gen4),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.gen4_intro),
                  _hex(_password, l.gen4_current_password, length: 4),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            try {
                              gen4ParseHex(_password.text, length: 4);
                            } catch (_) {
                              _form.currentState!.validate();
                              return;
                            }
                            _run(_read);
                          },
                    icon: const Icon(Icons.download),
                    label: Text(l.gen4_read),
                  ),
                  if (_version != null)
                    SelectableText('${l.version}: $_version'),
                  if (_config != null) ...[
                    const SizedBox(height: 12),
                    _select(l.gen4_protocol, _protocol, [
                      'MIFARE Classic',
                      'Ultralight / NTAG',
                    ], (v) => _protocol = v),
                    _select(l.gen4_uid_length, _uidSize, [
                      '4',
                      '7',
                      '10',
                    ], (v) => _uidSize = v),
                    _select(l.gen4_shadow, _shadow, [
                      l.gen4_prewrite,
                      l.gen4_restore,
                      l.disabled,
                      l.gen4_high_speed,
                      l.gen4_split,
                    ], (v) => _shadow = v),
                    Text(
                      l.gen4_shadow_warning,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    _hex(
                      _newPassword,
                      l.gen4_new_password,
                      length: 4,
                      help: l.gen4_password_help,
                    ),
                    _hex(_ats, 'ATS', maxLength: 16, help: l.gen4_ats_help),
                    _hex(_atqa, 'ATQA', length: 2, help: l.gen4_atqa_help),
                    _hex(_sak, 'SAK', length: 1, help: l.gen4_sak_help),
                    _select(l.gen4_ul_mode, _ulMode, [
                      'Ultralight EV1',
                      'NTAG',
                      'Ultralight C',
                      'Ultralight',
                    ], (v) => _ulMode = v),
                    _hex(
                      _maxBlock,
                      l.gen4_max_block,
                      length: 1,
                      help: l.gen4_max_block_help,
                    ),
                    _select(l.gen4_block0, _block0, [
                      l.enabled,
                      l.disabled,
                      l.gen4_factory_default,
                    ], (v) => _block0 = v),
                    FilledButton(
                      onPressed: _busy ? null : _apply,
                      child: Text(l.gen4_apply),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: Text(l.gen4_uid_and_memory),
                      children: [
                        Text(l.gen4_memory_help),
                        _hex(
                          _uid,
                          'UID',
                          validate: false,
                          help: l.gen4_uid_help,
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final config = _config!;
                                  Uint8List uid;
                                  try {
                                    uid = gen4ParseHex(
                                      _uid.text,
                                      length: config.uidLength,
                                    );
                                  } catch (_) {
                                    setState(() {
                                      _status = l.gen4_hex_required(
                                        '${config.uidLength}',
                                      );
                                      _failed = true;
                                    });
                                    return;
                                  }
                                  if (!await _confirm(l.gen4_uid_warning) ||
                                      !mounted) {
                                    return;
                                  }
                                  _run((client) async {
                                    await client.writeUid(config, uid);
                                    if (mounted) {
                                      setState(
                                        () => _status = l.gen4_uid_written,
                                      );
                                    }
                                  });
                                },
                          child: Text(l.gen4_write_uid),
                        ),
                        _memoryEditor(),
                        _hex(_block, l.gen4_block_address, validate: false),
                        _hex(_blockData, l.gen4_block_data, validate: false),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run((client) async {
                                      final block = gen4ParseHex(
                                        _block.text,
                                        length: 1,
                                      ).single;
                                      final data = await client.readBlock(
                                        block,
                                      );
                                      if (mounted) {
                                        setState(
                                          () => _blockData.text = gen4Hex(data),
                                        );
                                      }
                                    }),
                              child: Text(l.gen4_read_block),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      // Parse before asking for confirmation or touching the card.
                                      int block;
                                      Uint8List data;
                                      try {
                                        block = gen4ParseHex(
                                          _block.text,
                                          length: 1,
                                        ).single;
                                        data = gen4ParseHex(
                                          _blockData.text,
                                          length: 16,
                                        );
                                      } catch (e) {
                                        setState(() {
                                          _status = e.toString();
                                          _failed = true;
                                        });
                                        return;
                                      }
                                      if (!await _confirm(
                                            l.gen4_block_warning,
                                          ) ||
                                          !mounted) {
                                        return;
                                      }
                                      _run((client) async {
                                        await client.writeBlock(block, data);
                                        final readback = await client.readBlock(
                                          block,
                                        );
                                        if (mounted) {
                                          setState(() {
                                            _failed =
                                                gen4Hex(readback) !=
                                                gen4Hex(data);
                                            _status = _failed
                                                ? l.gen4_verify_failed
                                                : l.gen4_verified;
                                          });
                                        }
                                      });
                                    },
                              child: Text(l.gen4_write_block),
                            ),
                          ],
                        ),
                      ],
                    ),
                    ExpansionTile(
                      title: Text(l.gen4_permanent_lock),
                      children: [
                        Text(l.gen4_fuse_warning),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _apply(permanent: true),
                          child: Text(l.gen4_permanent_lock),
                        ),
                      ],
                    ),
                  ],
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator(),
                    ),
                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(
                        _status!,
                        style: TextStyle(
                          color: _failed
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
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
        ],
      ),
    );
  }
}
