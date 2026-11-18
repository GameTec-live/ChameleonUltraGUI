import 'dart:convert';

import 'localization.dart';

import 'dart:io';

import 'package:uuid/uuid.dart';

/// Where a marketplace plugin was installed from. Updates match on
/// [repository] and [id]; [version] is the installed listing version.
typedef PluginSource = ({String repository, String id, String version});

/// Portable, versioned plugin envelope. Only code and resources are compressed.
class Plugin {
  static const format = 'chameleon-ultra-gui-plugin';
  static const maxDataBytes = 8 * 1024 * 1024;
  static const maxFileBytes = maxDataBytes * 2;
  final String id;
  final String name;
  final String description;
  final int color;
  final String code;
  final Map<String, String> resources;

  /// Null for plugins created or imported locally.
  final PluginSource? source;

  Plugin({
    String? id,
    required this.name,
    this.description = '',
    this.color = 0xffff5722,
    required this.code,
    Map<String, String> resources = const {},
    this.source,
  }) : id = id ?? const Uuid().v4(),
       resources = Map.unmodifiable(resources) {
    if (name.trim().isEmpty || name.length > 200) {
      throw FormatException(pluginLocalizations.plugin_error_name);
    }
    if (color < 0 || color > 0xffffffff) {
      throw FormatException(pluginLocalizations.plugin_error_color);
    }
    if (utf8.encode(jsonEncode({'code': code, 'resources': resources})).length >
        maxDataBytes) {
      throw FormatException(pluginLocalizations.plugin_error_data_size);
    }
    // Persistence uses the uncompressed envelope, even after a compressed import.
    if (utf8.encode(jsonEncode(toJson())).length > maxFileBytes) {
      throw FormatException(pluginLocalizations.plugin_error_file_size);
    }
  }

  Map<String, Object?> toJson({bool compress = false}) {
    final data = {'code': code, 'resources': resources};
    return {
      'format': format,
      'version': 1,
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'encoding': compress ? 'gzip+base64' : 'json',
      'data': compress
          ? base64Encode(gzip.encode(utf8.encode(jsonEncode(data))))
          : data,
      if (source case final source?)
        'source': {
          'repository': source.repository,
          'id': source.id,
          'version': source.version,
        },
    };
  }

  /// A fresh ID makes a new local plugin, detached from any marketplace source.
  static Future<Plugin> decode(String source, {bool freshId = false}) async {
    if (utf8.encode(source).length > maxFileBytes) {
      throw FormatException(pluginLocalizations.plugin_error_file_size);
    }
    final envelope = jsonDecode(source) as Map<String, dynamic>;
    if (envelope['format'] != format || envelope['version'] != 1) {
      throw FormatException(pluginLocalizations.plugin_error_format);
    }
    Object? data = envelope['data'];
    switch (envelope['encoding']) {
      case 'gzip+base64':
        // Stream decompression bounds the expanded payload before decoding JSON.
        final output = <int>[];
        await for (final chunk in Stream<List<int>>.value(
          base64Decode(data as String),
        ).transform(gzip.decoder)) {
          if (output.length + chunk.length > maxDataBytes) {
            throw FormatException(
              pluginLocalizations.plugin_error_expanded_size,
            );
          }
          output.addAll(chunk);
        }
        data = jsonDecode(utf8.decode(output));
      case 'json':
        break;
      default:
        throw FormatException(pluginLocalizations.plugin_error_encoding);
    }
    final payload = data as Map<String, dynamic>;
    return Plugin(
      id: freshId ? null : envelope['id'] as String,
      name: envelope['name'] as String,
      description: envelope['description'] as String,
      color: envelope['color'] as int,
      code: payload['code'] as String,
      resources: (payload['resources'] as Map<String, dynamic>)
          .cast<String, String>(),
      source: switch (envelope['source']) {
        {
          'repository': final String repository,
          'id': final String id,
          'version': final String version,
        }
            when !freshId =>
          (repository: repository, id: id, version: version),
        _ => null,
      },
    );
  }
}
