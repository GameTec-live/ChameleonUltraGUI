// TODO: move all github stuff from flash.dart there

import 'dart:convert';
import 'package:http/http.dart' as http;

List<Map<String, String>> developers = [
  {
    'name': 'GameTec-live',
    'description': 'Lead Developer',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/66077766',
    'username': 'GameTec-live'
  },
  {
    'name': 'Augusto Zanellato',
    'description': 'Developer',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/13242738',
    'username': 'auguzanellato'
  },
  {
    'name': 'Foxushka',
    'description': 'Developer 🦊',
    'avatarUrl': 'https://avatars.githubusercontent.com/u/135865149',
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
    'description': 'Translator',
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
        if (!developers.any(
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
