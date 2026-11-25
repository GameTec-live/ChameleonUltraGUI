import 'package:chameleonultragui/connector/ble_race_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct succeeds before the advertisement', () {
    final race = BleRacePolicy()..directSucceeded();
    race.scanSucceeded();
    expect(race.directOwnsLink, isTrue);
    expect(race.scanOwnsLink, isFalse);
  });

  test('scan succeeds before the remembered address', () {
    final race = BleRacePolicy()..scanSucceeded();
    race.directSucceeded();
    expect(race.scanOwnsLink, isTrue);
    expect(race.directOwnsLink, isFalse);
  });

  test('direct failure falls back to the scan result', () {
    final race = BleRacePolicy()..directFailed();
    expect(race.winner, BleRaceWinner.none);
    race.scanSucceeded();
    expect(race.scanOwnsLink, isTrue);
  });

  test('device disappears before either path succeeds', () {
    final race = BleRacePolicy()
      ..directFailed()
      ..scanFailed();
    expect(race.noRoute, isTrue);
    expect(race.winner, BleRaceWinner.none);
  });
}
