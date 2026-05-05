import 'dart:typed_data';

class LfSniffSummary {
  final int sampleCount;
  final int durationUs;
  final int min;
  final int max;
  final int mean;
  final int gapThreshold;
  final int gapCount;
  final int dynamicRange;

  const LfSniffSummary({
    required this.sampleCount,
    required this.durationUs,
    required this.min,
    required this.max,
    required this.mean,
    required this.gapThreshold,
    required this.gapCount,
    required this.dynamicRange,
  });

  double get durationMs => durationUs / 1000;
}

class LfSniffModulationResult {
  final bool hasSignal;
  final String label;
  final int dynamicRange;
  final int? nearestClockDivisor;
  final int? mostCommonRunSamples;
  final int? halfPeriodUs;
  final int? fullPeriodUs;

  const LfSniffModulationResult({
    required this.hasSignal,
    required this.label,
    required this.dynamicRange,
    this.nearestClockDivisor,
    this.mostCommonRunSamples,
    this.halfPeriodUs,
    this.fullPeriodUs,
  });
}

class LfManchesterDecodeResult {
  final int clockDivisor;
  final bool invert;
  final int threshold;
  final List<int> bits;

  const LfManchesterDecodeResult({
    required this.clockDivisor,
    required this.invert,
    required this.threshold,
    required this.bits,
  });

  bool get hasData => bits.isNotEmpty;

  String get bitString => bits.join();

  String get hexString {
    if (bits.isEmpty) {
      return '';
    }

    BigInt value = BigInt.zero;
    for (final bit in bits) {
      value = (value << 1) | BigInt.from(bit);
    }

    String hex = value.toRadixString(16);
    int expectedLength = (bits.length / 4).ceil();
    if (hex.length < expectedLength) {
      hex = hex.padLeft(expectedLength, '0');
    }

    return hex;
  }
}

class LfHexSampleRow {
  final int offset;
  final Uint8List bytes;
  final String levels;

  const LfHexSampleRow({
    required this.offset,
    required this.bytes,
    required this.levels,
  });
}

class LfSniffCapture {
  final Uint8List samples;
  final LfSniffSummary summary;
  final LfSniffModulationResult modulation;

  const LfSniffCapture({
    required this.samples,
    required this.summary,
    required this.modulation,
  });

  factory LfSniffCapture.fromSamples(Uint8List samples) {
    final summary = summarizeLfSniff(samples);
    return LfSniffCapture(
      samples: samples,
      summary: summary,
      modulation: detectLfSniffModulation(samples, summary: summary),
    );
  }
}

const List<int> kLfClockDivisors = <int>[8, 16, 32, 40, 50, 64, 100, 128];

LfSniffSummary summarizeLfSniff(Uint8List samples) {
  if (samples.isEmpty) {
    return const LfSniffSummary(
      sampleCount: 0,
      durationUs: 0,
      min: 0,
      max: 0,
      mean: 0,
      gapThreshold: 0,
      gapCount: 0,
      dynamicRange: 0,
    );
  }

  int minValue = 0xFF;
  int maxValue = 0x00;
  int total = 0;

  for (final sample in samples) {
    if (sample < minValue) {
      minValue = sample;
    }
    if (sample > maxValue) {
      maxValue = sample;
    }
    total += sample;
  }

  final mean = total ~/ samples.length;
  final threshold = mean ~/ 2;
  final steadyStart = samples.length > 200 ? 200 : samples.length;
  int gapCount = 0;
  for (int index = steadyStart; index < samples.length; index++) {
    if (samples[index] < threshold) {
      gapCount++;
    }
  }

  return LfSniffSummary(
    sampleCount: samples.length,
    durationUs: samples.length * 8,
    min: minValue,
    max: maxValue,
    mean: mean,
    gapThreshold: threshold,
    gapCount: gapCount,
    dynamicRange: maxValue - minValue,
  );
}

LfSniffModulationResult detectLfSniffModulation(
  Uint8List samples, {
  LfSniffSummary? summary,
}) {
  final sniffSummary = summary ?? summarizeLfSniff(samples);
  if (samples.isEmpty || sniffSummary.dynamicRange < 0x20) {
    return LfSniffModulationResult(
      hasSignal: false,
      label: 'none',
      dynamicRange: sniffSummary.dynamicRange,
    );
  }

  final bits = _binarize(samples, sniffSummary.gapThreshold);
  final runs = _measureRuns(bits);
  if (runs.length < 4) {
    return LfSniffModulationResult(
      hasSignal: false,
      label: 'insufficient-transitions',
      dynamicRange: sniffSummary.dynamicRange,
    );
  }

  final counts = <int, int>{};
  for (final run in runs) {
    counts.update(run, (value) => value + 1, ifAbsent: () => 1);
  }
  final sortedRuns = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final mostCommonRun = sortedRuns.first.key;
  final fullPeriodUs = mostCommonRun * 2 * 8;
  final nearestClockDivisor = kLfClockDivisors.reduce((current, next) {
    final currentDelta = (current * 8 - fullPeriodUs).abs();
    final nextDelta = (next * 8 - fullPeriodUs).abs();
    return nextDelta < currentDelta ? next : current;
  });

  final uniqueRuns = runs.toSet();
  final longRuns = runs.where((run) => run > mostCommonRun * 3).length;
  final tolerance = _maxInt(2, mostCommonRun ~/ 3);
  final isManchester = sortedRuns.length >= 2 &&
      (sortedRuns[1].key - (mostCommonRun * 2)).abs() <= tolerance;

  String label;
  if (longRuns > runs.length * 0.3) {
    label = 'ask-nrz';
  } else if (isManchester) {
    label = 'manchester';
  } else if (uniqueRuns.length <= 4) {
    label = 'biphase';
  } else {
    label = 'fsk-mixed';
  }

  return LfSniffModulationResult(
    hasSignal: true,
    label: label,
    dynamicRange: sniffSummary.dynamicRange,
    nearestClockDivisor: nearestClockDivisor,
    mostCommonRunSamples: mostCommonRun,
    halfPeriodUs: mostCommonRun * 8,
    fullPeriodUs: fullPeriodUs,
  );
}

LfManchesterDecodeResult decodeLfManchester(
  Uint8List samples, {
  int clockDivisor = 64,
  bool invert = false,
}) {
  if (samples.isEmpty) {
    return LfManchesterDecodeResult(
      clockDivisor: clockDivisor,
      invert: invert,
      threshold: 0,
      bits: const <int>[],
    );
  }

  final summary = summarizeLfSniff(samples);
  final rawBits = _binarize(samples, summary.gapThreshold, invert: invert);
  final runs = _measureBitRuns(rawBits);
  final halfClock = clockDivisor ~/ 2;
  final tolerance = _maxInt(2, halfClock ~/ 3);
  final decodedBits = <int>[];

  int index = 0;
  while (index < runs.length) {
    final (value, count) = runs[index];
    final isHalf = (count - halfClock).abs() <= tolerance;
    final isFull = (count - clockDivisor).abs() <= tolerance;

    if (isHalf && index + 1 < runs.length) {
      final (nextValue, nextCount) = runs[index + 1];
      final nextIsHalf = (nextCount - halfClock).abs() <= tolerance;
      if (nextIsHalf) {
        if (value == 0 && nextValue == 1) {
          decodedBits.add(0);
        } else if (value == 1 && nextValue == 0) {
          decodedBits.add(1);
        }
        index += 2;
        continue;
      }
    } else if (isFull) {
      decodedBits.add(value);
    }

    index += 1;
  }

  return LfManchesterDecodeResult(
    clockDivisor: clockDivisor,
    invert: invert,
    threshold: summary.gapThreshold,
    bits: decodedBits,
  );
}

List<LfHexSampleRow> buildLfHexRows(
  Uint8List samples, {
  int maxBytes = 512,
  int bytesPerRow = 16,
}) {
  final output = <LfHexSampleRow>[];
  final limit = samples.length < maxBytes ? samples.length : maxBytes;
  for (int offset = 0; offset < limit; offset += bytesPerRow) {
    final end = _minInt(offset + bytesPerRow, limit);
    final row = Uint8List.fromList(samples.sublist(offset, end));
    output.add(
      LfHexSampleRow(
        offset: offset,
        bytes: row,
        levels: _levelBar(row),
      ),
    );
  }
  return output;
}

List<int> _binarize(
  Uint8List samples,
  int threshold, {
  bool invert = false,
}) {
  return samples.map((sample) {
    int bit = sample > threshold ? 1 : 0;
    if (invert) {
      bit = 1 - bit;
    }
    return bit;
  }).toList(growable: false);
}

List<int> _measureRuns(List<int> bits) {
  if (bits.isEmpty) {
    return const <int>[];
  }

  final runs = <int>[];
  int current = bits.first;
  int count = 1;

  for (final bit in bits.skip(1)) {
    if (bit == current) {
      count++;
    } else {
      runs.add(count);
      current = bit;
      count = 1;
    }
  }

  runs.add(count);
  return runs;
}

List<(int, int)> _measureBitRuns(List<int> bits) {
  if (bits.isEmpty) {
    return const <(int, int)>[];
  }

  final runs = <(int, int)>[];
  int current = bits.first;
  int count = 1;

  for (final bit in bits.skip(1)) {
    if (bit == current) {
      count++;
    } else {
      runs.add((current, count));
      current = bit;
      count = 1;
    }
  }

  runs.add((current, count));
  return runs;
}

String levelGlyph(int value) {
  if (value < 0x10) {
    return '_';
  }
  if (value < 0x40) {
    return '.';
  }
  if (value < 0x80) {
    return '-';
  }
  if (value < 0xA0) {
    return '+';
  }
  if (value < 0xC0) {
    return 'o';
  }
  if (value < 0xE0) {
    return 'O';
  }
  return '#';
}

String _levelBar(Uint8List row) {
  final buffer = StringBuffer();
  for (final value in row) {
    buffer.write(levelGlyph(value));
  }
  return buffer.toString();
}

int _minInt(int a, int b) => a < b ? a : b;

int _maxInt(int a, int b) => a > b ? a : b;
