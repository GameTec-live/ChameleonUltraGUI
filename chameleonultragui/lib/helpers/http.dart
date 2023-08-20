import 'dart:typed_data';
import 'package:http/http.dart';

Future<Response> httpGet(
  String url
) async {
    final uri = Uri.parse(url);
    final response = await get(uri);
    return response;
}

Future<Uint8List> httpGetBinary(
  String url
) async {
    final uri = Uri.parse(url);
    final data = await readBytes(uri);
    return data;
}
