import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

const defaultProxyUrl = 'https://cors.gametec-live.com/';

// By default only use proxy on assets url for CORS on web, as
// both night.link as github.com do not allow non-CORS requests
const List<String> defaultUrlsToProxy = !kIsWeb ? [] : [
  'https://nightly.link/RfidResearchGroup/ChameleonUltra/', // For nightly releases which are github action build assets
  'https://github.com/RfidResearchGroup/ChameleonUltra/', // For github releases
  // 'https://github.com/GameTec-live/ChameleonUltraGUI/',
];

abstract interface class UrlParser {
  Uri toUri(String url);
}

class HttpRequestUrlStringParser implements UrlParser {
  String? proxyUrl;
  List<String> urlsToProxy;

  HttpRequestUrlStringParser({
    this.proxyUrl = defaultProxyUrl,
    this.urlsToProxy = defaultUrlsToProxy,
  });

  /// Checks if the given url should be transformed into a proxy url or not
  @protected
  String withProxy(String url) {
    final shouldProxy = urlsToProxy.any((urlToProxy) {
      return url.startsWith(urlToProxy);
    });

    final proxyUrl = this.proxyUrl;
    if (!shouldProxy || proxyUrl == null) {
      return url;
    }

    if (proxyUrl.contains('{url}')) {
      return proxyUrl.replaceAll('{url}', url);
    }

    // Just append the url
    return '$proxyUrl$url';
  }

  @override
  Uri toUri(String url) {
    final proxiedUrl = withProxy(url);
    return Uri.parse(proxiedUrl);
  }
}

class HttpGetRequest {
  final Uri uri;
  final void Function(double progress)? onProgress;

  HttpGetRequest(this.uri, {
    this.onProgress,
  });

  factory HttpGetRequest.fromString(String url, {
    void Function(double progress)? onProgress,
    UrlParser? urlParser
  }) {
    urlParser ??= HttpRequestUrlStringParser();

    final uri = urlParser.toUri(url);
    return HttpGetRequest(uri, onProgress: onProgress);
  }

  Future<Response> get _response async {
    onProgress?.call(0);

    final request = Request('GET', uri);
    var responseStream = await request.send();

    final totalSize = responseStream.contentLength;

    if (onProgress == null || totalSize == null) {
      return Response.fromStream(responseStream);
    }

    List<int> responseBytes = List.empty(growable: true);
    var completer = Completer<Response>();

    responseStream.stream.listen(
      (chunk) {
        responseBytes.addAll(chunk);
        final receivedSize = responseBytes.length;

        onProgress!.call(receivedSize / totalSize);
      },
      onError: (err) {
        throw err;
      },
      onDone: () => completer.complete(
        Response.bytes(responseBytes, responseStream.statusCode)
      )
    );

    return completer.future;
  }

  Future<String> asString() async {
    final response = await _response;
    return response.body.toString();
  }

  Future<dynamic> asJson() async {
    final responseBody = await asString();

    try {
      return json.decode(responseBody);
    } catch (_) {
      // print('JSON Error');
      rethrow;
    }
  }

  Future<Uint8List> asBytes() async {
    final response = await _response;
    return response.bodyBytes;
  }
}
