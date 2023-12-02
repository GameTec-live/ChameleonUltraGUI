import 'dart:typed_data';
import 'dart:convert';
import 'package:chameleonultragui/bridge/chameleon.dart';
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
    if (data['color'] == null) {
      data['color'] = colorToHex(Colors.deepPurple);
    }
    final color = hexToColor(data['color']);
    final encodedData = data['data'] as List<dynamic>;
    List<Uint8List> tagData = [];
    for (var block in encodedData) {
      tagData.add(Uint8List.fromList(List<int>.from(block)));
    }
    return CardSave(
        id: id,
        uid: uid,
        sak: sak,
        name: name,
        tag: tag,
        data: tagData,
        color: color,
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
    });
  }

  CardSave(
      {String? id,
      required this.uid,
      required this.name,
      required this.tag,
      int? sak,
      Uint8List? atqa,
      Uint8List? ats,
      this.color = Colors.deepOrange,
      this.data = const []})
      : id = id ?? const Uuid().v4(),
        sak = sak ?? 0x08,
        atqa = atqa ?? Uint8List.fromList([0x04, 0x00]),
        ats = ats ?? Uint8List(0);
}

class SharedPreferencesProvider extends ChangeNotifier {
  SharedPreferencesProvider._privateConstructor();

  static final SharedPreferencesProvider _instance =
      SharedPreferencesProvider._privateConstructor();

  factory SharedPreferencesProvider() {
    return _instance;
  }

  late SharedPreferences _sharedPreferences;

  SharedPreferences get sharedPreferences => _sharedPreferences;

  Future<void> load() async {
    _sharedPreferences = await SharedPreferences.getInstance();
  }

  ThemeMode getTheme() {
    final themeValue = _sharedPreferences.getInt('app_theme') ?? 2;
    switch (themeValue) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void setTheme(ThemeMode theme) {
    switch (theme) {
      case ThemeMode.light:
        _sharedPreferences.setInt('app_theme', 1);
        break;
      case ThemeMode.dark:
        _sharedPreferences.setInt('app_theme', 2);
        break;
      default:
        _sharedPreferences.remove('app_theme');
        break;
    }
  }

  bool getSideBarAutoExpansion() {
    return _sharedPreferences.getBool('sidebar_auto_expanded') ?? false;
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

  MaterialColor getThemeColor() {
    final themeValue = _sharedPreferences.getInt('app_theme_color') ?? 1;
    switch (themeValue) {
      case 1:
        return Colors.deepPurple;
      case 2:
        return Colors.blue;
      case 3:
        return Colors.green;
      case 4:
        return Colors.indigo;
      case 5:
        return Colors.lime;
      case 6:
        return Colors.red;
      case 7:
        return Colors.yellow;
      case 8:
        return Colors.purple;
      case 9:
        return Colors.pink;
      default:
        return Colors.deepOrange;
    }
  }

  Color getThemeComplementaryColor() {
    final themeValue = _sharedPreferences.getInt('app_theme_color') ?? 0;
    final themeMode = _sharedPreferences.getInt('app_theme') ?? 2;
    switch (themeMode) {
      case 1:
        switch (themeValue) {
          case 1:
            return const Color.fromARGB(255, 238, 227, 252);
          case 2:
            return const Color.fromARGB(255, 234, 252, 255);
          case 3:
            return const Color.fromARGB(255, 238, 255, 248);
          case 4:
            return const Color.fromARGB(248, 248, 239, 255);
          case 5:
            return const Color.fromARGB(255, 255, 255, 240);
          case 6:
            return const Color.fromARGB(255, 253, 238, 238);
          case 7:
            return const Color.fromARGB(255, 248, 252, 216);
          case 8:
            return const Color.fromARGB(255, 238, 227, 252);
          case 9:
            return const Color.fromARGB(255, 238, 227, 252);
          default:
            return const Color.fromARGB(255, 255, 236, 236);
        }
      case 2:
        switch (themeValue) {
          case 1:
            return const Color.fromARGB(30, 116, 58, 183);
          case 2:
            return const Color.fromARGB(44, 62, 216, 243);
          case 3:
            return const Color.fromARGB(50, 175, 76, 172);
          case 4:
            return const Color.fromARGB(46, 130, 51, 196);
          case 5:
            return const Color.fromARGB(48, 110, 116, 29);
          case 6:
            return const Color.fromARGB(47, 188, 43, 201);
          case 7:
            return const Color.fromARGB(44, 58, 104, 202);
          case 8:
            return const Color.fromARGB(30, 116, 58, 183);
          case 9:
            return const Color.fromARGB(30, 116, 58, 183);
          default:
            return const Color.fromARGB(16, 202, 43, 43);
        }
      default:
        switch (themeValue) {
          case 1:
            return const Color.fromARGB(30, 116, 58, 183);
          case 2:
            return const Color.fromARGB(44, 62, 216, 243);
          case 3:
            return const Color.fromARGB(50, 175, 76, 172);
          case 4:
            return const Color.fromARGB(46, 130, 51, 196);
          case 5:
            return const Color.fromARGB(48, 110, 116, 29);
          case 6:
            return const Color.fromARGB(47, 188, 43, 201);
          case 7:
            return const Color.fromARGB(44, 58, 104, 202);
          default:
            return const Color.fromARGB(16, 202, 43, 43);
        }
    }
  }

  void setThemeColor(int color) {
    _sharedPreferences.setInt('app_theme_color', color);
  }

  bool isDebugMode() {
    return _sharedPreferences.getBool('debug') ?? true;
  }

  bool isShowAll() {
    return _sharedPreferences.getBool('all_pages') ?? false;
  }

  void setShowAll(bool value) {
    _sharedPreferences.setBool('all_pages', value);
  }

  void setB(String flag, bool value){
    _sharedPreferences.setBool(flag, value);
  }

  bool getB(String flag){
    return _sharedPreferences.getBool(flag) ?? false;
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

  Locale getLocale() {
    final loc = _sharedPreferences.getString('locale');
    if (loc != null && loc.contains("-")) {
      var lcode = loc.toString().split("-").first;
      var ccode = loc.toString().split("-").last;
      if (!AppLocalizations.supportedLocales.contains(Locale(lcode, ccode))) {
        return const Locale('ru');
      } else {
        return Locale(lcode, ccode);
      }
    } else if (loc != null) {
      if (!AppLocalizations.supportedLocales.contains(Locale(loc.toString()))) {
        return const Locale('ru');
      } else {
        return Locale(loc.toString());
      }
    }
    return const Locale('ru');
  }

  void clearLocale() {
    _sharedPreferences.setString('locale', "ru");
    notifyListeners();
  }

  String getFlag(Locale loc) {
    switch (loc.toLanguageTag()) {
      case 'en':
        return 'English';
      case 'zh':
        return '中文';
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'de':
        return 'Deutsch';
      case 'de-AT':
        return 'Deutsch (Österreich)';
      case 'pt':
        return 'Português';
      case 'pt-BR':
        return 'Português (Brasil)';
      case 'ru':
        return 'Русский';
      case 'it':
        return 'Italiano';
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      case 'nl':
        return 'Dutch';
      case 'ar':
        return 'العربية ';
      case 'tr':
        return 'Türkçe';
      case 'pl':
        return 'Polski';
      case 'sv':
        return 'Svenska';
      case 'da':
        return 'Dansk';
      case 'no':
        return 'Norsk';
      case 'fi':
        return 'Suomi';
      case 'cs':
        return 'Čeština';
      case 'hu':
        return 'Magyar';
      case 'el':
        return 'Ελληνικά';
      case 'he':
        return 'עברית ';
      case 'th':
        return 'ไทย ';
      case 'id':
        return 'Bahasa Indonesia';
      case 'uk':
        return 'Українська';
      case 'ro':
        return 'Română';
      case 'ms':
        return 'Bahasa Melayu';
      case 'hi':
        return 'हिन्दी';
      case 'vi':
        return 'Tiếng Việt';
      case 'ca':
        return 'Català';
      case 'bg':
        return 'Български';
      default:
        return 'Unknown';
    }
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
      dynamic value = _sharedPreferences.get(key);
      String typeKey = '${value.runtimeType};$key';
      if (value is List<String>) {
        settingsMap[typeKey] = jsonEncode(value);
      } else {
        settingsMap[typeKey] = value.toString();
      }
    }
    String jsonSettings = jsonEncode(settingsMap); // This will create the nested json

    return jsonSettings;
  }

  void restoreSettingsFromJson(String jsonSettings) {
    Map<String, dynamic> settingsMap = jsonDecode(jsonSettings);

    for (var key in settingsMap.keys) {
      var splitKey = key.split(';');
      var type = splitKey[0];
      var actualKey = splitKey[1];

      dynamic value = settingsMap[key];

      if (value != null) {
        switch (type) {
          case 'String':
            _sharedPreferences.setString(actualKey, value);
            break;
          case 'int':
            _sharedPreferences.setInt(actualKey, int.parse(value));
            break;
          case 'double':
            _sharedPreferences.setDouble(actualKey, double.parse(value));
            break;
          case 'bool':
            _sharedPreferences.setBool(actualKey, value == 'true');
            break;
          case 'List<String>':
            // Decode the JSON array string back to List<String>
            List<String> listValue = List<String>.from(jsonDecode(value));
            _sharedPreferences.setStringList(actualKey, listValue);
            break;
          default:
            break;
        }
      }
    }
  }


}
