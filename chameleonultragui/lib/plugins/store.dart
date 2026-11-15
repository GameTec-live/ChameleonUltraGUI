import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'localization.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'plugin.dart';
import '../sharedprefsprovider.dart';

/// Separate preference key: importing plugins never mutates cards or dictionaries.
class PluginStore {
  /// Bumped when sync changed stored plugins, so open views reload.
  static final remoteChanges = ValueNotifier(0);

  Future<List<Plugin>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return Future.wait(
      (preferences.getStringList('plugins_v1') ?? []).map(Plugin.decode),
    );
  }

  Future<void> save(List<Plugin> plugins) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setStringList(
      'plugins_v1',
      plugins.map((plugin) => jsonEncode(plugin.toJson())).toList(),
    )) {
      throw StateError(pluginLocalizations.plugin_error_save);
    }
    SharedPreferencesProvider().onLocalChange?.call();
  }
}
