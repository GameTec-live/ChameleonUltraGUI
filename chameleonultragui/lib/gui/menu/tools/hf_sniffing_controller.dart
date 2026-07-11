part of 'hf_sniffing.dart';

// Capture, export, and key recovery behavior for the sniffing page.
extension on _HfSniffingMenuState {
  Future<void> _loadCapabilities() async {
    final appState = context.read<ChameleonGUIState>();
    try {
      final capabilities = await appState.communicator!.getDeviceCapabilities();
      if (!mounted) {
        return;
      }
      updateSniffingState(() {
        _capabilitySupported =
            capabilities.contains(ChameleonCommand.hf14aSniff.value);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      updateSniffingState(() {
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

    updateSniffingState(() {
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
        updateSniffingState(() {
          _statusMessage = localizations.hf_sniff_no_frames;
        });
        return;
      }

      final capture = HfSniffCapture.fromRawBytes(rawBytes);
      updateSniffingState(() {
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
      updateSniffingState(() {
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
        updateSniffingState(() {
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
      fileName: '$filename.bin',
      bytes: capture.rawBytes,
    );

    if (outputFile != null && mounted) {
      _showSnack(localizations.save_to_file);
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

    updateSniffingState(() {
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

      if (mfkey64Result.isNotEmpty &&
          mfkey64Result.first != _HfSniffingMenuState._kNoKey) {
        if (!mounted) {
          return;
        }
        updateSniffingState(() {
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

      if (mfkey32Result.isNotEmpty &&
          mfkey32Result.first != _HfSniffingMenuState._kNoKey) {
        updateSniffingState(() {
          _recoveryStates[group.id] = _HfSniffRecoveryState(
            key: mfkey32Result.first,
            method: 'mfkey32',
          );
        });
      } else {
        updateSniffingState(() {
          _recoveryStates[group.id] = _HfSniffRecoveryState(
            error: localizations.hf_sniff_recovery_failed,
          );
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      updateSniffingState(() {
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

    updateSniffingState(() {
      _isRecoveringAll = true;
    });

    try {
      for (final group in groups) {
        await _recoverGroup(group);
      }
    } finally {
      if (mounted) {
        updateSniffingState(() {
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
}
