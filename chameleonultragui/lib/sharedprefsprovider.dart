import 'dart:typed_data';
import 'dart:convert';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/colors.dart' as colors;
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class Dictionary {
  String id;
  String name;
  List<Uint8List> keys;
  Color color;
  String? folderId; // Add folder association

  factory Dictionary.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final name = data['name'] as String;
    final encodedKeys = data['keys'] as List<dynamic>;
    if (data['color'] == null) {
      data['color'] = colorToHex(Colors.deepOrange);
    }
    final color = hexToColor(data['color']);
    final folderId = data['folderId'] as String?;
    List<Uint8List> keys = [];
    for (var key in encodedKeys) {
      keys.add(Uint8List.fromList(List<int>.from(key)));
    }
    return Dictionary(id: id, name: name, keys: keys, color: color, folderId: folderId);
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'name': name,
      'color': colorToHex(color),
      'folderId': folderId,
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
      this.color = Colors.deepOrange,
      this.folderId})
      : id = id ?? const Uuid().v4();
}

class DictionaryFolder {
  String id;
  String name;
  Color color;
  String? parentId;
  List<String> dictionaryIds;
  List<String> subFolderIds;

  factory DictionaryFolder.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final name = data['name'] as String;
    final color = data['color'] == null ? Colors.blue : hexToColor(data['color']);
    final parentId = data['parentId'] as String?;
    final dictionaryIds = List<String>.from(data['dictionaryIds'] ?? []);
    final subFolderIds = List<String>.from(data['subFolderIds'] ?? []);

    return DictionaryFolder(
        id: id,
        name: name,
        color: color,
        parentId: parentId,
        dictionaryIds: dictionaryIds,
        subFolderIds: subFolderIds);
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'name': name,
      'color': colorToHex(color),
      'parentId': parentId,
      'dictionaryIds': dictionaryIds,
      'subFolderIds': subFolderIds,
    });
  }

  DictionaryFolder({
    String? id,
    required this.name,
    this.color = Colors.blue,
    this.parentId,
    this.dictionaryIds = const [],
    this.subFolderIds = const [],
  }) : id = id ?? const Uuid().v4();
}

class CardFolder {
  String id;
  String name;
  Color color;
  String? parentId;
  List<String> cardIds;
  List<String> subFolderIds;

  factory CardFolder.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final name = data['name'] as String;
    final color = data['color'] == null ? Colors.blue : hexToColor(data['color']);
    final parentId = data['parentId'] as String?;
    final cardIds = List<String>.from(data['cardIds'] ?? []);
    final subFolderIds = List<String>.from(data['subFolderIds'] ?? []);

    return CardFolder(
        id: id,
        name: name,
        color: color,
        parentId: parentId,
        cardIds: cardIds,
        subFolderIds: subFolderIds);
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'name': name,
      'color': colorToHex(color),
      'parentId': parentId,
      'cardIds': cardIds,
      'subFolderIds': subFolderIds,
    });
  }

  CardFolder({
    String? id,
    required this.name,
    this.color = Colors.blue,
    this.parentId,
    this.cardIds = const [],
    this.subFolderIds = const [],
  }) : id = id ?? const Uuid().v4();
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
  String? folderId; // Add folder association

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
    final folderId = data['folderId'] as String?;
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
        atqa: Uint8List.fromList(atqa),
        folderId: folderId);
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
      'folderId': folderId,
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
    this.folderId,
  })  : id = id ?? const Uuid().v4(),
        sak = sak ?? 0,
        atqa = atqa ?? Uint8List(0),
        ats = ats ?? Uint8List(0),
        extraData = extraData ?? CardSaveExtra();
}

class CardSaveExtra {
  Uint8List ultralightSignature;
  Uint8List ultralightVersion;
  List<int> ultralightCounters;

  factory CardSaveExtra.import(Map<String, dynamic> data) {
    List<int> readBytes(Map<String, dynamic> data, String key) {
      return List<int>.from(
          data[key] != null ? data[key] as List<dynamic> : []);
    }

    final ultralightSignature = readBytes(data, 'ultralightSignature');
    final ultralightVersion = readBytes(data, 'ultralightVersion');
    final ultralightCounters = data['ultralightCounters'] != null
        ? List<int>.from(data['ultralightCounters'] as List<dynamic>)
        : <int>[];

    return CardSaveExtra(
        ultralightSignature: Uint8List.fromList(ultralightSignature),
        ultralightVersion: Uint8List.fromList(ultralightVersion),
        ultralightCounters: ultralightCounters);
  }

  Map<String, dynamic> export() {
    Map<String, dynamic> json = {};

    if (ultralightSignature.isNotEmpty) {
      json['ultralightSignature'] = ultralightSignature;
    }

    if (ultralightVersion.isNotEmpty) {
      json['ultralightVersion'] = ultralightVersion;
    }

    if (ultralightCounters.isNotEmpty) {
      json['ultralightCounters'] = ultralightCounters;
    }

    return json;
  }

  CardSaveExtra(
      {Uint8List? ultralightSignature,
      Uint8List? ultralightVersion,
      List<int>? ultralightCounters})
      : ultralightSignature = ultralightSignature ?? Uint8List(0),
        ultralightVersion = ultralightVersion ?? Uint8List(0),
        ultralightCounters = ultralightCounters ?? <int>[];
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

  bool isEmulatedChameleon() {
    return _sharedPreferences.getBool('emulate_device') ?? false;
  }

  void setEmulatedChameleon(bool value) {
    _sharedPreferences.setBool('emulate_device', value);
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

  List<CardFolder> getFolders() {
    List<CardFolder> output = [];
    final data = _sharedPreferences.getStringList('card_folders') ?? [];
    for (var folder in data) {
      output.add(CardFolder.fromJson(folder));
    }
    return output;
  }

  void setFolders(List<CardFolder> folders) {
    List<String> output = [];
    for (var folder in folders) {
      output.add(folder.toJson());
    }
    _sharedPreferences.setStringList('card_folders', output);
  }

  CardFolder? getFolder(String folderId) {
    final folders = getFolders();
    try {
      return folders.firstWhere((folder) => folder.id == folderId);
    } catch (_) {
      return null;
    }
  }

  List<CardSave> getCardsInFolder(String? folderId) {
    final cards = getCards();
    return cards.where((card) => card.folderId == folderId).toList();
  }

  List<CardFolder> getSubfolders(String? parentId) {
    final folders = getFolders();
    return folders.where((folder) => folder.parentId == parentId).toList();
  }

  void moveCardToFolder(String cardId, String? folderId) {
    final cards = getCards();
    final folders = getFolders();
    
    // Update card
    for (var card in cards) {
      if (card.id == cardId) {
        // Remove from old folder
        if (card.folderId != null) {
          for (var folder in folders) {
            if (folder.id == card.folderId) {
              folder.cardIds.remove(cardId);
              break;
            }
          }
        }
        
        // Add to new folder
        card.folderId = folderId;
        if (folderId != null) {
          for (var folder in folders) {
            if (folder.id == folderId) {
              if (!folder.cardIds.contains(cardId)) {
                folder.cardIds.add(cardId);
              }
              break;
            }
          }
        }
        break;
      }
    }
    
    setCards(cards);
    setFolders(folders);
  }

  void createFolder(String name, {String? parentId, Color? color}) {
    final folders = getFolders();
    final newFolder = CardFolder(
      name: name,
      parentId: parentId,
      color: color ?? Colors.blue,
    );
    
    // Add to parent if specified
    if (parentId != null) {
      for (var folder in folders) {
        if (folder.id == parentId) {
          folder.subFolderIds.add(newFolder.id);
          break;
        }
      }
    }
    
    folders.add(newFolder);
    setFolders(folders);
  }

  void deleteFolder(String folderId, {bool moveCardsToParent = true}) {
    final folders = getFolders();
    final cards = getCards();
    CardFolder? folderToDelete;
    
    // Find folder to delete
    for (var folder in folders) {
      if (folder.id == folderId) {
        folderToDelete = folder;
        break;
      }
    }
    
    if (folderToDelete == null) return;
    
    // Handle cards in folder
    if (moveCardsToParent) {
      for (var card in cards) {
        if (card.folderId == folderId) {
          card.folderId = folderToDelete.parentId;
        }
      }
    } else {
      // Delete cards in folder
      cards.removeWhere((card) => card.folderId == folderId);
    }
    
    // Handle subfolders - move to parent
    for (var folder in folders) {
      if (folder.parentId == folderId) {
        folder.parentId = folderToDelete.parentId;
      }
    }
    
    // Remove from parent folder
    if (folderToDelete.parentId != null) {
      for (var folder in folders) {
        if (folder.id == folderToDelete.parentId) {
          folder.subFolderIds.remove(folderId);
          break;
        }
      }
    }
    
    // Remove folder
    folders.removeWhere((folder) => folder.id == folderId);
    
    setCards(cards);
    setFolders(folders);
  }

  void renameFolder(String folderId, String newName) {
    final folders = getFolders();
    for (var folder in folders) {
      if (folder.id == folderId) {
        folder.name = newName;
        break;
      }
    }
    setFolders(folders);
  }

  // Dictionary Folder Management Methods
  List<DictionaryFolder> getDictionaryFolders() {
    List<DictionaryFolder> output = [];
    final data = _sharedPreferences.getStringList('dictionary_folders') ?? [];
    for (var folder in data) {
      output.add(DictionaryFolder.fromJson(folder));
    }
    return output;
  }

  void setDictionaryFolders(List<DictionaryFolder> folders) {
    List<String> output = [];
    for (var folder in folders) {
      output.add(folder.toJson());
    }
    _sharedPreferences.setStringList('dictionary_folders', output);
  }

  DictionaryFolder? getDictionaryFolder(String folderId) {
    final folders = getDictionaryFolders();
    for (var folder in folders) {
      if (folder.id == folderId) {
        return folder;
      }
    }
    return null;
  }

  List<DictionaryFolder> getDictionarySubfolders(String? parentId) {
    final folders = getDictionaryFolders();
    return folders.where((folder) => folder.parentId == parentId).toList();
  }

  List<Dictionary> getDictionariesInFolder(String? folderId) {
    final dictionaries = getDictionaries();
    return dictionaries.where((dict) => dict.folderId == folderId).toList();
  }

  void moveDictionaryToFolder(String dictionaryId, String? targetFolderId) {
    final dictionaries = getDictionaries();
    for (var dictionary in dictionaries) {
      if (dictionary.id == dictionaryId) {
        dictionary.folderId = targetFolderId;
        break;
      }
    }
    setDictionaries(dictionaries);
  }

  void createDictionaryFolder(String name, String? parentId, {Color color = Colors.blue}) {
    final folders = getDictionaryFolders();
    
    final newFolder = DictionaryFolder(
      name: name,
      parentId: parentId,
      color: color,
    );

    // Add to parent if specified
    if (parentId != null) {
      for (var folder in folders) {
        if (folder.id == parentId) {
          folder.subFolderIds.add(newFolder.id);
          break;
        }
      }
    }
    
    folders.add(newFolder);
    setDictionaryFolders(folders);
  }

  void deleteDictionaryFolder(String folderId, {bool moveDictionariesToParent = true}) {
    final folders = getDictionaryFolders();
    final dictionaries = getDictionaries();
    
    // Find folder to delete
    DictionaryFolder? folderToDelete;
    for (var folder in folders) {
      if (folder.id == folderId) {
        folderToDelete = folder;
        break;
      }
    }
    
    if (folderToDelete == null) return;
    
    // Handle dictionaries in folder
    for (var dictionary in dictionaries) {
      if (dictionary.folderId == folderId) {
        if (moveDictionariesToParent) {
          dictionary.folderId = folderToDelete.parentId;
        } else {
          // Delete dictionaries in folder
          dictionaries.removeWhere((d) => d.id == dictionary.id);
        }
      }
    }
    
    // Handle subfolders - move to parent
    for (var folder in folders) {
      if (folder.parentId == folderId) {
        folder.parentId = folderToDelete.parentId;
      }
    }
    
    // Remove from parent folder
    if (folderToDelete.parentId != null) {
      for (var folder in folders) {
        if (folder.id == folderToDelete.parentId) {
          folder.subFolderIds.remove(folderId);
          break;
        }
      }
    }
    
    // Remove folder
    folders.removeWhere((folder) => folder.id == folderId);
    
    setDictionaries(dictionaries);
    setDictionaryFolders(folders);
  }

  void renameDictionaryFolder(String folderId, String newName) {
    final folders = getDictionaryFolders();
    for (var folder in folders) {
      if (folder.id == folderId) {
        folder.name = newName;
        break;
      }
    }
    setDictionaryFolders(folders);
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
