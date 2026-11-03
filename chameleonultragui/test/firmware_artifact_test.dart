import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> artifact(int id, String name, int runId, String sha,
    {String branch = "main", int repo = 581338100, bool expired = false}) {
  return {
    "id": id,
    "name": name,
    "expired": expired,
    "workflow_run": {
      "id": runId,
      "head_branch": branch,
      "head_repository_id": repo,
      "head_sha": sha,
    },
  };
}

String? latestSha(List<dynamic> artifacts, ChameleonDevice device) {
  final artifact = selectLatestFirmwareArtifact(artifacts, device);
  return artifact?["workflow_run"]["head_sha"];
}

void main() {
  test('picks the newest main build rather than the first one listed', () {
    // ultra-dfu-app artifacts in the order the API returned them right after
    // ChameleonUltra v2.3.0 was tagged. The first main build listed (4ffb6574)
    // predates the tag and reports itself as v2.2.0.
    final artifacts = [
      artifact(12556795441, "ultra-dfu-app", 40083994172, "6b8abbc6",
          branch: "gtl-ruff"),
      artifact(12556275591, "ultra-dfu-app", 40083284705, "4e1a5b26",
          branch: "v2.3.0"),
      artifact(12556171389, "ultra-dfu-app", 40082843368, "4ffb6574"),
      artifact(12556166963, "ultra-dfu-app", 40083294055, "4e1a5b26"),
      artifact(12556150414, "ultra-dfu-app", 40082361581, "d3767298"),
      artifact(12556020255, "ultra-dfu-app", 40081684055, "22f2c712",
          branch: "feat/fsk-dc-robustness", repo: 1278913770),
      artifact(12556004448, "ultra-dfu-app", 40084008126, "6b8abbc6",
          branch: "gtl-ruff"),
      artifact(12555988496, "ultra-dfu-app", 40084496773, "23507c28"),
    ];

    expect(latestSha(artifacts, ChameleonDevice.ultra), "23507c28");
  });

  test('skips expired artifacts', () {
    final artifacts = [
      artifact(2, "ultra-dfu-app", 20, "expired", expired: true),
      artifact(1, "ultra-dfu-app", 10, "available"),
    ];

    expect(latestSha(artifacts, ChameleonDevice.ultra), "available");
  });

  test('ignores other branches, tags, forks and devices', () {
    final artifacts = [
      artifact(5, "ultra-dfu-app", 50, "branch", branch: "gtl-ruff"),
      artifact(4, "ultra-dfu-app", 40, "tag", branch: "v2.3.0"),
      artifact(3, "ultra-dfu-app", 30, "fork", repo: 1278913770),
      artifact(2, "lite-dfu-app", 20, "lite"),
      artifact(1, "ultra-dfu-app", 10, "ultra"),
    ];

    expect(latestSha(artifacts, ChameleonDevice.ultra), "ultra");
    expect(latestSha(artifacts, ChameleonDevice.lite), "lite");
  });

  test('returns null when there is no main build', () {
    expect(selectLatestFirmwareArtifact([], ChameleonDevice.ultra), isNull);
    expect(
        selectLatestFirmwareArtifact([
          artifact(1, "ultra-dfu-app", 10, "branch", branch: "gtl-ruff"),
        ], ChameleonDevice.ultra),
        isNull);
  });
}
