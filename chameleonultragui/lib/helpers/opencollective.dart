import 'dart:convert';
import 'package:http/http.dart' as http;

Future<List<String>> fetchOpenCollectiveHighrollers() async {

  final Uri url = Uri.parse('https://api.opencollective.com/graphql/v2');
  const headers = {'Content-Type': 'application/json'};
  const body = '{"query":"query account(\$slug:String){account(slug:\$slug){name slug transactions(type:CREDIT){totalCount nodes{type fromAccount{name}amount{value}}}}}","variables":{"slug":"chameleon-ultra-gui"}}';
  final response = await http.post(url, headers: headers, body: body);
  final json = jsonDecode(response.body);

  List<String> highrollsers = [];
  
  for (var node in json["data"]["account"]["transactions"]["nodes"]) {
    //if (node["amount"]["value"] > 30) { Maybe another day if it overflows 
    highrollsers.add(node["fromAccount"]["name"]);
    //}
  }

  return highrollsers;
}

Future<double> fetchOpenCollectiveBalance() async {
  final Uri url = Uri.parse('https://api.opencollective.com/graphql/v2');
  const headers = {'Content-Type': 'application/json'};
  const body = '{"query":"query account(\$slug:String){account(slug:\$slug){name slug stats{balance{value}}}}","variables":{"slug":"chameleon-ultra-gui"}}';
  final response = await http.post(url, headers: headers, body: body);
  final json = jsonDecode(response.body);
  return json["data"]["account"]["stats"]["balance"];
}