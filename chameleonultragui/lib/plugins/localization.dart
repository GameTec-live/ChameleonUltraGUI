import 'dart:async';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations_en.dart';

// Keep diagnostics localized without threading BuildContext through model and
// conversion helpers. Zones scope translations to a call, including async work;
// scripts cannot change the locale used by another invocation.
final _localizationKey = Object();
final _english = AppLocalizationsEn();

AppLocalizations get pluginLocalizations =>
    Zone.current[_localizationKey] as AppLocalizations? ?? _english;

T withPluginLocalizations<T>(
  AppLocalizations localizations,
  T Function() action,
) => runZoned(action, zoneValues: {_localizationKey: localizations});
