enum BleRaceWinner { none, direct, scan }

/// First-wins state machine for the "remembered address" and "advertisement"
/// connection paths. The connector keeps its hardware state separate; this
/// class only records which attempt owns the link.
class BleRacePolicy {
  BleRaceWinner winner = BleRaceWinner.none;
  bool directActive = true;
  bool scanActive = true;

  void directSucceeded() {
    if (winner == BleRaceWinner.none) {
      winner = BleRaceWinner.direct;
    }
  }

  void scanSucceeded() {
    if (winner == BleRaceWinner.none) {
      winner = BleRaceWinner.scan;
    }
  }

  void directFailed() {
    directActive = false;
  }

  void scanFailed() {
    scanActive = false;
  }

  bool get directOwnsLink => winner == BleRaceWinner.direct;
  bool get scanOwnsLink => winner == BleRaceWinner.scan;
  bool get noRoute =>
      winner == BleRaceWinner.none && !directActive && !scanActive;
}
