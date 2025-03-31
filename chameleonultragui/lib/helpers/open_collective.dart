import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

Future<List<String>> fetchOpenCollectiveContributors() async {
  final Uri url = Uri.parse('https://api.opencollective.com/graphql/v2');
  const headers = {'Content-Type': 'application/json'};
  const body =
      '{"query":"query account(\$slug:String){account(slug:\$slug){name slug transactions(type:CREDIT){totalCount nodes{type fromAccount{name}amount{value}}}}}","variables":{"slug":"chameleon-ultra-gui"}}';
  try {
    final response = await http.post(url, headers: headers, body: body);
    final json = jsonDecode(response.body);
    Map<String, int> contributors = {};
    List<String> contributorsList = [];

    for (var node in json["data"]["account"]["transactions"]["nodes"]) {
      contributors[node["fromAccount"]["name"]] =
          (contributors[node["fromAccount"]["name"]] ?? 0) +
              (node["amount"]["value"] as int);
    }

    List<MapEntry<String, int>> sortedEntries = contributors.entries.toList();

    sortedEntries.sort((a, b) => b.value.compareTo(a.value));

    Map.fromEntries(sortedEntries).forEach((key, value) {
      contributorsList.add("$key ($value\$)");
    });

    return contributorsList;
  } catch (e) {
    Logger log = Logger();
    log.d(e.toString());
    return [""];
  }
}

Future<double> fetchOpenCollectiveBalance() async {
  // Will be used later on when everything is async ;)
  try {
    final Uri url = Uri.parse('https://api.opencollective.com/graphql/v2');
    const headers = {'Content-Type': 'application/json'};
    const body =
        '{"query":"query account(\$slug:String){account(slug:\$slug){name slug stats{balance{value}}}}","variables":{"slug":"chameleon-ultra-gui"}}';
    final response = await http.post(url, headers: headers, body: body);
    final json = jsonDecode(response.body);
    return json["data"]["account"]["stats"]["balance"];
  } catch (e) {
    Logger log = Logger();
    log.d(e.toString());
    return 0;
  }
}
