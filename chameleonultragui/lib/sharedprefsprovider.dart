import 'dart:typed_data';
import 'dart:convert';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:uuid/v4.dart';

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

    final String id;
    final String uid;
    final int sak;
    final List<int> atqa;
    final List<int> ats;
    final String name;
    final TagType tag;
    final Color color;
    List<Uint8List> tagData = [];

    if (data['Created'] == "proxmark3") {
      // PM3 JSON, parse that
      id = const Uuid().v4();
      uid = data['Card']['UID'] as String;
      String sakString = data['Card']['SAK'] as String;
      sak = hexToBytes(sakString)[0];
      String atqaString = data['Card']['ATQA'] as String;
      atqa = [
        int.parse(atqaString.substring(2), radix: 16),
        int.parse(atqaString.substring(0, 2), radix: 16)
      ];
      ats = [];
      name = uid;
      color = Colors.deepOrange;
      
      List<String> blocks = [];
      Map<String, dynamic> blockData = data['blocks'] as Map<String, dynamic>;
      for (int i = 0; blockData.containsKey(i.toString()); i++) {
        blocks.add(blockData[i.toString()] as String);
      }

      //Check if a block has more than 16 Bytes, Ultralight, return as unknown
      if (blocks[0].length > 32) {
        tag = TagType.unknown;
      } else {
        tag = mfClassicTypeToTagType(mfClassicGetCardType(blocks.length));
      }

      for (var block in blocks) {
        tagData.add(hexToBytes(block));
      }
      
    } else {
      id = data['id'] as String;
      uid = data['uid'] as String;
      sak = data['sak'] as int;
      atqa = List<int>.from(data['atqa'] as List<dynamic>);
      ats = List<int>.from((data['ats'] ?? []) as List<dynamic>);
      name = data['name'] as String;
      tag = getTagTypeByValue(data['tag']);
      if (data['color'] == null) {
        data['color'] = colorToHex(Colors.deepOrange);
      }
      color = hexToColor(data['color']);
      final encodedData = data['data'] as List<dynamic>;
      for (var block in encodedData) {
        tagData.add(Uint8List.fromList(List<int>.from(block)));
      }
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
        sak = sak ?? 0,
        atqa = atqa ?? Uint8List(0),
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
    final themeValue = _sharedPreferences.getInt('app_theme') ?? 0;
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

  MaterialColor getThemeColor() {
    final themeValue = _sharedPreferences.getInt('app_theme_color') ?? 0;
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

  Locale getLocale() {
    final loc = _sharedPreferences.getString('locale');
    if (loc != null && loc.contains("-")) {
      var lcode = loc.toString().split("-").first;
      var ccode = loc.toString().split("-").last;
      if (!AppLocalizations.supportedLocales.contains(Locale(lcode, ccode))) {
        return const Locale('en');
      } else {
        return Locale(lcode, ccode);
      }
    } else if (loc != null) {
      if (!AppLocalizations.supportedLocales.contains(Locale(loc.toString()))) {
        return const Locale('en');
      } else {
        return Locale(loc.toString());
      }
    }
    return const Locale('en');
  }

  void clearLocale() {
    _sharedPreferences.setString('locale', "en");
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
}
