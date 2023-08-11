import 'dart:convert';
import 'package:http/http.dart' as http;

Future<List<String>> fetchOpenCollectiveHighrollers() async {
  final Uri url = Uri.parse('https://api.opencollective.com/graphql/v2');
  const headers = {'Content-Type': 'application/json'};
  const body =
      '{"query":"query account(\$slug:String){account(slug:\$slug){name slug transactions(type:CREDIT){totalCount nodes{type fromAccount{name}amount{value}}}}}","variables":{"slug":"chameleon-ultra-gui"}}';
  try {
    final response = await http.post(url, headers: headers, body: body);
    final json = jsonDecode(response.body);
    List<String> highrollers = [];

    var nodes = json["data"]["account"]["transactions"]["nodes"]!;
    nodes.sort((a, b) {
      return b["amount"]["value"].compareTo(a["amount"]["value"]) as int;
    });

    for (var node in nodes) {
      highrollers
          .add("${node["fromAccount"]["name"]} (${node["amount"]["value"]}\$)");
    }

    return highrollers;
  } catch (e) {
    List<String> error = [e.toString()];
    return error;
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
    return 0;
  }
}
