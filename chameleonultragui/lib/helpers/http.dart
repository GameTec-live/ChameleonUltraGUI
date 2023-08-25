import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

const proxyUrl = 'https://cors.gametec-live.com/';
const urlsToProxy = [
  'https://nightly.link/RfidResearchGroup/ChameleonUltra/', // For nightly releases / github action build assets
  'https://github.com/RfidResearchGroup/ChameleonUltra/', // For github releases
  // 'https://github.com/GameTec-live/ChameleonUltraGUI/',
];

String getUrl(String url) {
  if (kIsWeb) {
    final shouldProxy = urlsToProxy.any((urlToProxy) {
      return url.startsWith(urlToProxy);
    });

    if (shouldProxy) {
      return '$proxyUrl$url';
    }
  }

  return url;
}

Future<Response> httpGet(
  String url
) async {
    final uri = Uri.parse(getUrl(url));
    final response = await get(uri);
    return response;
}

Future<Uint8List> httpGetBinary(
  String url
) async {
    final uri = Uri.parse(getUrl(url));
    final data = await readBytes(uri);
    return data;
}
