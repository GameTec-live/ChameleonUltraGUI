part of 'api.dart';

extension _SettingsApi on PluginApi {
  void _registerSettings() {
    final preferences = app.sharedPreferencesProvider;
    methods.addAll({
      'settings.get': (_) => {
        'language': preferences.getLocale().toLanguageTag(),
        'theme': preferences.getTheme().name,
        'themeColor': preferences.getThemeColorIndex(),
        'sidebar': [
          'expanded',
          'auto',
          'collapsed',
        ][preferences.getSideBarExpandedIndex()],
        'autoScan': preferences.getAutoScanEnabled(),
        'autoConnect': preferences.getAutoConnectFirstFoundDevice(),
        'confirmDelete': preferences.getConfirmDelete(),
        'debugMode': preferences.isDebugMode(),
        'debugLogging': preferences.isDebugLogging(),
        'emulatedDevice': preferences.isEmulatedChameleon(),
      },
      'settings.options': (_) => {
        'language': AppLocalizations.supportedLocales
            .map((locale) => locale.toLanguageTag())
            .toList(),
        'theme': ThemeMode.values.map((theme) => theme.name).toList(),
        'themeColor': [
          'deepOrange',
          'deepPurple',
          'blue',
          'green',
          'indigo',
          'lime',
          'red',
          'yellow',
        ],
        'sidebar': ['expanded', 'auto', 'collapsed'],
      },
      'settings.update': (a) async {
        final input = (a.single as Map).cast<String, Object?>();
        final changes = <VoidCallback>[];
        // Prepare all changes first, so an invalid field cannot partly apply a patch.
        for (final entry in input.entries) {
          final value = entry.value;
          switch (entry.key) {
            case 'language':
              final locale = AppLocalizations.supportedLocales
                  .where(
                    (l) =>
                        l.toLanguageTag().toLowerCase() ==
                        (value as String).toLowerCase(),
                  )
                  .firstOrNull;
              if (locale == null) {
                throw ArgumentError(
                  pluginLocalizations.plugin_error_language(value.toString()),
                );
              }
              changes.add(() => preferences.setLocale(locale));
            case 'theme':
              final theme = ThemeMode.values.byName(value as String);
              changes.add(() => preferences.setTheme(theme));
            case 'themeColor':
              final index = value as int;
              RangeError.checkValueInInterval(index, 0, 7, 'themeColor');
              changes.add(() => preferences.setThemeColor(index));
            case 'sidebar':
              final index = [
                'expanded',
                'auto',
                'collapsed',
              ].indexOf(value as String);
              if (index < 0) {
                throw ArgumentError(pluginLocalizations.plugin_error_sidebar);
              }
              changes.add(() {
                preferences.setSideBarExpandedIndex(index);
                preferences.setSideBarAutoExpansion(index == 1);
                if (index != 1) preferences.setSideBarExpanded(index == 0);
              });
            case 'autoScan':
              final enabled = value as bool;
              changes.add(() => preferences.setAutoScanEnabled(enabled));
            case 'autoConnect':
              final enabled = value as bool;
              changes.add(
                () => preferences.setAutoConnectFirstFoundDevice(enabled),
              );
            case 'confirmDelete':
              final enabled = value as bool;
              changes.add(() => preferences.setConfirmDelete(enabled));
            case 'debugMode':
              final enabled = value as bool;
              changes.add(() => preferences.setDebugMode(enabled));
            case 'debugLogging':
              final enabled = value as bool;
              changes.add(() => preferences.setDebugLogging(enabled));
            case 'emulatedDevice':
              final enabled = value as bool;
              changes.add(() => preferences.setEmulatedChameleon(enabled));
            default:
              throw ArgumentError(
                pluginLocalizations.plugin_error_setting(entry.key),
              );
          }
        }
        final switchDevice =
            input.containsKey('emulatedDevice') &&
            input['emulatedDevice'] != preferences.isEmulatedChameleon();
        if (switchDevice) {
          await app.disconnect(manual: true);
          if (_cancelled) throw StateError(pluginLocalizations.plugin_stopped);
          app.connector = null;
        }
        for (final apply in changes) {
          apply();
        }
        if (input.containsKey('debugMode') ||
            input.containsKey('debugLogging')) {
          final logger =
              preferences.isDebugMode() && preferences.isDebugLogging()
              ? Logger(
                  output: SharedPreferencesLogger(preferences),
                  printer: PrettyPrinter(noBoxingByDefault: true),
                  filter: ChameleonLogFilter(),
                )
              : Logger();
          app.log = logger;
          app.connector?.log = logger;
          // Communicators retain their logger until the next connection.
        }
        app.changesMade();
        if (input.containsKey('sidebar')) {
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (!context.mounted) return;
            final size = app.navigationRailKey.currentContext?.size;
            if (size != null) {
              app.navigationRailSize = size;
              app.changesMade();
            }
          });
        }
        return methods['settings.get']!([]);
      },
    });
  }
}
