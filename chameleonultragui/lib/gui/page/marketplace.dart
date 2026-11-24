import 'package:flutter/material.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/plugins/localization.dart';
import 'package:chameleonultragui/plugins/marketplace.dart';
import 'package:chameleonultragui/plugins/plugin.dart';
import 'package:chameleonultragui/plugins/store.dart';

/// Browse, search, install and update plugins from Git repositories.
class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});
  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  AppLocalizations get _localizations =>
      AppLocalizations.of(context) ?? pluginLocalizations;
  final _store = PluginStore();
  final _search = TextEditingController();
  var _repositories = <String, AsyncSnapshot<MarketplaceRepository>>{};

  /// Null until loaded, and while unreadable so installs cannot overwrite it.
  List<Plugin>? _installed;
  bool _busy = false;

  /// Bumped per refresh so results of a superseded refresh are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _message(Object message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.toString())));

  Future<void> _refresh() async {
    final generation = ++_generation;
    final localizations = _localizations;
    final urls = Marketplace.repositories;
    setState(
      () => _repositories = {
        for (final url in urls)
          url: const AsyncSnapshot<MarketplaceRepository>.waiting(),
      },
    );
    try {
      final installed = await withPluginLocalizations(
        localizations,
        _store.load,
      );
      if (mounted && generation == _generation) {
        setState(() => _installed = installed);
      }
    } catch (error) {
      if (mounted && generation == _generation) _message(error);
    }
    final problems = <String>[];
    await Future.wait(
      urls.map((url) async {
        AsyncSnapshot<MarketplaceRepository> result;
        try {
          final repository = await withPluginLocalizations(
            localizations,
            () => Marketplace.load(url),
          );
          problems.addAll(
            repository.problems.map(
              (problem) => '${repository.name}: $problem',
            ),
          );
          result = AsyncSnapshot.withData(ConnectionState.done, repository);
        } catch (error) {
          problems.add(localizations.marketplace_load_failed(error, url));
          result = AsyncSnapshot.withError(ConnectionState.done, error);
        }
        if (mounted && generation == _generation) {
          setState(() => _repositories[url] = result);
        }
      }),
    );
    if (mounted && generation == _generation && problems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(problems.join('\n')),
          showCloseIcon: true,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Plugin? _installedFrom(MarketplaceListing listing) =>
      _installed?.where(listing.isSourceOf).firstOrNull;

  bool _hasUpdate(MarketplaceListing listing) {
    final version = _installedFrom(listing)?.source?.version;
    return version != null && version != listing.version;
  }

  Future<bool> _confirm(String title, List<String> paragraphs) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          scrollable: true,
          content: Text(
            paragraphs.where((text) => text.isNotEmpty).join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_localizations.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_localizations.continue_action),
            ),
          ],
        ),
      ) ==
      true;

  /// Installs [listings], updating the ones already installed in place.
  Future<void> _install(List<MarketplaceListing> listings) async {
    final localizations = _localizations;
    final fresh =
        listings.length == 1 && _installedFrom(listings.single) == null;
    setState(() => _busy = true);
    try {
      // Reload so changes made elsewhere since opening are not overwritten.
      final plugins = await withPluginLocalizations(localizations, _store.load);
      for (final listing in listings) {
        final index = plugins.indexWhere(listing.isSourceOf);
        if (index < 0) {
          plugins.add(listing.install());
        } else {
          plugins[index] = listing.install(plugins[index]);
        }
      }
      await withPluginLocalizations(localizations, () => _store.save(plugins));
      if (!mounted) return;
      setState(() => _installed = plugins);
      _message(
        fresh
            ? localizations.marketplace_installed_message(
                listings.single.plugin.name,
              )
            : localizations.marketplace_updated_message(listings.length),
      );
    } catch (error) {
      if (mounted) _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installOne(
    MarketplaceListing listing,
    MarketplaceRepository repository,
  ) async {
    final update = _installedFrom(listing) != null;
    if (await _confirm(
      update
          ? _localizations.marketplace_update_title(
              listing.plugin.name,
              listing.version,
            )
          : _localizations.marketplace_install_title(listing.plugin.name),
      [
        listing.plugin.description,
        _localizations.marketplace_source(repository.name, listing.version),
        if (update) _localizations.marketplace_update_message,
        _localizations.plugin_import_warning,
      ],
    )) {
      await _install([listing]);
    }
  }

  Future<void> _updateAll(List<MarketplaceListing> updates) async {
    if (await _confirm(_localizations.marketplace_update_all(updates.length), [
      updates
          .map((listing) => '${listing.plugin.name} ${listing.version}')
          .join('\n'),
      _localizations.marketplace_update_message,
      _localizations.plugin_import_warning,
    ])) {
      await _install(updates);
    }
  }

  Future<void> _openSettings() async {
    final before = Marketplace.repositories;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _RepositoriesPage(
          names: {
            for (final MapEntry(:key, :value) in _repositories.entries)
              if (value.data case final repository?) key: repository.name,
          },
        ),
      ),
    );
    if (mounted && Marketplace.repositories.join('\n') != before.join('\n')) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final loaded = [
      for (final snapshot in _repositories.values) ?snapshot.data,
    ];
    final matches = [
      for (final repository in loaded)
        for (final listing in repository.listings)
          if ([
            listing.plugin.name,
            listing.plugin.description,
            listing.author,
            listing.id,
            repository.name,
          ].any((text) => text.toLowerCase().contains(query)))
            (repository, listing),
    ]..sort((a, b) => a.$2.plugin.name.compareTo(b.$2.plugin.name));
    final updates = [
      for (final repository in loaded) ...repository.listings.where(_hasUpdate),
    ];
    final loading = _repositories.values.any(
      (snapshot) => snapshot.connectionState == ConnectionState.waiting,
    );
    final canInstall = _installed != null && !_busy;

    return Scaffold(
      appBar: AppBar(
        title: Text(_localizations.marketplace),
        actionsPadding: const EdgeInsets.only(right: 12),
        actions: [
          if (updates.isNotEmpty)
            IconButton(
              tooltip: _localizations.marketplace_update_all(updates.length),
              // Wait for every repository, so no update is silently skipped.
              onPressed: canInstall && !loading
                  ? () => _updateAll(updates)
                  : null,
              icon: Badge.count(
                count: updates.length,
                child: const Icon(Icons.system_update_alt),
              ),
            ),
          IconButton(
            tooltip: _localizations.marketplace_refresh,
            onPressed: loading || _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: _localizations.marketplace_repositories,
            onPressed: _busy ? null : _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: _localizations.marketplace_search,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: _localizations.clear_search,
                        onPressed: _search.clear,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (loading || _busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_repositories.isEmpty)
                  _Empty(_localizations.marketplace_no_repositories)
                else if (matches.isEmpty && !loading)
                  _Empty(_localizations.marketplace_empty),
                for (final (repository, listing) in matches)
                  _ListingCard(
                    listing: listing,
                    repository: repository,
                    installed: _installedFrom(listing),
                    onInstall: canInstall
                        ? () => _installOne(listing, repository)
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final MarketplaceListing listing;
  final MarketplaceRepository repository;
  final Plugin? installed;
  final VoidCallback? onInstall;

  const _ListingCard({
    required this.listing,
    required this.repository,
    required this.installed,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context) ?? pluginLocalizations;
    final plugin = listing.plugin;
    final upToDate = installed?.source?.version == listing.version;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        leading: Icon(Icons.extension, color: Color(plugin.color), size: 32),
        title: Text(plugin.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plugin.description.isNotEmpty)
              Text(
                plugin.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Tag(Icons.sell_outlined, listing.version),
                if (listing.author.isNotEmpty)
                  _Tag(Icons.person_outline, listing.author),
                _Tag(Icons.inventory_2_outlined, repository.name),
              ],
            ),
          ],
        ),
        trailing: upToDate
            ? Chip(
                avatar: const Icon(Icons.check, size: 18),
                label: Text(localizations.marketplace_installed),
              )
            : installed != null
            ? FilledButton(
                onPressed: onInstall,
                child: Text(localizations.update),
              )
            : FilledButton.tonal(
                onPressed: onInstall,
                child: Text(localizations.marketplace_install),
              ),
      ),
    );
  }
}

/// Small read-only chip for listing metadata.
class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Tag(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(label),
    labelStyle: Theme.of(context).textTheme.labelSmall,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty(this.message);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(child: Text(message, textAlign: TextAlign.center)),
  );
}

/// Marketplace settings: the list of repositories. Changes save immediately.
class _RepositoriesPage extends StatefulWidget {
  /// Display names of repositories that loaded, by URL.
  final Map<String, String> names;
  const _RepositoriesPage({required this.names});
  @override
  State<_RepositoriesPage> createState() => _RepositoriesPageState();
}

class _RepositoriesPageState extends State<_RepositoriesPage> {
  AppLocalizations get _localizations =>
      AppLocalizations.of(context) ?? pluginLocalizations;
  var _urls = Marketplace.repositories;

  void _save(List<String> urls) {
    Marketplace.repositories = urls;
    setState(() => _urls = urls);
  }

  Future<void> _add() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => _AddRepositoryDialog(existing: _urls),
    );
    if (url != null) _save([..._urls, url]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_localizations.marketplace_repositories),
      actionsPadding: const EdgeInsets.only(right: 12),
      actions: [
        IconButton(
          tooltip: _localizations.marketplace_add_repository,
          onPressed: _add,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final url in _urls)
          Card(
            child: ListTile(
              title: Text(widget.names[url] ?? url),
              // Unloaded repositories already show their URL as the title.
              subtitle: switch ([
                if (widget.names.containsKey(url)) url,
                if (url == Marketplace.defaultRepository)
                  _localizations.marketplace_default_repository,
              ]) {
                [] => null,
                final lines => Text(lines.join('\n')),
              },
              trailing: IconButton(
                tooltip: _localizations.marketplace_remove_repository,
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _save(_urls.where((other) => other != url).toList()),
              ),
            ),
          ),
        if (!_urls.contains(Marketplace.defaultRepository))
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(_localizations.marketplace_restore_default),
            onTap: () => _save([Marketplace.defaultRepository, ..._urls]),
          ),
      ],
    ),
  );
}

class _AddRepositoryDialog extends StatefulWidget {
  final List<String> existing;
  const _AddRepositoryDialog({required this.existing});
  @override
  State<_AddRepositoryDialog> createState() => _AddRepositoryDialogState();
}

class _AddRepositoryDialogState extends State<_AddRepositoryDialog> {
  AppLocalizations get _localizations =>
      AppLocalizations.of(context) ?? pluginLocalizations;
  final _url = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final url = withPluginLocalizations(
        _localizations,
        () => Marketplace.normalizeUrl(_url.text),
      );
      if (widget.existing.contains(url)) {
        throw FormatException(_localizations.marketplace_repository_exists);
      }
      Navigator.pop(context, url);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_localizations.marketplace_add_repository),
    content: TextField(
      controller: _url,
      autofocus: true,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: _localizations.marketplace_repository_url,
        errorText: _error,
        errorMaxLines: 3,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_localizations.cancel),
      ),
      FilledButton(onPressed: _submit, child: Text(_localizations.ok)),
    ],
  );
}
