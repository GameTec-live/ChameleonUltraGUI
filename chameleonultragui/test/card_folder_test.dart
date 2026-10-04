import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy card JSON remains outside folders', () {
    final card = CardSave(
      id: 'card',
      uid: '01 02 03 04',
      name: 'Legacy card',
      tag: TagType.mifare1K,
    );

    final decoded = CardSave.fromJson(card.toJson());

    expect(decoded.folderId, isNull);
  });

  test('folder bundle round-trips nested folders and cards', () {
    final root = CardFolder(
      id: 'root',
      name: 'Building',
      color: Colors.blue,
    );
    final child = CardFolder(
      id: 'child',
      name: 'Second floor',
      color: Colors.green,
      parentId: root.id,
    );
    final card = CardSave(
      id: 'card',
      uid: '01 02 03 04',
      name: 'Office',
      tag: TagType.mifare1K,
      folderId: child.id,
    );
    final source = CardFolderBundle(
      rootFolderId: root.id,
      folders: [root, child],
      cards: [card],
    ).toJson();

    final decoded = CardFolderBundle.fromJson(source);

    expect(decoded.rootFolderId, root.id);
    expect(decoded.folders, hasLength(2));
    expect(decoded.folders.last.parentId, root.id);
    expect(decoded.cards.single.folderId, child.id);
    expect(
      decoded.folders.first.color.toARGB32(),
      Colors.blue.toARGB32(),
    );
  });

  test('folder bundle rejects unrelated JSON', () {
    expect(
      () => CardFolderBundle.fromJson('{"name":"not a folder"}'),
      throwsFormatException,
    );
  });

  test('dictionary folder bundle round-trips hierarchy and membership', () {
    final root = DictionaryFolder(
      id: 'dictionary-root',
      name: 'MIFARE',
      color: Colors.purple,
    );
    final child = DictionaryFolder(
      id: 'dictionary-child',
      name: 'Site A',
      parentId: root.id,
    );
    final dictionary = Dictionary(
      id: 'dictionary',
      name: 'Keys',
      keys: [
        Uint8List.fromList([0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
      ],
      keyLength: 12,
      folderId: child.id,
    );

    final decoded = DictionaryFolderBundle.fromJson(
      DictionaryFolderBundle(
        rootFolderId: root.id,
        folders: [root, child],
        dictionaries: [dictionary],
      ).toJson(),
    );

    expect(decoded.rootFolderId, root.id);
    expect(decoded.folders.last.parentId, root.id);
    expect(decoded.dictionaries.single.folderId, child.id);
    expect(decoded.dictionaries.single.keys.single,
        orderedEquals(dictionary.keys.single));
  });

  test('legacy dictionary JSON remains outside folders', () {
    final dictionary = Dictionary(
      id: 'legacy-dictionary',
      name: 'Legacy',
      keys: const [],
    );

    expect(Dictionary.fromJson(dictionary.toJson()).folderId, isNull);
  });
}
