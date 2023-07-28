import 'dart:typed_data';
import 'dart:convert';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ChameleonDictionary {
  String id;
  String name;
  List<Uint8List> keys;

  factory ChameleonDictionary.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final name = data['name'] as String;
    final encodedKeys = data['keys'] as List<dynamic>;
    List<Uint8List> keys = [];
    for (var key in encodedKeys) {
      keys.add(Uint8List.fromList(List<int>.from(key)));
    }
    return ChameleonDictionary(id: id, name: name, keys: keys);
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'name': name,
      'keys': keys.map((key) => key.toList()).toList()
    });
  }

  factory ChameleonDictionary.fromFile(String file, String name) {
    final id = const Uuid().v4();
    final lines = file.split("\n");
    List<Uint8List> keys = [];
    for (var key in lines) {
      keys.add(hexToBytes(key));
    }
    return ChameleonDictionary(id: id, name: name, keys: keys);
  }

  Uint8List toFile() {
    String output = "";
    for (var key in keys) {
      output += "${bytesToHex(key).toUpperCase()}\n";
    }
    return const Utf8Encoder().convert(output);
  }

  ChameleonDictionary({this.id = "", this.name = "", this.keys = const []});
}

class ChameleonTagSave {
  String id;
  String uid;
  int sak;
  Uint8List atqa;
  String name;
  ChameleonTag tag;
  List<Uint8List> data;

  factory ChameleonTagSave.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final uid = data['uid'] as String;
    final sak = data['sak'] as int;
    final atqa = List<int>.from(data['atqa'] as List<dynamic>);
    final name = data['name'] as String;
    final tag = getTagTypeByValue(data['tag']);
    final encodedData = data['data'] as List<dynamic>;
    List<Uint8List> tagData = [];
    for (var block in encodedData) {
      tagData.add(Uint8List.fromList(List<int>.from(block)));
    }
    return ChameleonTagSave(
        id: id,
        uid: uid,
        sak: sak,
        name: name,
        tag: tag,
        data: tagData,
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
      'data': data.map((data) => data.toList()).toList()
    });
  }

  ChameleonTagSave(
      {required this.id,
      required this.uid,
      required this.name,
      required this.sak,
      required this.atqa,
      required this.tag,
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
    return _sharedPreferences.getBool('sidebar_autoexpanded') ?? true;
  }

  bool getSideBarExpanded() {
    return _sharedPreferences.getBool('sidebar_expanded') ?? false;
  }

  int getSideBarExpandedIndex() {
    return _sharedPreferences.getInt('sidebar_expandedindex') ?? 1;
  }

  void setSideBarAutoExpansion(bool autoExpanded) {
    _sharedPreferences.setBool('sidebar_autoexpanded', autoExpanded);
  }

  void setSideBarExpanded(bool expanded) {
    _sharedPreferences.setBool('sidebar_expanded', expanded);
  }

  void setSideBarExpandedIndex(int index) {
    _sharedPreferences.setInt('sidebar_expandedindex', index);
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

  bool getDeveloperMode() {
    return _sharedPreferences.getBool('developer_mode') ?? false;
  }

  void setDeveloperMode(bool value) {
    _sharedPreferences.setBool('developer_mode', value);
  }

  List<ChameleonDictionary> getChameleonDictionaries() {
    List<ChameleonDictionary> output = [];
    final data = _sharedPreferences.getStringList('dictionaries') ?? [];
    for (var dictionary in data) {
      output.add(ChameleonDictionary.fromJson(dictionary));
    }
    return output;
  }

  void setChameleonDictionaries(List<ChameleonDictionary> dictionaries) {
    List<String> output = [];
    for (var dictionary in dictionaries) {
      if (dictionary.id != "") {
        // system empty dictionary, never save it
        output.add(dictionary.toJson());
      }
    }
    _sharedPreferences.setStringList('dictionaries', output);
  }

  List<ChameleonTagSave> getChameleonTags() {
    List<ChameleonTagSave> output = [];
    final data = _sharedPreferences.getStringList('cards') ?? [];
    for (var tag in data) {
      output.add(ChameleonTagSave.fromJson(tag));
    }
    return output;
  }

  void setChameleonTags(List<ChameleonTagSave> tags) {
    List<String> output = [];
    for (var tag in tags) {
      output.add(tag.toJson());
    }
    _sharedPreferences.setStringList('cards', output);
  }
}
