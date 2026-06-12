import 'dart:io';
import 'dart:math' as math;

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/hex_viewer.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf_sniff.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class HfSniffingMenu extends StatefulWidget {
  const HfSniffingMenu({super.key});

  @override
  State<HfSniffingMenu> createState() => _HfSniffingMenuState();
}

class _HfSniffRecoveryState {
  final bool isLoading;
  final int? key;
  final String? method;
  final String? error;

  const _HfSniffRecoveryState({
    this.isLoading = false,
    this.key,
    this.method,
    this.error,
  });
}

class _HfSniffingMenuState extends State<HfSniffingMenu> {
  static const int _kNoKey = 0xFFFFFFFFFFFFFFFF;

  final _formKey = GlobalKey<FormState>();
  final _timeoutController = TextEditingController(text: '5000');

  bool _isCapturing = false;
  bool _isRecoveringAll = false;
  bool? _capabilitySupported;
  String? _statusMessage;
  String? _errorMessage;

  HfSniffCapture? _capture;
  final Map<String, _HfSniffRecoveryState> _recoveryStates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCapabilities();
    });
  }

  @override
  void dispose() {
    _timeoutController.dispose();
    super.dispose();
  }

  Future<void> _loadCapabilities() async {
    final appState = context.read<ChameleonGUIState>();
    if (appState.communicator == null) {
      return;
    }
    try {
      final capabilities = await appState.communicator!.getDeviceCapabilities();
      if (!mounted) {
        return;
      }
      setState(() {
        _capabilitySupported =
            capabilities.contains(ChameleonCommand.hf14aSniff.value);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _capabilitySupported = null;
      });
    }
  }

  Future<void> _captureFrames() async {
    final localizations = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final timeoutMs = int.parse(_timeoutController.text);
    final appState = context.read<ChameleonGUIState>();

    setState(() {
      _isCapturing = true;
      _capture = null;
      _recoveryStates.clear();
      _errorMessage = null;
      _statusMessage = localizations.hf_sniff_capture_in_progress(timeoutMs);
    });

    try {
      if (await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(false);
      }

      final rawBytes =
          await appState.communicator!.hf14aSniff(timeoutMs: timeoutMs);
      if (!mounted) {
        return;
      }

      if (rawBytes.isEmpty) {
        setState(() {
          _statusMessage = localizations.hf_sniff_no_frames;
        });
        return;
      }

      final capture = HfSniffCapture.fromChameleonBytes(rawBytes);
      setState(() {
        _capture = capture;
        _statusMessage = capture.frames.isEmpty
            ? localizations.hf_sniff_no_decoded_frames
            : localizations.hf_sniff_capture_done(capture.frames.length);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final errorText = error.toString();
      final firmwareUnsupported = _isFirmwareUnsupportedError(errorText);
      setState(() {
        if (firmwareUnsupported) {
          _capabilitySupported = false;
          _statusMessage = null;
          _errorMessage = null;
        } else {
          _errorMessage = errorText;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  bool _isFirmwareUnsupportedError(String errorText) {
    return errorText.contains('0x67') || errorText.contains('0x69');
  }

  Future<void> _exportCapture() async {
    final capture = _capture;
    if (capture == null) {
      return;
    }

    final localizations = AppLocalizations.of(context)!;
    final filename =
        'hf-sniff-${DateTime.now().toIso8601String().replaceAll(':', '-')}';

    final outputFile = await FilePicker.saveFile(
      dialogTitle: '${localizations.output_file}:',
      fileName: '$filename.trace',
      bytes: capture.rawBytes,
    );

    if (outputFile != null && mounted) {
      _showSnack(localizations.save_to_file);
    }
  }

  Future<void> _loadCaptureFromFile() async {
    final localizations = AppLocalizations.of(context)!;

    final picked = await FilePicker.pickFile();
    if (picked == null) {
      return;
    }

    Uint8List? bytes;
    if (picked.path != null) {
      try {
        bytes = await File(picked.path!).readAsBytes();
      } catch (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = localizations.hf_sniff_load_failed(error.toString());
        });
        return;
      }
    }

    if (bytes == null || bytes.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            localizations.hf_sniff_load_failed(localizations.hf_sniff_no_frames);
      });
      return;
    }

    try {
      final capture = HfSniffCapture.fromProxmarkTrace(bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _capture = capture;
        _recoveryStates.clear();
        _errorMessage = null;
        _statusMessage = capture.frames.isEmpty
            ? localizations.hf_sniff_no_decoded_frames
            : localizations.hf_sniff_loaded(capture.frames.length);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = localizations.hf_sniff_load_failed(error.toString());
      });
    }
  }

  Future<void> _copyText(String text, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _showSnack(successMessage);
    }
  }

  Future<void> _recoverGroup(HfSniffNonceGroup group) async {
    final localizations = AppLocalizations.of(context)!;
    if (!group.canRecover) {
      return;
    }

    setState(() {
      _recoveryStates[group.id] = const _HfSniffRecoveryState(isLoading: true);
    });

    try {
      final first = group.exchanges[0];
      final second = group.exchanges[1];
      final uid = int.parse(group.uid, radix: 16);

      final mfkey64Result = await recovery.mfkey64(recovery.Mfkey64Dart(
        uid: uid,
        nt: first.nt,
        nrEnc: first.nr,
        arEnc: first.ar,
        atEnc: second.nt,
      ));

      if (mfkey64Result.isNotEmpty && mfkey64Result.first != _kNoKey) {
        if (!mounted) {
          return;
        }
        setState(() {
          _recoveryStates[group.id] = _HfSniffRecoveryState(
            key: mfkey64Result.first,
            method: 'mfkey64',
          );
        });
        return;
      }

      final mfkey32Result = await recovery.mfkey32(recovery.Mfkey32Dart(
        uid: uid,
        nt0: first.nt,
        nt1: second.nt,
        nr0Enc: first.nr,
        ar0Enc: first.ar,
        nr1Enc: second.nr,
        ar1Enc: second.ar,
      ));

      if (!mounted) {
        return;
      }

      if (mfkey32Result.isNotEmpty && mfkey32Result.first != _kNoKey) {
        setState(() {
          _recoveryStates[group.id] = _HfSniffRecoveryState(
            key: mfkey32Result.first,
            method: 'mfkey32',
          );
        });
      } else {
        setState(() {
          _recoveryStates[group.id] = _HfSniffRecoveryState(
            error: localizations.hf_sniff_recovery_failed,
          );
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recoveryStates[group.id] = _HfSniffRecoveryState(
          error: error.toString(),
        );
      });
    }
  }

  Future<void> _recoverAll() async {
    final capture = _capture;
    if (capture == null || _isRecoveringAll) {
      return;
    }

    final groups = capture.nonceGroups.where((group) => group.canRecover);
    if (groups.isEmpty) {
      return;
    }

    setState(() {
      _isRecoveringAll = true;
    });

    try {
      for (final group in groups) {
        await _recoverGroup(group);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRecoveringAll = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.hideCurrentSnackBar();
    scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatKey(int key) {
    return key.toRadixString(16).padLeft(12, '0').toUpperCase();
  }

  Uint8List _keyBytes(int key) {
    return Uint8List.fromList(u64ToBytes(key).sublist(2, 8));
  }

  Future<void> _saveRecoveredKey(HfSniffNonceGroup group, int key) async {
    await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return DictionaryExportMenu(
          defaultName: group.uid == '00000000'
              ? 'hf-sniff-key'
              : 'hf-sniff-${group.uid.toLowerCase()}',
          keys: [_keyBytes(key)],
        );
      },
    );
  }

  String _rawHexDump({int? maxBytes}) {
    final capture = _capture;
    if (capture == null) {
      return '';
    }
    return buildHfSniffRawHexPreview(
      capture.rawBytes,
      maxBytes: maxBytes ?? capture.rawBytes.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final dialogWidth =
        math.min(MediaQuery.of(context).size.width * 0.92, 960.0).toDouble();
    final dialogHeight =
        math.min(MediaQuery.of(context).size.height * 0.84, 780.0).toDouble();

    return AlertDialog(
      title: Text(localizations.hf_sniffing),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: DefaultTabController(
          length: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCapabilityBanner(localizations),
              Form(
                key: _formKey,
                child: _buildHeaderControls(localizations),
              ),
              if (_statusMessage != null || _errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildStatusBlock(),
                ),
              const SizedBox(height: 12),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: localizations.hf_sniff_summary),
                  Tab(text: localizations.hf_sniff_frames),
                  Tab(text: localizations.hf_sniff_nonces),
                  Tab(text: localizations.hf_sniff_recovery),
                  Tab(text: localizations.hf_sniff_raw),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildSummaryTab(localizations),
                    _buildFramesTab(localizations),
                    _buildNoncesTab(localizations),
                    _buildRecoveryTab(localizations),
                    _buildRawTab(localizations),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.close),
        ),
      ],
    );
  }

  Widget _buildHeaderControls(AppLocalizations localizations) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        final field = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: TextFormField(
            controller: _timeoutController,
            enabled: !_isCapturing,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: localizations.hf_sniff_timeout,
              helperText: localizations.hf_sniff_timeout_help,
              border: const OutlineInputBorder(),
            ),
            validator: (value) => validateIntRange(
              value,
              localizations,
              min: 1,
              max: 30000,
            ),
          ),
        );

        final buttons = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: (_isCapturing ||
                      _capabilitySupported == false ||
                      !_isDeviceConnected())
                  ? null
                  : _captureFrames,
              icon: _isCapturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar),
              label: Text(localizations.hf_sniff_capture),
            ),
            OutlinedButton.icon(
              onPressed: _capture == null ? null : _exportCapture,
              icon: const Icon(Icons.download),
              label: Text(localizations.save_to_file),
            ),
            OutlinedButton.icon(
              onPressed: _isCapturing ? null : _loadCaptureFromFile,
              icon: const Icon(Icons.upload_file),
              label: Text(localizations.hf_sniff_load_file),
            ),
            OutlinedButton.icon(
              onPressed: _capture == null
                  ? null
                  : () => _copyText(
                        _rawHexDump(),
                        localizations.hf_sniff_hex_copied,
                      ),
              icon: const Icon(Icons.copy_all),
              label: Text(localizations.hf_sniff_copy_hex),
            ),
          ],
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field,
              const SizedBox(width: 20),
              Expanded(
                  child:
                      Align(alignment: Alignment.centerLeft, child: buttons)),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field,
            const SizedBox(height: 12),
            buttons,
          ],
        );
      },
    );
  }

  Widget _buildCapabilityBanner(AppLocalizations localizations) {
    if (!_isDeviceConnected()) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          color: Colors.orange.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    localizations.sniff_device_required_hint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_capabilitySupported != false) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Colors.orange.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localizations.hf_sniff_firmware_unsupported,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isDeviceConnected() {
    return context.read<ChameleonGUIState>().communicator != null;
  }

  Widget _buildStatusBlock() {
    if (_errorMessage != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_errorMessage!),
        ),
      );
    }

    if (_statusMessage == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(_statusMessage!),
    );
  }

  Widget _buildSummaryTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    final summary = capture.summary;
    final amount = summary.amountMinorUnits == null
        ? null
        : '${(summary.amountMinorUnits! ~/ 100)}.${(summary.amountMinorUnits! % 100).toString().padLeft(2, '0')}';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _summaryCard(
              localizations.hf_sniff_frames,
              '${summary.frameCount}',
              '${summary.readerFrameCount} / ${summary.cardFrameCount}',
            ),
            _summaryCard(
              localizations.hf_sniff_uid,
              summary.uid ?? localizations.unknown,
              summary.uid == null
                  ? localizations.hf_sniff_note
                  : localizations.hf_sniff_uid,
            ),
            _summaryCard(
              localizations.hf_sniff_protocol,
              summary.ratsSeen ? 'ISO14443-4' : 'ISO14443-A',
              summary.ratsSeen
                  ? localizations.hf_sniff_protocol
                  : localizations.hf_sniff_note,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.hf_sniff_summary,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _infoRow(localizations.hf_sniff_reader_frames,
                  '${summary.readerFrameCount}'),
              _infoRow(localizations.hf_sniff_card_frames,
                  '${summary.cardFrameCount}'),
              _infoRow(localizations.hf_sniff_uid,
                  summary.uid ?? localizations.unknown),
              _infoRow(localizations.hf_sniff_protocol,
                  summary.ratsSeen ? 'ISO14443-4 (RATS)' : 'ISO14443-A'),
              _infoRow(
                  localizations.hf_sniff_auth,
                  summary.authRequests.isEmpty
                      ? localizations.no
                      : summary.authRequests
                          .map((request) => request.block >= 0
                              ? '${request.keyType} block ${request.block}'
                              : request.keyType)
                          .join(', ')),
              if (summary.aids.isNotEmpty)
                _infoRow(localizations.hf_sniff_aids, summary.aids.join('\n')),
              if (summary.atcLabel != null)
                _infoRow(localizations.hf_sniff_atc, summary.atcLabel!),
              if (amount != null)
                _infoRow(localizations.hf_sniff_amount, amount),
              if (summary.arqcSeen)
                _infoRow(localizations.hf_sniff_auth_type, 'ARQC'),
              if (summary.tcSeen)
                _infoRow(localizations.hf_sniff_auth_type, 'TC'),
              if (summary.halted)
                _infoRow(localizations.hf_sniff_end, 'HALT / DESELECT'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFramesTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    if (capture.annotatedFrames.isEmpty) {
      return _buildEmptyState(localizations.hf_sniff_no_decoded_frames);
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: capture.annotatedFrames.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final annotated = capture.annotatedFrames[index];
        return _buildFrameTranscriptEntry(
          localizations,
          index,
          annotated.frame,
          annotated.label,
        );
      },
    );
  }

  Widget _buildNoncesTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    if (capture.nonceGroups.isEmpty) {
      return _buildEmptyState(localizations.hf_sniff_nonce_groups);
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: capture.nonceGroups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final group = capture.nonceGroups[index];
        return _buildPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.hf_sniff_nonce_group_value(
                  group.block,
                  group.keyType,
                  group.uid,
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              for (int i = 0; i < group.exchanges.length; i++) ...[
                SelectableText(
                  localizations.hf_sniff_nonce_exchange_value(
                    i,
                    group.exchanges[i].ntHex,
                    group.exchanges[i].nrHex,
                    group.exchanges[i].arHex,
                  ),
                  style: const TextStyle(fontFamily: 'RobotoMono'),
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 6),
              SelectableText(
                buildMfkey64Command(group),
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
              const SizedBox(height: 6),
              if (group.canRecover)
                SelectableText(
                  buildMfkey32Command(group),
                  style: const TextStyle(fontFamily: 'RobotoMono'),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copyText(
                      buildMfkey64Command(group),
                      localizations.hf_sniff_command_copied,
                    ),
                    icon: const Icon(Icons.copy),
                    label: Text(localizations.hf_sniff_mfkey64),
                  ),
                  if (group.canRecover)
                    OutlinedButton.icon(
                      onPressed: () => _copyText(
                        buildMfkey32Command(group),
                        localizations.hf_sniff_command_copied,
                      ),
                      icon: const Icon(Icons.copy),
                      label: Text(localizations.hf_sniff_mfkey32),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecoveryTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    final groups = capture.nonceGroups;
    if (groups.isEmpty) {
      return _buildEmptyState(localizations.hf_sniff_nonce_groups);
    }

    final recoverableGroups =
        groups.where((group) => group.canRecover).toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (recoverableGroups.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _isRecoveringAll ? null : _recoverAll,
              icon: _isRecoveringAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.key),
              label: Text(localizations.hf_sniff_recover_all),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final group in groups) ...[
          _buildRecoveryGroup(localizations, group),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildRecoveryGroup(
      AppLocalizations localizations, HfSniffNonceGroup group) {
    final state = _recoveryStates[group.id];

    return _buildPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.hf_sniff_nonce_group_value(
              group.block,
              group.keyType,
              group.uid,
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (!group.canRecover) ...[
            Text(localizations.hf_sniff_nonce_single),
            const SizedBox(height: 8),
            SelectableText(
              buildMfkey64Command(group),
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: state?.isLoading == true
                      ? null
                      : () => _recoverGroup(group),
                  icon: state?.isLoading == true
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.key),
                  label: Text(localizations.hf_sniff_recover_key),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyText(
                    buildMfkey64Command(group),
                    localizations.hf_sniff_command_copied,
                  ),
                  icon: const Icon(Icons.copy),
                  label: Text(localizations.hf_sniff_mfkey64),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyText(
                    buildMfkey32Command(group),
                    localizations.hf_sniff_command_copied,
                  ),
                  icon: const Icon(Icons.copy),
                  label: Text(localizations.hf_sniff_mfkey32),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (state == null) Text(localizations.hf_sniff_recovery_pending),
            if (state?.isLoading == true)
              Text(localizations.hf_sniff_recovery_in_progress),
            if (state?.key != null) ...[
              Text(
                localizations.hf_sniff_recovery_method(state!.method ?? ''),
              ),
              const SizedBox(height: 6),
              SelectableText(
                _formatKey(state.key!),
                style: const TextStyle(
                  fontFamily: 'RobotoMono',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copyText(
                      _formatKey(state.key!),
                      localizations.hf_sniff_key_copied,
                    ),
                    icon: const Icon(Icons.copy),
                    label: Text(localizations.hf_sniff_copy_key),
                  ),
                  FilledButton.icon(
                    onPressed: () => _saveRecoveredKey(group, state.key!),
                    icon: const Icon(Icons.save),
                    label: Text(localizations.save_recovered_keys),
                  ),
                ],
              ),
            ],
            if (state?.error != null) ...[
              const SizedBox(height: 6),
              Text(
                state!.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRawTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    final shownBytes = math.min(capture.rawBytes.length, 1024);
    final shownData =
        Uint8List.fromList(capture.rawBytes.take(shownBytes).toList());

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(localizations.hf_sniff_raw_help(
            shownBytes, capture.rawBytes.length)),
        const SizedBox(height: 12),
        _buildPanel(
          padding: const EdgeInsets.all(12),
          child: HexViewer(
            data: shownData,
            scrollVertically: false,
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        _buildPanel(
          child: SelectableText(
            _rawHexDump(maxBytes: 1024).toUpperCase(),
            style: const TextStyle(fontFamily: 'RobotoMono'),
          ),
        ),
      ],
    );
  }

  Widget _buildFrameTranscriptEntry(
    AppLocalizations localizations,
    int index,
    HfSniffFrame frame,
    String label,
  ) {
    final isReader = frame.isReaderToCard;
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = isReader ? colorScheme.primary : colorScheme.tertiary;
    final bubbleColor = isReader
        ? colorScheme.primaryContainer.withValues(alpha: 0.42)
        : colorScheme.tertiaryContainer.withValues(alpha: 0.46);
    final routeLabel = isReader ? 'reader -> card' : 'card -> reader';
    final bubbleAlignment =
        isReader ? Alignment.centerLeft : Alignment.centerRight;
    final crossAxisAlignment =
        isReader ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    final textAlign = isReader ? TextAlign.left : TextAlign.right;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final bubbleMaxWidth =
            width < 520 ? width * 0.94 : math.min(760.0, width * 0.84);

        return SizedBox(
          width: double.infinity,
          child: Align(
            alignment: bubbleAlignment,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: accentColor.withValues(alpha: 0.28)),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: crossAxisAlignment,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment:
                            isReader ? WrapAlignment.start : WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '#${index + 1}',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            routeLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${frame.bitLength}b',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: accentColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        frame.hexString.toUpperCase(),
                        textAlign: textAlign,
                        style: const TextStyle(
                          fontFamily: 'RobotoMono',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: textAlign,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String value, String subtitle) {
    return SizedBox(
      width: 260,
      child: _buildPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
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
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
