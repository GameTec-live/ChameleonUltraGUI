part of 'lf_sniffing.dart';

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
