import 'dart:typed_data';
import 'dart:convert';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
    final id = const Uuid().v4();
    final lines = file.split("\n");
    List<Uint8List> keys = [];
    for (var key in lines) {
      keys.add(hexToBytes(key));
    }
    return Dictionary(id: id, name: name, keys: keys);
  }

  Uint8List toFile() {
    String output = "";
    for (var key in keys) {
      output += "${bytesToHex(key).toUpperCase()}\n";
    }
    return const Utf8Encoder().convert(output);
  }

  Dictionary(
      {this.id = "",
      this.name = "",
      this.keys = const [],
      this.color = Colors.deepOrange});
}

class CardSave {
  String id;
  String uid;
  int sak;
  Uint8List atqa;
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
    final name = data['name'] as String;
    final tag = getTagTypeByValue(data['tag']);
    if (data['color'] == null) {
      data['color'] = colorToHex(Colors.deepOrange);
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
        atqa: Uint8List.fromList(atqa));
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'uid': uid,
      'sak': sak,
      'atqa': atqa.toList(),
      'name': name,
      'tag': tag.value,
      'color': colorToHex(color),
      'data': data.map((data) => data.toList()).toList()
    });
  }

  CardSave(
      {required this.id,
      required this.uid,
      required this.name,
      required this.sak,
      required this.atqa,
      required this.tag,
      this.color = Colors.deepOrange,
      this.data = const []});
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

  String? get httpCorsProxy  {
    return _sharedPreferences.getString('http_cors_proxy');
  }

  set httpCorsProxy(String? proxy) {
    if (proxy == null) {
      _sharedPreferences.remove('http_cors_proxy');
    } else {
      _sharedPreferences.setString('http_cors_proxy', proxy);
    }
  }
}
