import 'dart:convert';
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
];

Future<List<Map<String, String>>> fetchGitHubContributors() async {
  try {
    final response = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/GameTec-live/ChameleonUltraGUI/contributors")))
        .body
        .toString());

    if (response is List) {
      List<Map<String, String>> contributors = [];
      for (var contributor in response) {
        if (contributor['login'] != 'github-actions[bot]' &&
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

    for (var file in releases[0]["assets"]) {
      if (file["name"] ==
          "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app.zip") {
        content = await http.readBytes(Uri.parse(file["browser_download_url"]));
        break;
      }
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return content;
}

Future<Uint8List> fetchFirmwareFromActions(ChameleonDevice device) async {
  Uint8List content = Uint8List(0);
  String error = "";

  try {
    final artifacts = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts")))
        .body
        .toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    for (var artifact in artifacts["artifacts"]) {
      if (artifact["name"] ==
              "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app" &&
          artifact["workflow_run"]["head_branch"] == "main") {
        content = await http.readBytes(Uri.parse(
            "https://nightly.link/RfidResearchGroup/ChameleonUltra/suites/${artifact["workflow_run"]["id"]}/artifacts/${artifact["id"]}"));
        break;
      }
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
    final releases = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
        .body
        .toString());

    if (releases is! List && releases.containsKey("message")) {
      error = releases["message"];
      throw error;
    }

    for (var release in releases) {
      if (release["author"]["login"] == "github-actions[bot]") {
        return release["target_commitish"];
      }
    }
  } catch (_) {}

  try {
    final artifacts = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts")))
        .body
        .toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    for (var artifact in artifacts["artifacts"]) {
      if (artifact["name"] ==
              "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app" &&
          artifact["workflow_run"]["head_branch"] == "main") {
        return artifact["workflow_run"]["head_sha"];
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
