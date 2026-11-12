import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The app data the engine syncs, as `collection -> id -> JSON string`.
/// Values are the exact strings the app persists, so every device hashes and
/// stores byte-identical data.
abstract interface class SyncSource {
  Map<String, Map<String, String>> read();

  /// Inserts, replaces or (with `null`) deletes one record.
  void write(String collection, String id, String? json);
}

/// Settings that follow the user across devices. Everything else (sidebar
/// state, debug flags, logs, sync secrets) stays local.
const syncedSettings = {
  'app_theme',
  'app_theme_color',
  'locale',
  'confirm_delete',
  'auto_scan_enabled',
  'auto_connect_first_found',
  'sidebar_auto_expanded',
  'sidebar_expanded_index',
};

/// Collections stored as SharedPreferences string lists of JSON objects with
/// an `id` field, mapped to their preference key.
const _listCollections = {
  'cards': 'cards',
  'card_folders': 'card_folders',
  'dictionaries': 'dictionaries',
  'dictionary_folders': 'dictionary_folders',
  'plugins': 'plugins_v1',
};

/// Vault bookkeeping records (`_devices`, `_vault`) that live only in sync state.
const internalCollections = {'_devices', '_vault'};

const _internalKey = 'sync_internal_v1';

class PreferencesSource implements SyncSource {
  final SharedPreferences _prefs;
  PreferencesSource(this._prefs);

  static String? _id(String json) =>
      (jsonDecode(json) as Map<String, dynamic>)['id'] as String?;

  Map<String, dynamic> _internal() =>
      jsonDecode(_prefs.getString(_internalKey) ?? '{}')
          as Map<String, dynamic>;

  @override
  Map<String, Map<String, String>> read() {
    final internal = _internal();
    return {
      for (final MapEntry(key: collection, value: pref)
          in _listCollections.entries)
        collection: {
          for (final json in _prefs.getStringList(pref) ?? <String>[])
            if (_id(json) case final id? when id.isNotEmpty) id: json,
        },
      'settings': {
        for (final key in syncedSettings)
          if (_prefs.get(key) case final value?) key: jsonEncode(value),
      },
      for (final collection in internalCollections)
        collection: (internal[collection] as Map<String, dynamic>? ?? {})
            .cast<String, String>(),
    };
  }

  @override
  void write(String collection, String id, String? json) {
    if (_listCollections[collection] case final pref?) {
      final items = _prefs.getStringList(pref) ?? [];
      final index = items.indexWhere((item) => _id(item) == id);
      if (json == null) {
        if (index >= 0) items.removeAt(index);
      } else if (index >= 0) {
        items[index] = json;
      } else {
        items.add(json);
      }
      _prefs.setStringList(pref, items);
    } else if (collection == 'settings' && syncedSettings.contains(id)) {
      switch (json == null ? null : jsonDecode(json)) {
        case null:
          _prefs.remove(id);
        case final bool value:
          _prefs.setBool(id, value);
        case final int value:
          _prefs.setInt(id, value);
        case final double value:
          _prefs.setDouble(id, value);
        case final String value:
          _prefs.setString(id, value);
      }
    } else if (internalCollections.contains(collection)) {
      final internal = _internal();
      final records = (internal[collection] as Map<String, dynamic>? ?? {})
        ..remove(id);
      if (json != null) records[id] = json;
      internal[collection] = records;
      _prefs.setString(_internalKey, jsonEncode(internal));
    }
  }

  /// Removes all vault bookkeeping (used when leaving a vault).
  void clearInternal() => _prefs.remove(_internalKey);
}
