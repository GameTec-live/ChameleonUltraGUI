import 'dart:async';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/chameleon.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:logger/logger.dart';

// TODO: Decide if we want to change variable names to camelCase or not
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

class Keytag {
  final int id;
  final String name;
  final String description;
  final String UID;
  final ChameleonTag type;
  final List<Uint8List> data;

  const Keytag({
    required this.id,
    required this.name,
    required this.description,
    required this.UID,
    required this.type,
    required this.data,
  });

  // Convert a keytag into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'UID': UID,
      'type': type,
      'data': data,
    };
  }

  // Implement toString to make it easier to see information about
  // each dog when using the print statement.
  @override
  String toString() {
    return 'keytag{id: $id, name: $name, description: $description, UID: $UID, Type: $type}';
  }
}

class Setting {
  final int id;
  final String name;
  final int value; //booleans and int values
  final String SValue; //string values
  const Setting({
    required this.id,
    required this.name,
    required this.value,
    required this.SValue,
  });

  // Convert a setting into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'value': value,
      'SValue': SValue,
    };
  }

  // Implement toString to make it easier to see information about
  // each dog when using the print statement.
  @override
  String toString() {
    return 'keytags{id: $id, name: $name, value: $value, SValue: $SValue}';
  }
}

void main() async {
  Logger log = Logger();
  // Avoid errors caused by flutter upgrade.
  // Importing 'package:flutter/widgets.dart' is required.
  WidgetsFlutterBinding.ensureInitialized();
  // Open the database and store the reference.
  final database = openDatabase(
    // Set the path to the database. Note: Using the `join` function from the
    // `path` package is best practice to ensure the path is correctly
    // constructed for each platform.
    join(await getDatabasesPath(),
        'data.db'), // We probably want to incorporate some kind of encryption here.
    // When the database is first created, create a table to store dogs.
    onCreate: (db, version) {
      // Run the CREATE TABLE statement on the database.
      db.execute(
          'CREATE TABLE keytags(id INTEGER PRIMARY KEY, name TEXT, description TEXT, UID TEXT, type TEXT, data BLOB)');
      return db.execute(
          'CREATE TABLE settings(id INTEGER PRIMARY KEY, name TEXT, value INTEGER, SValue TEXT)');
    },
    // Set the version. This executes the onCreate function and provides a
    // path to perform database upgrades and downgrades.
    version: 1,
  );

  Future<void> insertkeytag(Keytag keytag) async {
    // Get a reference to the database.
    final db = await database;

    // Insert the keytag into the correct table. You might also specify the
    // `conflictAlgorithm` to use in case the same dog is inserted twice.
    //
    // In this case, replace any previous data.
    await db.insert(
      'keytags',
      keytag.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertSetting(Setting setting) async {
    // Get a reference to the database.
    final db = await database;

    // Insert the setting into the correct table. You might also specify the
    // `conflictAlgorithm` to use in case the same dog is inserted twice.
    //
    // In this case, replace any previous data.
    await db.insert(
      'settings',
      setting.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // A method that retrieves all the keytags from the keytag table.
  Future<List<Keytag>> keytags() async {
    // Get a reference to the database.
    final db = await database;

    // Query the table for all The Dogs.
    final List<Map<String, dynamic>> maps = await db.query('keytags');

    // Convert the List<Map<String, dynamic> into a List<Dog>.
    return List.generate(maps.length, (i) {
      return Keytag(
        id: maps[i]['id'],
        name: maps[i]['name'],
        description: maps[i]['description'],
        UID: maps[i]['UID'],
        type: maps[i]['type'],
        data: maps[i]['data'],
      );
    });
  }

  // A method that retrieves all the settings from the settings table.
  Future<List<Setting>> settings() async {
    // Get a reference to the database.
    final db = await database;

    // Query the table for all The Dogs.
    final List<Map<String, dynamic>> maps = await db.query('settings');

    // Convert the List<Map<String, dynamic> into a List<Dog>.
    return List.generate(maps.length, (i) {
      return Setting(
        id: maps[i]['id'],
        name: maps[i]['name'],
        value: maps[i]['value'],
        SValue: maps[i]['SValue'],
      );
    });
  }

  Future<void> updateKeytag(Keytag keytag) async {
    // Get a reference to the database.
    final db = await database;

    // Update the given keytag.
    await db.update(
      'keytags',
      keytag.toMap(),
      // Ensure that the keytag has a matching id.
      where: 'id = ?',
      // Pass the keytag's id as a whereArg to prevent SQL injection.
      whereArgs: [keytag.id],
    );
  }

  Future<void> updateSetting(Setting setting) async {
    // Get a reference to the database.
    final db = await database;

    // Update the given keytag.
    await db.update(
      'settings',
      setting.toMap(),
      // Ensure that the keytag has a matching id.
      where: 'id = ?',
      // Pass the keytag's id as a whereArg to prevent SQL injection.
      whereArgs: [setting.id],
    );
  }

  Future<void> deleteKeytag(int id) async {
    // Get a reference to the database.
    final db = await database;

    // Remove the Keytag from the database.
    await db.delete(
      'keytags',
      // Use a `where` clause to delete a specific tag.
      where: 'id = ?',
      // Pass the keytag's id as a whereArg to prevent SQL injection.
      whereArgs: [id],
    );
  }

  //Everything past this point is for testing and can be removed once we know it works properly.

  var key = const Keytag(
    id: 0,
    name: 'home',
    description: '',
    UID: 'FFFFFFFF',
    type: ChameleonTag.mifare1K,
    data: [],
  );

  await insertkeytag(key);

  log.d(await keytags());

  key = const Keytag(
    id: 0,
    name: 'work',
    description: '',
    UID: 'FFFFFFFF',
    type: ChameleonTag.mifare1K,
    data: [],
  );
  await updateKeytag(key);

  log.d(await keytags());

  await deleteKeytag(key.id);

  log.d(await keytags());
}
