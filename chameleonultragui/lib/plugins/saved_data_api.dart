part of 'api.dart';

extension _SavedDataApi on PluginApi {
  void _registerSavedData() {
    final preferences = app.sharedPreferencesProvider;
    final cards = _SavedCollection<CardSave>(
      load: preferences.getCards,
      store: preferences.setCards,
      decode: _savedCard,
      encode: (card) => card.toJson(),
      id: (card) => card.id,
      folder: (card) => card.folderId,
      loadFolders: preferences.getCardFolders,
      storeFolders: preferences.setCardFolders,
      decodeBundle: (source) {
        final bundle = CardFolderBundle.fromJson(source);
        return (bundle.rootFolderId, bundle.folders, bundle.cards);
      },
      encodeBundle: (root, folders, cards) => CardFolderBundle(
        rootFolderId: root,
        folders: folders,
        cards: cards,
      ).toJson(),
      changed: app.changesMade,
    );
    final dictionaries = _SavedCollection<Dictionary>(
      load: preferences.getDictionaries,
      store: preferences.setDictionaries,
      decode: _dictionary,
      encode: (dictionary) => dictionary.toJson(),
      id: (dictionary) => dictionary.id,
      folder: (dictionary) => dictionary.folderId,
      loadFolders: () => preferences
          .getDictionaryFolders()
          .map((folder) => CardFolder.fromJson(folder.toJson()))
          .toList(),
      storeFolders: (folders) => preferences.setDictionaryFolders(
        folders
            .map((folder) => DictionaryFolder.fromJson(folder.toJson()))
            .toList(),
      ),
      decodeBundle: (source) {
        final bundle = DictionaryFolderBundle.fromJson(source);
        return (
          bundle.rootFolderId,
          bundle.folders
              .map((folder) => CardFolder.fromJson(folder.toJson()))
              .toList(),
          bundle.dictionaries,
        );
      },
      encodeBundle: (root, folders, items) => DictionaryFolderBundle(
        rootFolderId: root,
        folders: folders
            .map((folder) => DictionaryFolder.fromJson(folder.toJson()))
            .toList(),
        dictionaries: items,
      ).toJson(),
      changed: app.changesMade,
    );
    methods.addAll(cards.methods('cards', 'cardFolders'));
    methods.addAll(dictionaries.methods('dictionaries', 'dictionaryFolders'));
    methods.addAll({
      'cards.decode': (a) => jsonDecode(
        _decodeCard(
          a[0] as String,
          a.length > 1 ? a[1] as String : 'json',
        ).toJson(),
      ),
      'cards.encode': (a) {
        final card = _savedCard(a[0]);
        switch (a.length > 1 ? a[1] as String : 'json') {
          case 'json':
            if (isMifareClassic(card.tag)) {
              card.data = mfClassicGetExportBlocks(
                chameleonTagTypeGetMfClassicType(card.tag),
                card.data,
                isEV1: chameleonTagSaveCheckForMifareClassicEV1(card),
              );
            }
            return card.toJson();
          case 'bin':
            return isMifareClassic(card.tag)
                ? mfClassicGetExportBytes(
                    chameleonTagTypeGetMfClassicType(card.tag),
                    card.data,
                    isEV1: chameleonTagSaveCheckForMifareClassicEV1(card),
                  ).toList()
                : card.data.expand((block) => block).toList();
          default:
            throw ArgumentError(
              pluginLocalizations.plugin_error_export_formats,
            );
        }
      },
      'dictionaries.decode': (a) => jsonDecode(
        Dictionary.fromString(
          a[0] as String,
          name: a.length > 1
              ? a[1] as String
              : pluginLocalizations.plugin_imported_dictionary_name,
        ).toJson(),
      ),
      'dictionaries.encode': (a) => _dictionary(a[0]).toString(),
    });
  }
}

CardSave _savedCard(Object? value) {
  final input = (value as Map).cast<String, Object?>();
  _savedName(input['name']);
  if (!TagType.values.any((type) => type.value == input['tag'])) {
    throw ArgumentError(pluginLocalizations.plugin_error_card_tag);
  }
  PluginApi.bytes(input['atqa'] ?? []);
  PluginApi.bytes(input['ats'] ?? []);
  for (final block in PluginApi.list(input['data'] ?? [])) {
    PluginApi.bytes(block);
  }
  final sak = input['sak'] as int? ?? 0;
  RangeError.checkValueInInterval(sak, 0, 255, 'sak');
  if (input['color'] != null) _savedColor(input['color']);
  final card = PluginApi._card({
    'sak': 0,
    'atqa': <int>[],
    'ats': <int>[],
    'data': <Object?>[],
    ...input,
    'id': input['id'] as String? ?? const Uuid().v4(),
  });
  _savedId(card.id);
  PluginApi.bytes(card.atqa);
  PluginApi.bytes(card.ats);
  return card;
}

Dictionary _dictionary(Object? value) {
  final input = (value as Map).cast<String, Object?>();
  final keys = PluginApi.list(input['keys'] ?? [])
      .map(PluginApi.bytes)
      .toList();
  final keyLength =
      input['keyLength'] as int? ?? (keys.isEmpty ? 12 : keys.first.length * 2);
  if (!(keys.isEmpty && keyLength == 0) &&
      (![8, 12, 32].contains(keyLength) ||
          keys.any((key) => key.length * 2 != keyLength))) {
    throw ArgumentError(pluginLocalizations.plugin_error_dictionary_keys);
  }
  final id = input['id'] as String? ?? const Uuid().v4();
  _savedId(id);
  return Dictionary(
    id: id,
    name: _savedName(input['name']),
    keys: keys,
    keyLength: keyLength,
    color: _savedColor(input['color']),
    folderId: input['folderId'] as String?,
  );
}

CardSave _decodeCard(String source, String format) => switch (format) {
  'json' => _savedCard(jsonDecode(source)),
  'pm3' => pm3JsonToCardSave(source),
  'flipperNfc' => flipperNfcToCardSave(source),
  'flipperRfid' => flipperRfidToCardSave(source),
  'mct' => mctToCardSave(source),
  _ => throw ArgumentError(pluginLocalizations.plugin_error_import_formats),
};

String _savedName(Object? value) {
  final name = value as String;
  if (name.trim().isEmpty) {
    throw ArgumentError(pluginLocalizations.plugin_error_saved_name);
  }
  return name;
}

void _savedId(String value) {
  if (value.isEmpty) {
    throw ArgumentError(pluginLocalizations.plugin_error_saved_id);
  }
}

Color _savedColor(Object? value) {
  if (value == null) return Colors.deepOrange;
  if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    throw ArgumentError(pluginLocalizations.plugin_error_saved_color);
  }
  return hexToColor(value);
}

/// Shares folder integrity and import rules between the two existing stores.
/// The models and their interchange codecs remain the source of truth.
class _SavedCollection<T> {
  final List<T> Function() load;
  final void Function(List<T>) store;
  final T Function(Object?) decode;
  final String Function(T) encode;
  final String Function(T) id;
  final String? Function(T) folder;
  final List<CardFolder> Function() loadFolders;
  final void Function(List<CardFolder>) storeFolders;
  final (String, List<CardFolder>, List<T>) Function(String) decodeBundle;
  final String Function(String, List<CardFolder>, List<T>) encodeBundle;
  final VoidCallback changed;

  _SavedCollection({
    required this.load,
    required this.store,
    required this.decode,
    required this.encode,
    required this.id,
    required this.folder,
    required this.loadFolders,
    required this.storeFolders,
    required this.decodeBundle,
    required this.encodeBundle,
    required this.changed,
  });

  Map<String, Object?> _json(T value) =>
      (jsonDecode(encode(value)) as Map).cast<String, Object?>();

  void _checkParent(String? parent, List<CardFolder> folders) {
    if (parent != null && !folders.any((folder) => folder.id == parent)) {
      throw ArgumentError(pluginLocalizations.plugin_error_folder(parent));
    }
  }

  void _checkFolders(List<CardFolder> folders) {
    final byId = {for (final folder in folders) folder.id: folder};
    if (byId.length != folders.length) {
      throw ArgumentError(pluginLocalizations.plugin_error_folder_ids);
    }
    for (final folder in folders) {
      _savedId(folder.id);
      _savedName(folder.name);
      final seen = {folder.id};
      var parent = folder.parentId;
      while (parent != null) {
        if (!seen.add(parent)) {
          throw ArgumentError(pluginLocalizations.plugin_error_folder_cycle);
        }
        final ancestor = byId[parent];
        if (ancestor == null) {
          throw ArgumentError(
            pluginLocalizations.plugin_error_parent_folder(parent),
          );
        }
        parent = ancestor.parentId;
      }
    }
  }

  Set<String> _tree(String root, List<CardFolder> folders) {
    if (!folders.any((folder) => folder.id == root)) {
      throw ArgumentError(pluginLocalizations.plugin_error_folder(root));
    }
    final ids = {root};
    var added = true;
    while (added) {
      added = false;
      for (final folder in folders) {
        if (ids.contains(folder.parentId) && ids.add(folder.id)) added = true;
      }
    }
    return ids;
  }

  String _save(Object? input) {
    final item = decode(input);
    _checkParent(folder(item), loadFolders());
    final items = load()..removeWhere((existing) => id(existing) == id(item));
    items.add(item);
    store(items);
    changed();
    return id(item);
  }

  Map<String, ApiMethod> methods(String prefix, String foldersPrefix) => {
    '$prefix.list': (_) => load().map(_json).toList(),
    '$prefix.get': (a) {
      final item = load()
          .where((item) => id(item) == a.single as String)
          .firstOrNull;
      return item == null ? null : _json(item);
    },
    '$prefix.save': (a) => _save(a.single),
    '$prefix.delete': (a) {
      final items = load();
      final before = items.length;
      items.removeWhere((item) => id(item) == a.single as String);
      if (items.length == before) return false;
      store(items);
      changed();
      return true;
    },
    '$prefix.move': (a) {
      final item = load()
          .where((item) => id(item) == a[0] as String)
          .firstOrNull;
      if (item == null) return false;
      _save({
        ..._json(item),
        'folderId': a.length > 1 ? a[1] as String? : null,
      });
      return true;
    },
    '$foldersPrefix.list': (_) =>
        loadFolders().map((folder) => jsonDecode(folder.toJson())).toList(),
    '$foldersPrefix.save': (a) {
      final input = (a.single as Map).cast<String, Object?>();
      final folder = CardFolder(
        id: input['id'] as String?,
        name: _savedName(input['name']),
        color: _savedColor(input['color']),
        parentId: input['parentId'] as String?,
      );
      _savedId(folder.id);
      final folders = loadFolders()
        ..removeWhere((existing) => existing.id == folder.id);
      folders.add(folder);
      _checkFolders(folders);
      storeFolders(folders);
      changed();
      return folder.id;
    },
    '$foldersPrefix.delete': (a) {
      final folders = loadFolders();
      final ids = _tree(a.single as String, folders);
      storeFolders(
        folders.where((folder) => !ids.contains(folder.id)).toList(),
      );
      store(load().where((item) => !ids.contains(folder(item))).toList());
      changed();
      return true;
    },
    '$foldersPrefix.export': (a) {
      final folders = loadFolders();
      final root = a.single as String;
      final ids = _tree(root, folders);
      return encodeBundle(
        root,
        folders.where((folder) => ids.contains(folder.id)).toList(),
        load().where((item) => ids.contains(folder(item))).toList(),
      );
    },
    '$foldersPrefix.import': (a) {
      final (root, folders, items) = decodeBundle(a[0] as String);
      final existing = loadFolders();
      final destination = a.length > 1 ? a[1] as String? : null;
      _checkParent(destination, existing);
      // The exported root may reference its original parent outside the bundle.
      for (final folder in folders) {
        if (folder.id == root) folder.parentId = null;
      }
      _checkFolders(folders);
      final ids = _tree(root, folders);
      if (ids.length != folders.length) {
        throw ArgumentError(pluginLocalizations.plugin_error_bundle_folders);
      }
      final remap = {
        for (final folder in folders) folder.id: const Uuid().v4(),
      };
      final imported = folders
          .map(
            (folder) => CardFolder(
              id: remap[folder.id],
              name: _savedName(folder.name),
              color: folder.color,
              parentId: folder.id == root
                  ? destination
                  : remap[folder.parentId],
            ),
          )
          .toList();
      final copies = items.map((item) {
        if (!ids.contains(folder(item))) {
          throw ArgumentError(pluginLocalizations.plugin_error_bundle_item);
        }
        return decode({
          ..._json(item),
          'id': const Uuid().v4(),
          'folderId': remap[folder(item)],
        });
      }).toList();
      _checkFolders([...existing, ...imported]);
      storeFolders([...existing, ...imported]);
      store([...load(), ...copies]);
      changed();
      return remap[root];
    },
  };
}
