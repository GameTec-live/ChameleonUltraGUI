// DESFire tool (Phreakbyte fork addition). Covers both the emulation-slot
// commands (einfo/estats/eblank -- DESFIRE_GET_INFO/GET_STATS/FACTORY_BLANK,
// data_cmd.h 6008/6011/6009) and the reader-mode commands against a real
// card (GetVersion + GetApplicationIDs, readerauth -- 6013/6004/6012).
// Each action renders its result as a labeled panel (title + info rows),
// following hf_sniffing.dart's house style rather than a raw text dump.
import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class _ResultRow {
  final String label;
  final String value;
  const _ResultRow(this.label, this.value);
}

class _DesfireResult {
  final String title;
  final List<_ResultRow> rows;
  const _DesfireResult(this.title, this.rows);
}

class DesfireReaderMenu extends StatefulWidget {
  const DesfireReaderMenu({super.key});

  @override
  State<DesfireReaderMenu> createState() => _DesfireReaderMenuState();
}

class _DesfireReaderMenuState extends State<DesfireReaderMenu> {
  bool _busy = false;
  String? _errorMessage;
  _DesfireResult? _result;

  final _blankUidController = TextEditingController();
  final _keyNoController = TextEditingController(text: "0");
  final _aidController = TextEditingController();
  final _keyController =
      TextEditingController(text: "00000000000000000000000000000000");
  String _algo = "aes";
  bool _authExpanded = false;

  @override
  void dispose() {
    _blankUidController.dispose();
    _keyNoController.dispose();
    _aidController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _einfo() async {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.read<ChameleonGUIState>();
    var info = await appState.communicator!.desfireGetInfo();
    setState(() {
      _result = _DesfireResult(localizations.desfire_get_info, [
        _ResultRow(localizations.desfire_info_uid, bytesToHex(info.uid)),
        _ResultRow(localizations.desfire_info_apps,
            "${info.numApps} / ${info.maxApps}"),
        _ResultRow(localizations.desfire_info_files,
            "${info.numFiles} / ${info.maxFiles}"),
        _ResultRow(localizations.desfire_info_pool,
            "${info.poolUsed} / ${info.poolSize} bytes"),
        _ResultRow(
            localizations.desfire_info_keys, "up to ${info.maxKeys}"),
        _ResultRow(
            localizations.desfire_info_picc_auth,
            "0x${info.piccAuthCommand.toRadixString(16).padLeft(2, '0')}"),
        _ResultRow(localizations.desfire_info_cred_size,
            "${info.credSize} bytes"),
      ]);
    });
  }

  Future<void> _estats() async {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.read<ChameleonGUIState>();
    var st = await appState.communicator!.desfireGetStats();
    List<_ResultRow> rows = [
      _ResultRow(localizations.desfire_stats_rx, "${st.framesRx}"),
      _ResultRow(localizations.desfire_stats_tx, "${st.framesTx}"),
      _ResultRow(
          localizations.desfire_stats_errors, "${st.engineErrors}"),
      _ResultRow(localizations.desfire_stats_max_handler,
          "${st.maxHandlerUs} us"),
    ];
    if (st.activationRequests != null) {
      rows.addAll([
        _ResultRow(localizations.desfire_stats_activations,
            "${st.activationRequests}"),
        _ResultRow(localizations.desfire_stats_atqa, "${st.atqaTx}"),
        _ResultRow(
            localizations.desfire_stats_fdt_timeouts, "${st.fdtTimeouts}"),
        _ResultRow(localizations.desfire_stats_max_reset,
            "${st.maxResetUs} us"),
      ]);
    }
    rows.add(_ResultRow(
        localizations.desfire_stats_entropy_misses,
        "${st.entropyStarvations}"));
    setState(() {
      _result = _DesfireResult(localizations.desfire_get_stats, rows);
    });
  }

  Future<void> _eblank() async {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.read<ChameleonGUIState>();
    Uint8List? uid;
    if (_blankUidController.text.isNotEmpty) {
      uid = hexToBytes(_blankUidController.text);
      if (uid.length != 7 || uid[0] != 0x04) {
        throw (localizations.desfire_blank_uid_invalid);
      }
    }
    var newUid = await appState.communicator!.desfireFactoryBlank(uid: uid);
    setState(() {
      _result = _DesfireResult(localizations.desfire_factory_blank, [
        _ResultRow(localizations.desfire_blank_new_uid, bytesToHex(newUid)),
      ]);
    });
  }

  Future<void> _readerInfo() async {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.read<ChameleonGUIState>();
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }
    List<_ResultRow> rows = [];
    try {
      var frames = await appState.communicator!.desfireReaderGetVersion();
      for (var i = 0; i < frames.length; i++) {
        rows.add(_ResultRow(
            localizations.desfire_reader_frame(i), bytesToHex(frames[i])));
      }
    } catch (e) {
      rows.add(_ResultRow(
          localizations.desfire_reader_getversion_failed, e.toString()));
    }
    try {
      var aids = await appState.communicator!.desfireGetApplicationIds();
      if (aids.isEmpty) {
        rows.add(_ResultRow(
            localizations.desfire_reader_apps, localizations.emv_scan_not_found));
      } else {
        for (var aid in aids) {
          rows.add(
              _ResultRow(localizations.desfire_reader_aid, bytesToHex(aid)));
        }
      }
    } catch (e) {
      rows.add(_ResultRow(
          localizations.desfire_reader_apps_failed, e.toString()));
    }
    setState(() {
      _result =
          _DesfireResult(localizations.desfire_getversion_aid_list, rows);
    });
  }

  Future<void> _readerAuth() async {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.read<ChameleonGUIState>();
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }
    int keyNo = int.tryParse(_keyNoController.text) ?? -1;
    if (keyNo < 0 || keyNo > 31) {
      throw (localizations.desfire_auth_keyno_invalid);
    }
    Uint8List? aid;
    if (_aidController.text.isNotEmpty) {
      aid = hexToBytes(_aidController.text);
      if (aid.length != 3) throw (localizations.desfire_auth_aid_invalid);
    }
    var key = hexToBytes(_keyController.text);
    var result = await appState.communicator!.desfireReaderAuthIso7816(
      keyNo: keyNo,
      algorithm: _algo,
      key: key,
      aid: aid,
    );
    String outcome;
    switch (result) {
      case DesfireAuthResult.authenticated:
        outcome = localizations.desfire_auth_result_ok;
        break;
      case DesfireAuthResult.cardRejected:
        outcome = localizations.desfire_auth_result_card_rejected;
        break;
      case DesfireAuthResult.noCard:
        outcome = localizations.desfire_auth_result_no_card;
        break;
      case DesfireAuthResult.requestError:
        outcome = localizations.desfire_auth_result_request_error;
        break;
      case DesfireAuthResult.failed:
        outcome = localizations.desfire_auth_result_failed;
        break;
    }
    setState(() {
      _result = _DesfireResult(localizations.desfire_authenticate, [
        _ResultRow(localizations.desfire_auth_key_no, "$keyNo ($_algo)"),
        _ResultRow(localizations.desfire_auth_result, outcome),
      ]);
    });
  }

  Widget _buildPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildErrorBlock(String message) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var result = _result;
    return AlertDialog(
      title: Text(localizations.desfire_title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.desfire_emulation_slot,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _busy ? null : () => _run(_einfo),
                    child: Text(localizations.desfire_get_info),
                  ),
                  ElevatedButton(
                    onPressed: _busy ? null : () => _run(_estats),
                    child: Text(localizations.desfire_get_stats),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _blankUidController,
                      decoration: InputDecoration(
                        labelText: localizations.desfire_blank_uid_label,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _busy ? null : () => _run(_eblank),
                    child: Text(localizations.desfire_factory_blank),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(localizations.desfire_reader_mode,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy ? null : () => _run(_readerInfo),
                child: Text(localizations.desfire_getversion_aid_list),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                title: Text(localizations.desfire_authenticate),
                initiallyExpanded: _authExpanded,
                onExpansionChanged: (v) => setState(() => _authExpanded = v),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _keyNoController,
                                decoration: InputDecoration(
                                  labelText:
                                      localizations.desfire_key_no_label,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _algo,
                                decoration: InputDecoration(
                                  labelText:
                                      localizations.desfire_algorithm_label,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: "aes", child: Text("AES-128")),
                                  DropdownMenuItem(
                                      value: "2tdea", child: Text("2TDEA")),
                                  DropdownMenuItem(
                                      value: "3tdea", child: Text("3TDEA")),
                                ],
                                onChanged: (v) =>
                                    setState(() => _algo = v ?? "aes"),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _aidController,
                          decoration: InputDecoration(
                            labelText: localizations.desfire_aid_label,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _keyController,
                          decoration: InputDecoration(
                            labelText: localizations.desfire_key_label,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed:
                                _busy ? null : () => _run(_readerAuth),
                            child: Text(localizations.desfire_authenticate),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _buildErrorBlock(_errorMessage!),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (result != null) ...[
                const Divider(height: 24),
                _buildPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(result.title,
                              style: Theme.of(context).textTheme.titleMedium),
                          TextButton(
                            onPressed: () => setState(() => _result = null),
                            child: Text(localizations.desfire_clear_result),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var row in result.rows)
                        _infoRow(row.label, row.value),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.close),
        ),
      ],
    );
  }
}
