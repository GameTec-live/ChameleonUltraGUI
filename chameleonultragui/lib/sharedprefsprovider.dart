import 'dart:typed_data';
import 'dart:convert';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/colors.dart' as colors;
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class Dictionary {
  String id;
  String name;
  List<Uint8List> keys;
  Color color;

  factory Dictionary.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final name = data['name'] as String;
    final encodedKeys = data['keys'] as List<dynamic>;
    if (data['color'] == null) {
      data['color'] = colorToHex(Colors.deepOrange);
    }
    final color = hexToColor(data['color']);
    List<Uint8List> keys = [];
    for (var key in encodedKeys) {
      keys.add(Uint8List.fromList(List<int>.from(key)));
    }
    return Dictionary(id: id, name: name, keys: keys, color: color);
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'name': name,
      'color': colorToHex(color),
      'keys': keys.map((key) => key.toList()).toList()
    });
  }

  factory Dictionary.fromFile(String file, String name) {
    final lines = file.split("\n");
    List<Uint8List> keys = [];
    for (var key in lines) {
      keys.add(hexToBytes(key));
    }
    return Dictionary(name: name, keys: keys);
  }

  Uint8List toFile() {
    String output = "";
    for (var key in keys) {
      output += "${bytesToHex(key).toUpperCase()}\n";
    }
    return const Utf8Encoder().convert(output);
  }

  Dictionary(
      {String? id,
      this.name = "",
      this.keys = const [],
      this.color = Colors.deepOrange})
      : id = id ?? const Uuid().v4();
}

class CardSave {
  String id;
  String uid;
  int sak;
  Uint8List atqa;
  Uint8List ats;
  String name;
  TagType tag;
  List<Uint8List> data;
  CardSaveExtra extraData;
  Color color;

  factory CardSave.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final uid = data['uid'] as String;
    final sak = data['sak'] as int;
    final atqa = List<int>.from(data['atqa'] as List<dynamic>);
    final ats = List<int>.from((data['ats'] ?? []) as List<dynamic>);
    final name = data['name'] as String;
    final tag = getTagTypeByValue(data['tag']);
    final extraData = CardSaveExtra.import(data['extra'] ?? {});
    final color =
        data['color'] == null ? Colors.deepOrange : hexToColor(data['color']);
    List<Uint8List> tagData = (data['data'] as List<dynamic>)
        .map((e) => Uint8List.fromList(List<int>.from(e)))
        .toList();

    return CardSave(
        id: id,
        uid: uid,
        sak: sak,
        name: name,
        tag: tag,
        data: tagData,
        color: color,
        extraData: extraData,
        ats: Uint8List.fromList(ats),
        atqa: Uint8List.fromList(atqa));
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'uid': uid,
      'sak': sak,
      'atqa': atqa.toList(),
      'ats': ats.toList(),
      'name': name,
      'tag': tag.value,
      'color': colorToHex(color),
      'data': data.map((data) => data.toList()).toList(),
      'extra': extraData.export(),
    });
  }

  CardSave({
    String? id,
    required this.uid,
    required this.name,
    required this.tag,
    int? sak,
    Uint8List? atqa,
    Uint8List? ats,
    CardSaveExtra? extraData,
    this.color = Colors.deepOrange,
    this.data = const [],
  })  : id = id ?? const Uuid().v4(),
        sak = sak ?? 0,
        atqa = atqa ?? Uint8List(0),
        ats = ats ?? Uint8List(0),
        extraData = extraData ?? CardSaveExtra();
}

class CardSaveExtra {
  Uint8List ultralightSignature;
  Uint8List ultralightVersion;

  factory CardSaveExtra.import(Map<String, dynamic> data) {
    List<int> readBytes(Map<String, dynamic> data, String key) {
      return List<int>.from(
          data[key] != null ? data[key] as List<dynamic> : []);
    }

    final ultralightSignature = readBytes(data, 'ultralightSignature');
    final ultralightVersion = readBytes(data, 'ultralightVersion');

    return CardSaveExtra(
        ultralightSignature: Uint8List.fromList(ultralightSignature),
        ultralightVersion: Uint8List.fromList(ultralightVersion));
  }

  Map<String, dynamic> export() {
    Map<String, dynamic> json = {};

    if (ultralightSignature.isNotEmpty) {
      json['ultralightSignature'] = ultralightSignature;
    }

    if (ultralightVersion.isNotEmpty) {
      json['ultralightVersion'] = ultralightVersion;
    }

    return json;
  }

  CardSaveExtra({Uint8List? ultralightSignature, Uint8List? ultralightVersion})
      : ultralightSignature = ultralightSignature ?? Uint8List(0),
        ultralightVersion = ultralightVersion ?? Uint8List(0);
}

class SharedPreferencesProvider extends ChangeNotifier {
  SharedPreferencesProvider._privateConstructor();

  static final SharedPreferencesProvider _instance =
      SharedPreferencesProvider._privateConstructor();

  factory SharedPreferencesProvider() {
    return _instance;
  }

  late SharedPreferences _sharedPreferences;

  Future<void> load() async {
    _sharedPreferences = await SharedPreferences.getInstance();
  }

  ThemeMode getTheme() {
    final themeValue = _sharedPreferences.getInt('app_theme') ?? 0;
    return ThemeMode.values[themeValue];
  }

  void setTheme(ThemeMode theme) {
    _sharedPreferences.setInt('app_theme', theme.index);
  }

  bool getSideBarAutoExpansion() {
    return _sharedPreferences.getBool('sidebar_auto_expanded') ?? true;
  }

  bool getSideBarExpanded() {
    return _sharedPreferences.getBool('sidebar_expanded') ?? false;
  }

  int getSideBarExpandedIndex() {
    return _sharedPreferences.getInt('sidebar_expanded_index') ?? 1;
  }

  void setSideBarAutoExpansion(bool autoExpanded) {
    _sharedPreferences.setBool('sidebar_auto_expanded', autoExpanded);
  }

  void setSideBarExpanded(bool expanded) {
    _sharedPreferences.setBool('sidebar_expanded', expanded);
  }

  void setSideBarExpandedIndex(int index) {
    _sharedPreferences.setInt('sidebar_expanded_index', index);
  }

  int getThemeColorIndex() {
    return _sharedPreferences.getInt('app_theme_color') ?? 0;
  }

  MaterialColor getThemeColor() {
    return colors.getThemeColor(getThemeColorIndex());
  }

  Color getThemeComplementaryColor() {
    final themeMode = _sharedPreferences.getInt('app_theme') ?? 2;
    return colors.getThemeComplementary(themeMode, getThemeColorIndex());
  }

  void setThemeColor(int color) {
    _sharedPreferences.setInt('app_theme_color', color);
  }

  bool isDebugMode() {
    return _sharedPreferences.getBool('debug') ?? false;
  }

  void setDebugMode(bool value) {
    _sharedPreferences.setBool('debug', value);
  }

  List<Dictionary> getDictionaries() {
    List<Dictionary> output = [];
    final data = _sharedPreferences.getStringList('dictionaries') ?? [];
    for (var dictionary in data) {
      output.add(Dictionary.fromJson(dictionary));
    }
    return output;
  }

  void setDictionaries(List<Dictionary> dictionaries) {
    List<String> output = [];
    for (var dictionary in dictionaries) {
      if (dictionary.id != "") {
        // system empty dictionary, never save it
        output.add(dictionary.toJson());
      }
    }
    _sharedPreferences.setStringList('dictionaries', output);
  }

  List<CardSave> getCards() {
    List<CardSave> output = [];
    final data = _sharedPreferences.getStringList('cards') ?? [];
    for (var tag in data) {
      output.add(CardSave.fromJson(tag));
    }
    return output;
  }

  void setCards(List<CardSave> cards) {
    List<String> output = [];
    for (var card in cards) {
      output.add(card.toJson());
    }
    _sharedPreferences.setStringList('cards', output);
  }

  void setLocale(Locale loc) {
    for (var locale in AppLocalizations.supportedLocales) {
      if (locale.toLanguageTag().toLowerCase() ==
          loc.toLanguageTag().toLowerCase()) {
        _sharedPreferences.setString('locale', loc.toLanguageTag());
        notifyListeners();
        return;
      }
    }
  }

  String getLocaleString() {
    return _sharedPreferences.getString("locale") ?? "en";
  }

  Locale getLocale() {
    final localeId = getLocaleString();
    Locale locale;
    if (localeId.contains("-")) {
      final [lcode, ccode] = localeId.toString().split("-");
      locale = Locale(lcode, ccode);
    } else {
      locale = Locale(localeId);
    }
    if (!AppLocalizations.supportedLocales.contains(locale)) {
      return const Locale('en');
    } else {
      return locale;
    }
  }

  void clearLocale() {
    _sharedPreferences.setString('locale', "en");
    notifyListeners();
  }

  bool isDebugLogging() {
    return _sharedPreferences.getBool('debug_logging') ?? false;
  }

  void setDebugLogging(bool value) {
    _sharedPreferences.setBool('debug_logging', value);
  }

  void addLogLine(String value) {
    List<String> rows =
        _sharedPreferences.getStringList('debug_logging_value') ?? [];
    rows.add(value);

    if (rows.length > 5000) {
      rows.removeAt(0);
    }

    _sharedPreferences.setStringList('debug_logging_value', rows);
  }

  void clearLogLines() {
    _sharedPreferences.setStringList('debug_logging_value', []);
  }

  List<String> getLogLines() {
    return _sharedPreferences.getStringList('debug_logging_value') ?? [];
  }

  String dumpSettingsToJson() {
    Map<String, dynamic> settingsMap = {};

    for (var key in _sharedPreferences.getKeys()) {
      if (key == "debug_logging_value") {
        continue;
      }
      var value = _sharedPreferences.get(key) as dynamic;
      if (value == null) {
        continue;
      }
      if (value is List) {
        // this hack is needed in order to output proper json with objects instead of objects-in-strings
        value = value.map((e) => jsonDecode(e)).toList();
      }
      settingsMap[key] = value;
    }

    return jsonEncode(settingsMap);
  }

  void restoreSettingsFromJson(String jsonSettings) {
    Map<String, dynamic> settingsMap = jsonDecode(jsonSettings);

    for (var key in settingsMap.keys) {
      dynamic value = settingsMap[key];

      if (value == null) {
        continue;
      }
      switch (value) {
        case String s:
          _sharedPreferences.setString(key, s);
          break;
        case int i:
          _sharedPreferences.setInt(key, i);
          break;
        case double d:
          _sharedPreferences.setDouble(key, d);
          break;
        case bool b:
          _sharedPreferences.setBool(key, b);
          break;
        case List l:
          // this is the reverse of the hack above :)
          _sharedPreferences.setStringList(
              key, l.map((e) => jsonEncode(e)).toList());
          break;
        default:
          break;
      }
    }
  }

  bool getConfirmDelete() {
    return _sharedPreferences.getBool('confirm_delete') ?? true;
  }

  void setConfirmDelete(bool value) {
    _sharedPreferences.setBool('confirm_delete', value);
  }
}
