import 'dart:typed_data';

import 'package:chameleonultragui/helpers/lf_sniff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summarizeLfSniff counts post-startup gaps', () {
    final samples = Uint8List.fromList([
      ...List<int>.filled(200, 0xB0),
      0xB0,
      0x00,
      0x10,
      0xB0,
    ]);

    final summary = summarizeLfSniff(samples);

    expect(summary.sampleCount, samples.length);
    expect(summary.durationUs, samples.length * 8);
    expect(summary.min, 0x00);
    expect(summary.max, 0xB0);
    expect(summary.gapCount, 2);
    expect(summary.gapThreshold, lessThan(summary.mean));
  });

  test('detectLfSniffModulation reports flat carrier as none', () {
    final samples = Uint8List.fromList(List<int>.filled(400, 0x80));

    final modulation = detectLfSniffModulation(samples);

    expect(modulation.hasSignal, isFalse);
    expect(modulation.label, 'none');
  });

  test('Manchester synthetic waveform decodes and identifies modulation', () {
    final samples = _buildManchesterSamples([0, 0, 0]);

    final modulation = detectLfSniffModulation(samples);
    final decode = decodeLfManchester(samples, clockDivisor: 64);

    expect(modulation.hasSignal, isTrue);
    expect(decode.bits, [0, 0, 0]);
    expect(decode.hexString, '0');
  });
}

Uint8List _buildManchesterSamples(
  List<int> bits, {
  int halfClock = 32,
  int low = 0x10,
  int high = 0xE0,
}) {
  final samples = <int>[];

  for (final bit in bits) {
    if (bit == 0) {
      samples.addAll(List<int>.filled(halfClock, low));
      samples.addAll(List<int>.filled(halfClock, high));
    } else {
      samples.addAll(List<int>.filled(halfClock, high));
      samples.addAll(List<int>.filled(halfClock, low));
    }
  }

  return Uint8List.fromList(samples);
}
