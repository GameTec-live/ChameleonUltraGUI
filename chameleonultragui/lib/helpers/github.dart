import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:http/http.dart' as http;

List<Map<String, String>> developers = [
  {
    'name': 'GameTec-live',
    'description': 'Lead Developer',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/66077766',
    'username': 'GameTec-live'
  },
  {
    'name': 'Foxushka',
    'description': 'Lead Developer 🦊',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/135865149',
    'username': 'Foxushka'
  },
  {
    'name': 'Augusto Zanellato',
    'description': 'Developer',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/13242738',
    'username': 'augustozanellato'
  },
  {
    'name': 'Thomas Cannon',
    'description': 'Apple maintainer',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/1297160',
    'username': 'thomascannon'
  },
  {
    'name': 'Akisame',
    'description': 'Schrödingers Developer',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/61940251',
    'username': 'Akisame-AI'
  },
  {
    'name': 'Andrés Ruz Nieto',
    'description': 'Translation maintainer',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/40019177',
    'username': 'aruznieto'
  },
  {
    'name': 'St.Ricky',
    'description': 'Icon designer',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/192366376',
    'username': 'Saint-Ricky'
  }
];

List<String> excludedAccounts = ["github-actions[bot]", "ChameleonHelper"];

Future<List<Map<String, String>>> fetchGitHubContributors() async {
  try {
    final response = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/GameTec-live/ChameleonUltraGUI/contributors")))
        .body
        .toString());

    if (response is List) {
      List<Map<String, String>> contributors = [];
      for (var contributor in response) {
        if (!excludedAccounts.contains(contributor['login']) &&
            !developers.any(
                (developer) => developer['username'] == contributor['login'])) {
          contributors.add({
            'name': contributor['login'],
            'description': '',
            'avatarUrl': contributor['avatar_url'],
            'username': contributor['login']
          });
        }
      }

      return contributors;
    }

    return [];
  } catch (_) {
    return [];
  }
}

Future<Uint8List> fetchFirmwareFromReleases(ChameleonDevice device) async {
  Uint8List content = Uint8List(0);
  String error = "";

  try {
    final releases = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
        .body
        .toString());

    if (releases is! List && releases.containsKey("message")) {
      error = releases["message"];
      throw error;
    }

    for (var release in releases) {
      if (release["prerelease"]) {
        for (var file in release["assets"]) {
          if (file["name"] == "${_dfuAppName(device)}.zip") {
            content =
                await http.readBytes(Uri.parse(file["browser_download_url"]));
            break;
          }
        }
      }

      if (content.isNotEmpty) {
        break;
      }
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return content;
}

String _dfuAppName(ChameleonDevice device) =>
    "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app";

bool _isMainFirmwareArtifact(dynamic artifact, ChameleonDevice device) {
  final run = artifact["workflow_run"];
  return artifact["name"] == _dfuAppName(device) &&
      artifact["expired"] != true &&
      run != null &&
      run["head_branch"] == "main" &&
      run["head_repository_id"] == 581338100;
}

Uri _artifactDownloadUrl(dynamic artifact) => Uri.parse(
    "https://nightly.link/RfidResearchGroup/ChameleonUltra/suites/${artifact["workflow_run"]["id"]}/artifacts/${artifact["id"]}");

/// Returns the newest non-expired DFU artifact built from upstream main.
///
/// The artifacts API lists by artifact ID, which does not follow build order,
/// so the first match can be an older build. Workflow run IDs do follow it,
/// and unlike created_at they do not change when an old run is re-run.
Map<String, dynamic>? selectLatestFirmwareArtifact(
    List<dynamic> artifacts, ChameleonDevice device) {
  Map<String, dynamic>? latest;

  for (var artifact in artifacts) {
    if (!_isMainFirmwareArtifact(artifact, device)) {
      continue;
    }

    if (latest == null ||
        artifact["workflow_run"]["id"] > latest["workflow_run"]["id"]) {
      latest = artifact;
    }
  }

  return latest;
}

enum FirmwareChannel { release, prerelease, dev }

class FirmwareBuild {
  final String name;
  final FirmwareChannel channel;
  final DateTime date;
  final Uri url;
  final String? commit;

  FirmwareBuild({
    required this.name,
    required this.channel,
    required this.date,
    required this.url,
    this.commit,
  });

  /// Whether [gitVersion] (as reported by the device, e.g. `v2.3.0` or
  /// `v2.3.0-2-g23507c2`) is this build.
  bool isInstalled(String gitVersion) {
    if (gitVersion == name) {
      return true;
    }

    final installedCommit =
        RegExp(r'-g([0-9a-f]{7,})').firstMatch(gitVersion)?.group(1);
    return installedCommit != null &&
        commit != null &&
        commit!.startsWith(installedCommit);
  }
}

List<FirmwareBuild> firmwareBuildsFromReleases(
    List<dynamic> releases, ChameleonDevice device) {
  final builds = <FirmwareBuild>[];

  for (var release in releases) {
    final asset = (release["assets"] as List)
        .where((file) => file["name"] == "${_dfuAppName(device)}.zip")
        .firstOrNull;
    if (asset == null) {
      continue;
    }

    // target_commitish is a branch name on some releases
    final String commitish = release["target_commitish"] ?? "";
    builds.add(FirmwareBuild(
      name: release["tag_name"],
      channel: release["prerelease"] == true
          ? FirmwareChannel.prerelease
          : FirmwareChannel.release,
      // The rolling dev pre-release keeps its original publish date, so use
      // the upload date of the firmware itself
      date: DateTime.parse(asset["updated_at"]),
      url: Uri.parse(asset["browser_download_url"]),
      commit:
          RegExp(r'^[0-9a-f]{40}$').hasMatch(commitish) ? commitish : null,
    ));
  }

  return builds;
}

List<FirmwareBuild> firmwareBuildsFromArtifacts(
    List<dynamic> artifacts, ChameleonDevice device) {
  final matching = artifacts
      .where((artifact) => _isMainFirmwareArtifact(artifact, device))
      .toList()
    ..sort((a, b) => (b["workflow_run"]["id"] as int)
        .compareTo(a["workflow_run"]["id"] as int));

  // Re-runs produce several artifacts for the same commit, keep the newest
  final commits = <String>{};
  return [
    for (var artifact in matching)
      if (commits.add(artifact["workflow_run"]["head_sha"]))
        FirmwareBuild(
          name: artifact["workflow_run"]["head_sha"].substring(0, 7),
          channel: FirmwareChannel.dev,
          date: DateTime.parse(artifact["created_at"]),
          url: _artifactDownloadUrl(artifact),
          commit: artifact["workflow_run"]["head_sha"],
        ),
  ];
}

/// Lists the releases, pre-releases and recent main builds that can be
/// flashed to [device], newest first within each channel.
Future<List<FirmwareBuild>> fetchFirmwareBuilds(ChameleonDevice device) async {
  final releases = json.decode((await http.get(Uri.parse(
          "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
      .body
      .toString());

  if (releases is! List) {
    throw releases["message"] ?? "Unexpected response from GitHub";
  }

  final artifacts = json.decode((await http.get(Uri.parse(
          "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts?per_page=100&name=${_dfuAppName(device)}")))
      .body
      .toString());

  if (artifacts.containsKey("message")) {
    throw artifacts["message"];
  }

  return [
    ...firmwareBuildsFromReleases(releases, device),
    ...firmwareBuildsFromArtifacts(artifacts["artifacts"], device),
  ];
}

Future<Uint8List> downloadFirmwareBuild(FirmwareBuild build) =>
    http.readBytes(build.url);

Future<Uint8List> fetchFirmwareFromActions(ChameleonDevice device) async {
  Uint8List content = Uint8List(0);
  String error = "";

  try {
    final artifacts = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts?per_page=100&name=${_dfuAppName(device)}")))
        .body
        .toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    final artifact =
        selectLatestFirmwareArtifact(artifacts["artifacts"], device);
    if (artifact != null) {
      content = await http.readBytes(_artifactDownloadUrl(artifact));
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return content;
}

Future<String> latestAvailableCommit(ChameleonDevice device) async {
  String error = "";

  try {
    final artifacts = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts?per_page=100&name=${_dfuAppName(device)}")))
        .body
        .toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    final artifact =
        selectLatestFirmwareArtifact(artifacts["artifacts"], device);
    if (artifact != null) {
      return artifact["workflow_run"]["head_sha"];
    }
  } catch (_) {}

  try {
    final releases = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
        .body
        .toString());

    if (releases is! List && releases.containsKey("message")) {
      error = releases["message"];
      throw error;
    }

    for (var release in releases) {
      if (release["author"]["login"] == "github-actions[bot]" &&
          release["prerelease"]) {
        return release["target_commitish"];
      }
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return "";
}

Future<String> resolveCommit(String commitHash) async {
  if ('-'.allMatches(commitHash).length == 2) {
    return commitHash.split("-")[2].replaceAll('g', ''); // v2.0.0-1-gXXXXXX
  } else if (commitHash.startsWith('-dirty')) {
    return commitHash; // v2.0.0-1-gXXXXXX-dirty
  } else if ('-'.allMatches(commitHash).isEmpty) {
    final tags = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/tags")))
        .body
        .toString());
    for (var tag in tags) {
      if (commitHash == tag['name']) {
        return tag['commit']['sha'];
      }
    }
  }

  return commitHash;
}

class ChangelogEntry {
  final String version;
  final String? tagName;
  final DateTime publishedAt;
  final String url;
  final List<String> changes;
  final bool isPrerelease;
  final String? currentVersionCommit;
  final Map<String, String>? commitHashes; // Maps change message to commit hash

  ChangelogEntry({
    required this.version,
    this.tagName,
    required this.publishedAt,
    required this.url,
    required this.changes,
    required this.isPrerelease,
    this.currentVersionCommit,
    this.commitHashes,
  });

  factory ChangelogEntry.fromGitHubRelease(Map<String, dynamic> release) {
    // Parse the body to extract changelog items
    String body = release['body'] ?? '';
    List<String> changes = _parseChangelogFromBody(body);

    return ChangelogEntry(
      version: release['name'] ?? release['tag_name'] ?? 'Unknown',
      tagName: release['tag_name'],
      publishedAt: DateTime.parse(release['published_at']),
      url: release['html_url'],
      changes: changes,
      isPrerelease: release['prerelease'] ?? false,
    );
  }

  static List<String> _parseChangelogFromBody(String body) {
    // Find the "## What's Changed" section
    final RegExp whatsChangedRegex = RegExp(
      r"## What's Changed\r?\n(.*?)(?:\r?\n\r?\n|$)",
      dotAll: true,
      caseSensitive: false,
    );

    final Match? match = whatsChangedRegex.firstMatch(body);
    if (match == null) {
      return [];
    }

    String changesSection = match.group(1) ?? '';

    // Split by lines and filter for actual changelog items (usually start with * or -)
    return changesSection
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.trim())
        .where((line) =>
            line.startsWith('*') ||
            line.startsWith('-') ||
            line.startsWith('+'))
        .map((line) => line.replaceFirst(RegExp(r'^[*\-+]\s*'), ''))
        .toList();
  }
}

Future<List<dynamic>?> _fetchReleases() async {
  try {
    final response = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/GameTec-live/ChameleonUltraGUI/releases")))
        .body
        .toString());

    if (response is List) {
      return response;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<List<ChangelogEntry>> fetchChangelogs([String? buildNumber]) async {
  try {
    final List<ChangelogEntry> changelogs = [];

    // Fetch releases once and reuse for both functions
    final releases = await _fetchReleases();
    if (releases == null) {
      return [];
    }

    // Find current version commit if build number is provided
    String? currentVersionCommit;
    if (buildNumber != null) {
      currentVersionCommit = await findCurrentVersionCommit(buildNumber);
    }

    // First, get unreleased changes
    final unreleasedEntry =
        await fetchUnreleasedChanges(releases, currentVersionCommit);
    if (unreleasedEntry != null) {
      changelogs.add(unreleasedEntry);
    }

    // Then get published releases
    final publishedReleases = releases
        .where((release) => release['prerelease'] != true)
        .map((release) => ChangelogEntry.fromGitHubRelease(release))
        .toList();
    changelogs.addAll(publishedReleases);

    return changelogs;
  } catch (_) {
    return [];
  }
}

Future<ChangelogEntry?> fetchUnreleasedChanges(
    [List<dynamic>? releases, String? currentVersionCommit]) async {
  try {
    // Use provided releases or fetch them if not provided
    final releasesResponse = releases ?? await _fetchReleases();

    if (releasesResponse == null || releasesResponse.isEmpty) {
      return null;
    }

    // Find the latest non-prerelease
    final latestRelease = releasesResponse.firstWhere(
      (release) => release['prerelease'] != true,
      orElse: () => null,
    );

    if (latestRelease == null) {
      return null;
    }

    final String latestReleaseCommit = latestRelease['target_commitish'];

    // Get commits between the latest release and main branch
    final commitsResponse = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/GameTec-live/ChameleonUltraGUI/compare/$latestReleaseCommit...main")))
        .body
        .toString());

    if (commitsResponse['commits'] == null ||
        (commitsResponse['commits'] as List).isEmpty) {
      return null;
    }

    final List<dynamic> commits = commitsResponse['commits'];
    final List<String> changes = [];
    final Map<String, String> commitHashes = {};

    // Build changes list and commit hash mapping (reverse to show newest first)
    for (var commit in commits.reversed) {
      String message = commit['commit']['message']
          .toString()
          .split('\n')[0] // First line only
          .trim();

      if (message.isNotEmpty) {
        changes.add(message);
        commitHashes[message] = commit['sha'];
      }
    }

    if (changes.isEmpty) {
      return null;
    }

    // Check if current version commit is among the unreleased commits
    String? matchedCurrentVersionCommit;
    if (currentVersionCommit != null) {
      bool hasMatch =
          commits.any((commit) => commit['sha'] == currentVersionCommit);
      if (hasMatch) {
        matchedCurrentVersionCommit = currentVersionCommit;
      }
    }

    return ChangelogEntry(
      version: "Unreleased",
      tagName: null,
      publishedAt: DateTime.now(),
      url:
          "https://github.com/GameTec-live/ChameleonUltraGUI/compare/$latestReleaseCommit...main",
      changes: changes,
      isPrerelease: false,
      currentVersionCommit: matchedCurrentVersionCommit,
      commitHashes: commitHashes,
    );
  } catch (_) {
    return null;
  }
}

Future<String?> findCurrentVersionCommit(String buildNumber) async {
  String workflowName =
      (Platform.isAndroid || Platform.isMacOS || Platform.isIOS)
          ? 'publish-app.yml'
          : 'build-app.yml';

  try {
    // Fetch workflow runs
    final response = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/GameTec-live/ChameleonUltraGUI/actions/workflows/$workflowName/runs?status=success&per_page=100")))
        .body
        .toString());

    if (response['workflow_runs'] == null) {
      return null;
    }

    final List<dynamic> workflowRuns = response['workflow_runs'];

    // Look for a workflow run with matching run number (build ID)
    for (var run in workflowRuns) {
      if (run['run_number'].toString() == buildNumber) {
        return run['head_sha']; // Return the commit hash
      }
    }

    return null;
  } catch (_) {
    return null;
  }
}
