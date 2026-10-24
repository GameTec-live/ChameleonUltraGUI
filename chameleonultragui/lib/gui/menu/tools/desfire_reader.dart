// DESFire tool (Phreakbyte fork addition). Covers both the emulation-slot
// commands (einfo/estats/eblank -- DESFIRE_GET_INFO/GET_STATS/FACTORY_BLANK,
// data_cmd.h 6008/6011/6009) and the reader-mode commands against a real
// card (GetVersion + GetApplicationIDs, readerauth -- 6013/6004/6012).
// UI chrome (titles/buttons/field labels) goes through AppLocalizations
// (added to lib/l10n/app_en.arb -- the template arb, so `flutter gen-l10n`
// picks it up on the next build; no other locale has a translation yet).
// Device-readout text (field names like "UID"/"Applications" in the output
// box below) mirrors the Python CLI's own output 1:1 and stays English,
// same as every other raw-dump surface in this app (hex viewers, sniff
// logs, chameleonTagToString's own tag names).
import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DesfireReaderMenu extends StatefulWidget {
  const DesfireReaderMenu({super.key});

  @override
  State<DesfireReaderMenu> createState() => _DesfireReaderMenuState();
}

class _DesfireReaderMenuState extends State<DesfireReaderMenu> {
  bool _busy = false;
  String _output = "";

  final _blankUidController = TextEditingController();
  final _keyNoController = TextEditingController(text: "0");
  final _aidController = TextEditingController();
  final _keyController = TextEditingController(
      text: "00000000000000000000000000000000");
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

  void _append(String line) {
    setState(() {
      _output = _output.isEmpty ? line : "$_output\n$line";
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => ErrorPage(errorMessage: e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _einfo() async {
    var appState = context.read<ChameleonGUIState>();
    var info = await appState.communicator!.desfireGetInfo();
    _append("-- Slot info --");
    _append("UID           : ${bytesToHex(info.uid)}");
    _append("Applications  : ${info.numApps} / ${info.maxApps}");
    _append("Files         : ${info.numFiles} / ${info.maxFiles}");
    _append("File data pool: ${info.poolUsed} / ${info.poolSize} bytes");
    _append("Keys per app  : up to ${info.maxKeys}");
    _append(
        "PICC auth     : 0x${info.piccAuthCommand.toRadixString(16).padLeft(2, '0')}");
    _append("Credential    : ${info.credSize} bytes on device");
  }

  Future<void> _estats() async {
    var appState = context.read<ChameleonGUIState>();
    var st = await appState.communicator!.desfireGetStats();
    _append("-- Slot diagnostics --");
    _append("Frames received : ${st.framesRx}");
    _append("Frames sent     : ${st.framesTx}");
    _append("Engine errors   : ${st.engineErrors}");
    _append("Max handler time: ${st.maxHandlerUs} us");
    if (st.activationRequests != null) {
      _append("Activation reqs : ${st.activationRequests}");
      _append("ATQA sent       : ${st.atqaTx}");
      _append("FDT timeouts    : ${st.fdtTimeouts}");
      _append("Max reset time  : ${st.maxResetUs} us");
    }
    _append("Entropy misses  : ${st.entropyStarvations}");
  }

  Future<void> _eblank() async {
    var appState = context.read<ChameleonGUIState>();
    Uint8List? uid;
    if (_blankUidController.text.isNotEmpty) {
      uid = hexToBytes(_blankUidController.text);
      if (uid.length != 7 || uid[0] != 0x04) {
        throw ("UID must be 7 bytes starting with 04");
      }
    }
    var newUid = await appState.communicator!.desfireFactoryBlank(uid: uid);
    _append("-- Factory blank --");
    _append("Blanked. New UID: ${bytesToHex(newUid)}");
  }

  Future<void> _readerInfo() async {
    var appState = context.read<ChameleonGUIState>();
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }
    _append("-- Reader: GetVersion --");
    try {
      var frames = await appState.communicator!.desfireReaderGetVersion();
      for (var i = 0; i < frames.length; i++) {
        _append("Frame $i: ${bytesToHex(frames[i])}");
      }
    } catch (e) {
      _append("GetVersion failed: $e");
    }
    _append("-- Reader: GetApplicationIDs --");
    try {
      var aids = await appState.communicator!.desfireGetApplicationIds();
      if (aids.isEmpty) {
        _append("Applications: none");
      } else {
        _append("Applications: ${aids.length} found");
        for (var aid in aids) {
          _append("  AID: ${bytesToHex(aid)}");
        }
      }
    } catch (e) {
      _append("GetApplicationIDs failed: $e");
    }
  }

  Future<void> _readerAuth() async {
    var appState = context.read<ChameleonGUIState>();
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }
    int keyNo = int.tryParse(_keyNoController.text) ?? -1;
    if (keyNo < 0 || keyNo > 31) throw ("key number must be 0-31");
    Uint8List? aid;
    if (_aidController.text.isNotEmpty) {
      aid = hexToBytes(_aidController.text);
      if (aid.length != 3) throw ("AID must be 3 bytes (6 hex chars)");
    }
    var key = hexToBytes(_keyController.text);
    var result = await appState.communicator!.desfireReaderAuthIso7816(
      keyNo: keyNo,
      algorithm: _algo,
      key: key,
      aid: aid,
    );
    _append("-- Reader: authenticate (key $keyNo, $_algo) --");
    switch (result) {
      case DesfireAuthResult.authenticated:
        _append("Authenticated.");
        break;
      case DesfireAuthResult.cardRejected:
        _append("Card refused authentication.");
        break;
      case DesfireAuthResult.noCard:
        _append("No card in the field.");
        break;
      case DesfireAuthResult.requestError:
        _append("Device rejected the request.");
        break;
      case DesfireAuthResult.failed:
        _append("Authentication failed.");
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(localizations.desfire_title),
      content: SizedBox(
        width: 480,
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
                                  labelText: localizations.desfire_key_no_label,
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
                                  labelText: localizations.desfire_algorithm_label,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: const [
                                  DropdownMenuItem(value: "aes", child: Text("AES-128")),
                                  DropdownMenuItem(value: "2tdea", child: Text("2TDEA")),
                                  DropdownMenuItem(value: "3tdea", child: Text("3TDEA")),
                                ],
                                onChanged: (v) => setState(() => _algo = v ?? "aes"),
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
                            onPressed: _busy ? null : () => _run(_readerAuth),
                            child: Text(localizations.desfire_authenticate),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(localizations.desfire_output_label,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 100, maxHeight: 220),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _output.isEmpty ? localizations.no_output_yet : _output,
                    style: const TextStyle(fontFamily: "monospace", fontSize: 12),
                  ),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _output = ""),
          child: Text(localizations.clear),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.close),
        ),
      ],
    );
  }
}
