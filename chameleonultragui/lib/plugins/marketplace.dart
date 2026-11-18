import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../sharedprefsprovider.dart';
import 'git.dart';
import 'localization.dart';
import 'plugin.dart';

/// Plugin marketplace backed by plain Git repositories.
///
/// A repository is any Git remote reachable over HTTPS. Its root contains
/// [indexFile], which lists plugin envelopes stored in the same repository:
///
/// ```json
/// {
///   "format": "chameleon-ultra-gui-marketplace",
///   "version": 1,
///   "name": "Example plugins",
///   "plugins": [
///     {"id": "count", "path": "count.plugin.json", "version": "1.0.0", "author": "Me"}
///   ]
/// }
/// ```
abstract final class Marketplace {
  static const format = 'chameleon-ultra-gui-marketplace';
  static const indexFile = 'marketplace.json';
  static const defaultRepository =
      'https://github.com/GameTec-live/ChameleonUltraGUI-Plugins';
  static const _preference = 'plugin_repositories';

  /// Upper bound for decoded plugin code and resources per repository, since
  /// compressed envelopes expand far beyond the Git download.
  static const maxDecodedBytes = 64 * 1024 * 1024;

  /// Parsed repositories by URL; reused while the remote HEAD is unchanged.
  static final _cache = <String, MarketplaceRepository>{};

  /// Configured repository URLs. Stored as a JSON string so it syncs like
  /// any other setting.
  static List<String> get repositories =>
      switch (SharedPreferencesProvider().preferences.getString(_preference)) {
        final String json => (jsonDecode(json) as List).cast<String>(),
        null => [defaultRepository],
      };

  static set repositories(List<String> urls) {
    SharedPreferencesProvider().preferences.setString(
      _preference,
      jsonEncode(urls),
    );
    SharedPreferencesProvider().onLocalChange?.call();
  }

  /// Validates a user-entered repository URL and returns its canonical form.
  static String normalizeUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw FormatException(pluginLocalizations.marketplace_error_url);
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }

  /// Fetches HEAD of the repository at [url] and parses its listings.
  static Future<MarketplaceRepository> load(String url) async {
    final client = http.Client();
    try {
      final remote = GitRemote(url, client);
      final commit = await remote.head();
      if (_cache[url] case final cached? when cached.commit == commit) {
        return cached;
      }
      return _cache[url] = await parse(url, commit, await remote.files(commit));
    } finally {
      client.close();
    }
  }

  /// Parses a repository snapshot. A broken listing is reported in
  /// [MarketplaceRepository.problems] instead of hiding the whole repository.
  static Future<MarketplaceRepository> parse(
    String url,
    String commit,
    Map<String, Uint8List> files,
  ) async {
    final index = switch (files[indexFile]) {
      final bytes? => jsonDecode(utf8.decode(bytes)),
      null => null,
    };
    if (index case {
      'format': format,
      'version': 1,
      'plugins': final List<dynamic> entries,
    }) {
      final listings = <MarketplaceListing>[];
      final problems = <String>[];
      // Listings may share an envelope; decode and charge each file once.
      final decoded = <String, Plugin>{};
      final ids = <String>{};
      var budget = maxDecodedBytes;
      for (final entry in entries) {
        try {
          if (entry
              case {
                'id': final String id,
                'path': final String path,
                'version': final String version,
              }
              when id.isNotEmpty && version.isNotEmpty) {
            if (!ids.add(id)) {
              throw FormatException(
                pluginLocalizations.marketplace_error_duplicate,
              );
            }
            var plugin = decoded[path];
            if (plugin == null) {
              final bytes =
                  files[path] ??
                  (throw FormatException(
                    pluginLocalizations.marketplace_error_missing_file(path),
                  ));
              plugin = await Plugin.decode(utf8.decode(bytes));
              final size = plugin.resources.entries.fold(
                plugin.code.length,
                (total, resource) =>
                    total + resource.key.length + resource.value.length,
              );
              if (size > budget) {
                throw FormatException(
                  pluginLocalizations.marketplace_error_too_large,
                );
              }
              budget -= size;
              decoded[path] = plugin;
            }
            listings.add(
              MarketplaceListing(
                repository: url,
                id: id,
                version: version,
                author: entry['author'] as String? ?? '',
                plugin: plugin,
              ),
            );
          } else {
            throw FormatException(
              pluginLocalizations.marketplace_error_listing,
            );
          }
        } catch (error) {
          final name = entry is Map ? entry['id'] ?? entry['path'] : null;
          problems.add(name == null ? '$error' : '$name: $error');
        }
      }
      return MarketplaceRepository(
        url: url,
        name: switch (index['name']) {
          final String name when name.trim().isNotEmpty => name,
          _ =>
            Uri.parse(url).pathSegments.lastOrNull
                    ?.replaceFirst(RegExp(r'\.git$'), '') ??
                url,
        },
        commit: commit,
        listings: listings,
        problems: problems,
      );
    }
    throw FormatException(pluginLocalizations.marketplace_error_index);
  }
}

class MarketplaceRepository {
  final String url;
  final String name;
  final String commit;
  final List<MarketplaceListing> listings;
  final List<String> problems;

  const MarketplaceRepository({
    required this.url,
    required this.name,
    required this.commit,
    required this.listings,
    required this.problems,
  });
}

/// One plugin offered by a repository.
class MarketplaceListing {
  final String repository;
  final String id;
  final String version;
  final String author;
  final Plugin plugin;

  const MarketplaceListing({
    required this.repository,
    required this.id,
    required this.version,
    required this.author,
    required this.plugin,
  });

  bool isSourceOf(Plugin installed) =>
      installed.source?.repository == repository && installed.source?.id == id;

  /// The plugin to store on install, or when updating [installed] in place.
  /// Fresh installs get an ID derived from the listing, so devices that sync
  /// converge on one copy instead of duplicates.
  Plugin install([Plugin? installed]) => Plugin(
    id:
        installed?.id ??
        const Uuid().v5(Namespace.url.value, '$repository#$id'),
    name: plugin.name,
    description: plugin.description,
    color: plugin.color,
    code: plugin.code,
    resources: plugin.resources,
    source: (repository: repository, id: id, version: version),
  );
}
