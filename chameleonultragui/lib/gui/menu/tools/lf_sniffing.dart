import 'dart:io';
import 'dart:math' as math;

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/hex_viewer.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/lf_sniff.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class LfSniffingMenu extends StatefulWidget {
  const LfSniffingMenu({super.key});

  @override
  State<LfSniffingMenu> createState() => _LfSniffingMenuState();
}

class _LfSniffingMenuState extends State<LfSniffingMenu> {
  final _formKey = GlobalKey<FormState>();
  final _timeoutController = TextEditingController(text: '2000');
  final _clockController = TextEditingController(text: '64');
  final _waveformScrollController = ScrollController();

  bool _isCapturing = false;
  bool _invertDecode = false;
  double _expandedWaveformZoom = 1.0;
  bool? _capabilitySupported;
  String? _statusMessage;
  String? _errorMessage;
  String? _decodeError;

  LfSniffCapture? _capture;
  LfManchesterDecodeResult? _decodeResult;

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
    _clockController.dispose();
    _waveformScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCapabilities() async {
    final appState = context.read<ChameleonGUIState>();
    try {
      final capabilities = await appState.communicator!.getDeviceCapabilities();
      if (!mounted) {
        return;
      }
      setState(() {
        _capabilitySupported =
            capabilities.contains(ChameleonCommand.lfSniff.value);
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

  Future<void> _captureLfSamples() async {
    final localizations = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final timeoutMs = int.parse(_timeoutController.text);
    final appState = context.read<ChameleonGUIState>();

    setState(() {
      _isCapturing = true;
      _errorMessage = null;
      _statusMessage = localizations.lf_sniff_capture_in_progress(timeoutMs);
    });

    try {
      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      final samples =
          await appState.communicator!.lfSniff(timeoutMs: timeoutMs);
      if (!mounted) {
        return;
      }

      if (samples.isEmpty) {
        setState(() {
          _capture = null;
          _decodeResult = null;
          _decodeError = null;
          _statusMessage = localizations.lf_sniff_no_samples;
        });
        return;
      }

      final capture = LfSniffCapture.fromSamples(samples);
      final decodeOutcome = _buildDecodeResult(capture.samples);

      setState(() {
        _capture = capture;
        _decodeResult = decodeOutcome.result;
        _decodeError = decodeOutcome.error;
        _statusMessage =
            localizations.lf_sniff_capture_done(capture.summary.sampleCount);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final errorText = error.toString();
      setState(() {
        if (errorText.contains('0x67') || errorText.contains('0x69')) {
          _capabilitySupported = false;
        }
        _errorMessage = errorText;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  ({LfManchesterDecodeResult? result, String? error}) _buildDecodeResult(
      Uint8List samples) {
    final localizations = AppLocalizations.of(context)!;
    final clockDivisor = int.tryParse(_clockController.text);
    if (clockDivisor == null ||
        !kLfClockDivisors.contains(clockDivisor) ||
        clockDivisor <= 0) {
      return (
        result: null,
        error: localizations.lf_sniff_invalid_clock,
      );
    }

    return (
      result: decodeLfManchester(samples,
          clockDivisor: clockDivisor, invert: _invertDecode),
      error: null,
    );
  }

  void _refreshDecode() {
    if (_capture == null) {
      return;
    }

    final decodeOutcome = _buildDecodeResult(_capture!.samples);
    setState(() {
      _decodeResult = decodeOutcome.result;
      _decodeError = decodeOutcome.error;
    });
  }

  Future<void> _exportCapture() async {
    final capture = _capture;
    if (capture == null) {
      return;
    }

    final localizations = AppLocalizations.of(context)!;
    final filename =
        'lf-sniff-${DateTime.now().toIso8601String().replaceAll(':', '-')}';

    try {
      await FileSaver.instance.saveAs(
          name: filename,
          bytes: capture.samples,
          ext: 'bin',
          mimeType: MimeType.other);
      _showSnack(localizations.save_to_file);
    } on UnimplementedError catch (_) {
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '${localizations.output_file}:',
        fileName: '$filename.bin',
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(capture.samples);
        if (mounted) {
          _showSnack(localizations.save_to_file);
        }
      }
    }
  }

  Future<void> _copyText(String text, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _showSnack(successMessage);
    }
  }

  void _showSnack(String message) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.hideCurrentSnackBar();
    scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _hexPreview({int maxBytes = 512}) {
    final capture = _capture;
    if (capture == null) {
      return '';
    }

    final rows = buildLfHexRows(capture.samples, maxBytes: maxBytes);
    final buffer = StringBuffer();
    for (final row in rows) {
      final hexPart = row.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      buffer.writeln(
          '${row.offset.toRadixString(16).padLeft(4, '0')}  ${hexPart.padRight(47)}  ${row.levels}');
    }
    return buffer.toString().trimRight();
  }

  String _groupBits(String bitString, {int width = 64}) {
    if (bitString.isEmpty) {
      return '';
    }

    final lines = <String>[];
    for (int index = 0; index < bitString.length; index += width) {
      final end = math.min(index + width, bitString.length);
      lines.add(bitString.substring(index, end));
    }
    return lines.join('\n');
  }

  String _modulationLabel(
      AppLocalizations localizations, LfSniffModulationResult modulation) {
    switch (modulation.label) {
      case 'none':
        return localizations.lf_sniff_modulation_none;
      case 'insufficient-transitions':
        return localizations.lf_sniff_modulation_insufficient;
      case 'manchester':
        return localizations.lf_sniff_modulation_manchester;
      case 'ask-nrz':
        return localizations.lf_sniff_modulation_ask_nrz;
      case 'biphase':
        return localizations.lf_sniff_modulation_biphase;
      default:
        return localizations.lf_sniff_modulation_fsk_mixed;
    }
  }

  Color _lfSampleColor(
    BuildContext context,
    LfSniffSummary summary,
    int offset,
    int value,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warmupColor =
        isDark ? Colors.deepOrangeAccent.shade100 : Colors.deepOrange.shade400;
    final lowColor =
        isDark ? Colors.amberAccent.shade200 : Colors.amber.shade700;
    final carrierColor =
        isDark ? Colors.cyanAccent.shade100 : Colors.blue.shade700;
    final peakColor =
        isDark ? Colors.lightGreenAccent.shade200 : Colors.green.shade700;

    if (offset >= 200 && value < summary.gapThreshold) {
      return colorScheme.error;
    }
    if (value < summary.gapThreshold) {
      return warmupColor;
    }
    if (value <= summary.mean) {
      return lowColor;
    }
    if (value < summary.max) {
      return carrierColor;
    }
    return peakColor;
  }

  Future<double?> _showWaveformDialog(LfSniffCapture capture) async {
    final localizations = AppLocalizations.of(context)!;
    final summary = capture.summary;
    final overlayController = ScrollController();

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        double zoom = _expandedWaveformZoom;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final mediaQuery = MediaQuery.of(context);
            final dialogWidth = math.min(mediaQuery.size.width * 0.96, 1100.0);
            final dialogHeight =
                math.min(mediaQuery.size.height * 0.9, 760.0).toDouble();
            final availablePlotWidth = math.max(320.0, dialogWidth - 64);
            final plotWidth = availablePlotWidth * zoom;
            final compactControls = dialogWidth < 640;

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.lf_sniff_waveform,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      _LfWaveformZoomControls(
                        label: localizations.lf_sniff_zoom,
                        zoom: zoom,
                        compact: compactControls,
                        onChanged: (value) {
                          setDialogState(() {
                            zoom = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(localizations.lf_sniff_mean_value(
                                '0x${summary.mean.toRadixString(16).padLeft(2, '0')}')),
                          ),
                          Chip(
                            label: Text(localizations.lf_sniff_gap_threshold_value(
                                '0x${summary.gapThreshold.toRadixString(16).padLeft(2, '0')}')),
                          ),
                          Chip(
                            label: Text(localizations.lf_sniff_samples_value(
                                '${summary.sampleCount}')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _LfWaveformSurface(
                          capture: capture,
                          plotWidth: plotWidth,
                          plotHeight: dialogHeight - 220,
                          controller: overlayController,
                          scrollbarThickness: 10,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(zoom),
                          child: Text(localizations.close),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    overlayController.dispose();
    return result;
  }

  Future<void> _openWaveformViewer(LfSniffCapture capture) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 700;
    final zoom = isCompact
        ? await Navigator.of(context).push<double>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (context) => _LfWaveformFullscreenPage(
                capture: capture,
                initialZoom: _expandedWaveformZoom,
              ),
            ),
          )
        : await _showWaveformDialog(capture);

    if (!mounted || zoom == null) {
      return;
    }

    setState(() {
      _expandedWaveformZoom = zoom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final dialogWidth =
        math.min(MediaQuery.of(context).size.width * 0.92, 920.0).toDouble();
    final dialogHeight =
        math.min(MediaQuery.of(context).size.height * 0.82, 760.0).toDouble();

    return AlertDialog(
      title: Text(localizations.lf_sniffing),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;
            return DefaultTabController(
              length: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCapabilityBanner(localizations),
                  Form(
                    key: _formKey,
                    child: _buildHeaderControls(localizations, isWide),
                  ),
                  if (_statusMessage != null || _errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildStatusBlock(),
                    ),
                  const Padding(padding: EdgeInsets.only(top: 12)),
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: localizations.lf_sniff_summary),
                      Tab(text: localizations.lf_sniff_waveform),
                      Tab(text: localizations.lf_sniff_decode),
                      Tab(text: localizations.lf_sniff_hex),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.only(top: 12)),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildSummaryTab(localizations),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildWaveformTab(localizations),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildDecodeTab(localizations),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildHexTab(localizations),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
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

  Widget _buildCaptureField(AppLocalizations localizations) {
    return TextFormField(
      controller: _timeoutController,
      enabled: !_isCapturing,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: localizations.lf_sniff_timeout,
        helperText: localizations.lf_sniff_timeout_help,
        border: const OutlineInputBorder(),
      ),
      validator: (value) => validateIntRange(
        value,
        localizations,
        min: 1,
        max: 10000,
      ),
    );
  }

  Widget _buildHeaderControls(AppLocalizations localizations, bool isWide) {
    const fieldWidth = 430.0;

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: fieldWidth),
            child: _buildCaptureField(localizations),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildActionButtons(localizations, centerToField: true),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCaptureField(localizations),
        const SizedBox(height: 12),
        _buildActionButtons(localizations, centerToField: false),
      ],
    );
  }

  Widget _buildActionButtons(
    AppLocalizations localizations, {
    required bool centerToField,
  }) {
    return Align(
      alignment: centerToField ? Alignment.centerLeft : Alignment.topLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: centerToField
            ? WrapCrossAlignment.center
            : WrapCrossAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: (_isCapturing || _capabilitySupported == false)
                ? null
                : _captureLfSamples,
            icon: _isCapturing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  )
                : const Icon(Icons.sensors),
            label: Text(localizations.lf_sniff_capture),
          ),
          OutlinedButton.icon(
            onPressed: _capture == null ? null : _exportCapture,
            icon: const Icon(Icons.download),
            label: Text(localizations.save_to_file),
          ),
          OutlinedButton.icon(
            onPressed: _capture == null
                ? null
                : () => _copyText(
                      _hexPreview(),
                      localizations.lf_sniff_hex_copied,
                    ),
            icon: const Icon(Icons.copy_all),
            label: Text(localizations.lf_sniff_copy_hex),
          ),
        ],
      ),
    );
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
          child: Text(
            _errorMessage!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      );
    }

    return Text(
      _statusMessage!,
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }

  Widget _buildCapabilityBanner(AppLocalizations localizations) {
    if (_capabilitySupported != false) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Colors.orange.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(localizations.lf_sniff_firmware_unsupported),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.lf_sniff_capture_prompt);
    }

    final summary = capture.summary;
    final modulation = capture.modulation;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final cardWidth =
            availableWidth >= 560 ? (availableWidth - 12) / 2 : availableWidth;

        return ListView(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.start,
              children: [
                _summaryCard(
                  context,
                  localizations.lf_sniff_samples,
                  '${summary.sampleCount}',
                  localizations.lf_sniff_duration_value(summary.durationMs
                      .toStringAsFixed(summary.durationMs.truncateToDouble() ==
                              summary.durationMs
                          ? 0
                          : 1)),
                  width: cardWidth,
                ),
                _summaryCard(
                  context,
                  localizations.lf_sniff_range,
                  '0x${summary.min.toRadixString(16).padLeft(2, '0')} - '
                  '0x${summary.max.toRadixString(16).padLeft(2, '0')}',
                  localizations.lf_sniff_mean_value(
                      '0x${summary.mean.toRadixString(16).padLeft(2, '0')}'),
                  width: cardWidth,
                ),
                _summaryCard(
                  context,
                  localizations.lf_sniff_gaps,
                  '${summary.gapCount}',
                  localizations.lf_sniff_gap_threshold_value(
                      '0x${summary.gapThreshold.toRadixString(16).padLeft(2, '0')}'),
                  width: cardWidth,
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations.lf_sniff_modulation,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          children: [
                            _compactInfoColumn(
                              localizations.lf_sniff_modulation_type,
                              _modulationLabel(localizations, modulation),
                            ),
                            _compactInfoColumn(
                              localizations.lf_sniff_dynamic_range,
                              '${modulation.dynamicRange}',
                            ),
                            if (modulation.nearestClockDivisor != null)
                              _compactInfoColumn(
                                localizations.lf_sniff_nearest_clock,
                                localizations.lf_sniff_clock_value(
                                    '${modulation.nearestClockDivisor}'),
                              ),
                            if (modulation.mostCommonRunSamples != null)
                              _compactInfoColumn(
                                localizations.lf_sniff_half_period,
                                localizations.lf_sniff_period_value(
                                    '${modulation.mostCommonRunSamples}',
                                    '${modulation.halfPeriodUs ?? 0}'),
                              ),
                            if (modulation.fullPeriodUs != null)
                              _compactInfoColumn(
                                localizations.lf_sniff_full_period,
                                localizations.lf_sniff_microseconds(
                                    '${modulation.fullPeriodUs}'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildWaveformTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.lf_sniff_capture_prompt);
    }

    final summary = capture.summary;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 700;
    final plotHeight = isCompact ? 320.0 : 280.0;
    final plotWidth = math.max(
      isCompact ? 720.0 : 640.0,
      capture.samples.length * (isCompact ? 3.0 : 2.0),
    );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (isCompact) ...[
          Text(
            localizations.lf_sniff_waveform_help,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openWaveformViewer(capture),
              icon: const Icon(Icons.open_in_full),
              label: Text(localizations.expand),
            ),
          ),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  localizations.lf_sniff_waveform_help,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _openWaveformViewer(capture),
                icon: const Icon(Icons.open_in_full),
                label: Text(localizations.expand),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(localizations.lf_sniff_mean_value(
                  '0x${summary.mean.toRadixString(16).padLeft(2, '0')}')),
            ),
            Chip(
              label: Text(localizations.lf_sniff_gap_threshold_value(
                  '0x${summary.gapThreshold.toRadixString(16).padLeft(2, '0')}')),
            ),
            Chip(
              label: Text(localizations
                  .lf_sniff_samples_value('${summary.sampleCount}')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: plotHeight,
          child: _LfWaveformSurface(
            capture: capture,
            plotWidth: plotWidth,
            plotHeight: plotHeight,
            controller: _waveformScrollController,
          ),
        ),
      ],
    );
  }

  Widget _buildDecodeTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.lf_sniff_capture_prompt);
    }

    final decodeResult = _decodeResult;
    final bitPreview =
        decodeResult == null ? '' : _groupBits(decodeResult.bitString);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplitPanels = constraints.maxWidth >= 760;
        final summaryWidth = useSplitPanels ? 280.0 : constraints.maxWidth;

        return ListView(
          clipBehavior: Clip.none,
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: TextFormField(
                controller: _clockController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: localizations.lf_sniff_clock_divisor,
                  helperText: localizations.lf_sniff_clock_help,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null || !kLfClockDivisors.contains(parsed)) {
                    return localizations.lf_sniff_invalid_clock;
                  }
                  return null;
                },
                onChanged: (_) => _refreshDecode(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  selected: _invertDecode,
                  label: Text(localizations.lf_sniff_invert),
                  onSelected: (selected) {
                    setState(() {
                      _invertDecode = selected;
                    });
                    _refreshDecode();
                  },
                ),
                OutlinedButton.icon(
                  onPressed: _refreshDecode,
                  icon: const Icon(Icons.refresh),
                  label: Text(localizations.lf_sniff_refresh_decode),
                ),
                OutlinedButton.icon(
                  onPressed: decodeResult == null || !decodeResult.hasData
                      ? null
                      : () => _copyText(
                            bitPreview,
                            localizations.lf_sniff_bits_copied,
                          ),
                  icon: const Icon(Icons.copy_all),
                  label: Text(localizations.lf_sniff_copy_bits),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_decodeError != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _decodeError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              )
            else if (decodeResult == null || !decodeResult.hasData)
              _buildEmptyState(localizations.lf_sniff_no_decode)
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: summaryWidth,
                    child: _buildPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _compactInfoColumn(
                            localizations.lf_sniff_bits,
                            '${decodeResult.bits.length}',
                          ),
                          const Padding(padding: EdgeInsets.only(top: 12)),
                          _compactInfoColumn(
                            localizations.lf_sniff_threshold,
                            '0x${decodeResult.threshold.toRadixString(16).padLeft(2, '0')}',
                          ),
                          if (decodeResult.hexString.isNotEmpty) ...[
                            const Padding(padding: EdgeInsets.only(top: 16)),
                            Text(
                              localizations.lf_sniff_hex_preview,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const Padding(padding: EdgeInsets.only(top: 8)),
                            SelectableText(
                              decodeResult.hexString.toUpperCase(),
                              style: const TextStyle(fontFamily: 'RobotoMono'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: useSplitPanels
                        ? constraints.maxWidth - summaryWidth - 12
                        : constraints.maxWidth,
                    child: _buildPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localizations.lf_sniff_bitstream,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Padding(padding: EdgeInsets.only(top: 8)),
                          SelectableText(
                            bitPreview,
                            style: const TextStyle(fontFamily: 'RobotoMono'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildHexTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.lf_sniff_capture_prompt);
    }

    final shownBytes = math.min(capture.samples.length, 512);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildHexLegend(localizations, capture.summary),
        const SizedBox(height: 10),
        Text(localizations.lf_sniff_hex_help(
            shownBytes, capture.samples.length)),
        const SizedBox(height: 12),
        _buildPanel(
          padding: const EdgeInsets.all(12),
          child: HexViewer(
            data: Uint8List.fromList(capture.samples.take(shownBytes).toList()),
            scrollVertically: false,
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
            indexedByteColorBuilder: (offset, value) =>
                _lfSampleColor(context, capture.summary, offset, value),
            trailingTextBuilder: (row) =>
                row.map((value) => levelGlyph(value)).join(),
          ),
        ),
      ],
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

  Widget _summaryCard(
      BuildContext context, String title, String value, String subtitle,
      {required double width}) {
    return SizedBox(
      width: width,
      child: _buildPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const Padding(padding: EdgeInsets.only(top: 8)),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const Padding(padding: EdgeInsets.only(top: 8)),
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

  Widget _compactInfoColumn(String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Padding(padding: EdgeInsets.only(top: 4)),
          Text(
            value,
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildHexLegend(
      AppLocalizations localizations, LfSniffSummary summary) {
    final thresholdHex =
        '0x${summary.gapThreshold.toRadixString(16).padLeft(2, '0')}';
    final meanHex = '0x${summary.mean.toRadixString(16).padLeft(2, '0')}';
    final maxHex = '0x${summary.max.toRadixString(16).padLeft(2, '0')}';
    final warmupProbe = summary.gapThreshold > 0 ? summary.gapThreshold - 1 : 0;
    final lowProbe = summary.gapThreshold <= summary.mean
        ? summary.gapThreshold
        : summary.mean;
    final carrierProbe =
        summary.mean < summary.max ? summary.mean + 1 : summary.mean;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        final colorLegend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.lf_sniff_hex_color_title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              localizations.lf_sniff_hex_color_scale(
                thresholdHex,
                meanHex,
                maxHex,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _buildHexColorLegendItem(
                  color: _lfSampleColor(context, summary, 200, warmupProbe),
                  label: localizations.lf_sniff_hex_color_gap,
                ),
                _buildHexColorLegendItem(
                  color: _lfSampleColor(context, summary, 0, warmupProbe),
                  label: localizations.lf_sniff_hex_color_warmup,
                ),
                _buildHexColorLegendItem(
                  color: _lfSampleColor(context, summary, 250, lowProbe),
                  label: localizations.lf_sniff_hex_color_low,
                ),
                _buildHexColorLegendItem(
                  color: _lfSampleColor(context, summary, 250, carrierProbe),
                  label: localizations.lf_sniff_hex_color_carrier,
                ),
                _buildHexColorLegendItem(
                  color: _lfSampleColor(context, summary, 250, summary.max),
                  label: localizations.lf_sniff_hex_color_peak,
                ),
              ],
            ),
          ],
        );

        final glyphLegend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.lf_sniff_hex_glyph_title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _buildHexGlyphLegendItem(
                  glyph: '_',
                  label: localizations.lf_sniff_hex_glyph_gap,
                ),
                _buildHexGlyphLegendItem(
                  glyph: '.',
                  label: localizations.lf_sniff_hex_glyph_ringing,
                ),
                _buildHexGlyphLegendItem(
                  glyph: '-',
                  label: localizations.lf_sniff_hex_glyph_low,
                ),
                _buildHexGlyphLegendItem(
                  glyph: '+',
                  label: localizations.lf_sniff_hex_glyph_mid,
                ),
                _buildHexGlyphLegendItem(
                  glyph: 'o',
                  label: localizations.lf_sniff_hex_glyph_carrier,
                ),
                _buildHexGlyphLegendItem(
                  glyph: 'O',
                  label: localizations.lf_sniff_hex_glyph_high,
                ),
                _buildHexGlyphLegendItem(
                  glyph: '#',
                  label: localizations.lf_sniff_hex_glyph_clipped,
                ),
              ],
            ),
          ],
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: colorLegend),
              const SizedBox(width: 24),
              Expanded(child: glyphLegend),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            colorLegend,
            const SizedBox(height: 12),
            glyphLegend,
          ],
        );
      },
    );
  }

  Widget _buildHexColorLegendItem({
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildHexGlyphLegendItem({
    required String glyph,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          glyph,
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _LfWaveformSurface extends StatelessWidget {
  final LfSniffCapture capture;
  final double plotWidth;
  final double plotHeight;
  final ScrollController controller;
  final double scrollbarThickness;

  const _LfWaveformSurface({
    required this.capture,
    required this.plotWidth,
    required this.plotHeight,
    required this.controller,
    this.scrollbarThickness = 8,
  });

  @override
  Widget build(BuildContext context) {
    final summary = capture.summary;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: RawScrollbar(
          controller: controller,
          thumbVisibility: true,
          radius: const Radius.circular(8),
          thickness: scrollbarThickness,
          child: SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            child: CustomPaint(
              size: Size(plotWidth, plotHeight),
              painter: _LfWaveformPainter(
                samples: capture.samples,
                mean: summary.mean,
                threshold: summary.gapThreshold,
                colorScheme: Theme.of(context).colorScheme,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LfWaveformFullscreenPage extends StatefulWidget {
  final LfSniffCapture capture;
  final double initialZoom;

  const _LfWaveformFullscreenPage({
    required this.capture,
    required this.initialZoom,
  });

  @override
  State<_LfWaveformFullscreenPage> createState() =>
      _LfWaveformFullscreenPageState();
}

class _LfWaveformFullscreenPageState extends State<_LfWaveformFullscreenPage> {
  late final ScrollController _scrollController;
  late double _zoom;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _zoom = widget.initialZoom;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final summary = widget.capture.summary;
    final mediaQuery = MediaQuery.of(context);
    final plotHeight = math.max(320.0, mediaQuery.size.height - 260);
    final availablePlotWidth = math.max(320.0, mediaQuery.size.width - 32);
    final plotWidth = availablePlotWidth * _zoom;
    final compactControls = mediaQuery.size.width < 520;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.lf_sniff_waveform),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(_zoom),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              localizations.lf_sniff_waveform_help,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _LfWaveformZoomControls(
              label: localizations.lf_sniff_zoom,
              zoom: _zoom,
              compact: compactControls,
              onChanged: (value) {
                setState(() {
                  _zoom = value;
                });
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(localizations.lf_sniff_mean_value(
                      '0x${summary.mean.toRadixString(16).padLeft(2, '0')}')),
                ),
                Chip(
                  label: Text(localizations.lf_sniff_gap_threshold_value(
                      '0x${summary.gapThreshold.toRadixString(16).padLeft(2, '0')}')),
                ),
                Chip(
                  label: Text(localizations
                      .lf_sniff_samples_value('${summary.sampleCount}')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: plotHeight,
              child: _LfWaveformSurface(
                capture: widget.capture,
                plotWidth: plotWidth,
                plotHeight: plotHeight,
                controller: _scrollController,
                scrollbarThickness: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LfWaveformZoomControls extends StatelessWidget {
  final String label;
  final double zoom;
  final bool compact;
  final ValueChanged<double> onChanged;

  const _LfWaveformZoomControls({
    required this.label,
    required this.zoom,
    required this.compact,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final slider = Slider(
      value: zoom,
      min: 1.0,
      max: 32.0,
      divisions: 14,
      label: '${zoom.toStringAsFixed(1)}x',
      onChanged: onChanged,
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          slider,
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SizedBox(
          width: 280,
          child: slider,
        ),
      ],
    );
  }
}

class _LfWaveformPainter extends CustomPainter {
  final Uint8List samples;
  final int mean;
  final int threshold;
  final ColorScheme colorScheme;

  const _LfWaveformPainter({
    required this.samples,
    required this.mean,
    required this.threshold,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      return;
    }

    final gapPaint = Paint()
      ..color = colorScheme.error.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final meanPaint = Paint()
      ..color = colorScheme.secondary
      ..strokeWidth = 1.2;
    final thresholdPaint = Paint()
      ..color = colorScheme.error
      ..strokeWidth = 1.2;
    final waveformPaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final gridPaint = Paint()
      ..color = colorScheme.outline.withValues(alpha: 0.25)
      ..strokeWidth = 1.0;

    final usableHeight = size.height - 24;
    final sampleStep =
        samples.length > 1 ? size.width / (samples.length - 1) : 0.0;

    for (final factor in <double>[0.25, 0.5, 0.75]) {
      final y = usableHeight * factor + 8;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    int? gapStartIndex;
    for (int index = 0; index < samples.length; index++) {
      final isGap = samples[index] < threshold;
      if (isGap && gapStartIndex == null) {
        gapStartIndex = index;
      } else if (!isGap && gapStartIndex != null) {
        canvas.drawRect(
          Rect.fromLTWH(gapStartIndex * sampleStep, 0,
              (index - gapStartIndex) * sampleStep, size.height),
          gapPaint,
        );
        gapStartIndex = null;
      }
    }
    if (gapStartIndex != null) {
      canvas.drawRect(
        Rect.fromLTWH(gapStartIndex * sampleStep, 0,
            size.width - gapStartIndex * sampleStep, size.height),
        gapPaint,
      );
    }

    final meanY = usableHeight - (mean / 255) * usableHeight + 8;
    final thresholdY = usableHeight - (threshold / 255) * usableHeight + 8;
    canvas.drawLine(Offset(0, meanY), Offset(size.width, meanY), meanPaint);
    canvas.drawLine(
        Offset(0, thresholdY), Offset(size.width, thresholdY), thresholdPaint);

    final path = Path();
    for (int index = 0; index < samples.length; index++) {
      final x = index * sampleStep;
      final y = usableHeight - (samples[index] / 255) * usableHeight + 8;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, waveformPaint);
  }

  @override
  bool shouldRepaint(covariant _LfWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.mean != mean ||
        oldDelegate.threshold != threshold ||
        oldDelegate.colorScheme != colorScheme;
  }
}
