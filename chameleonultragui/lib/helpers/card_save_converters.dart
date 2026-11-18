import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';

import 'dart:convert';
import 'dart:typed_data';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

CardSave pm3JsonToCardSave(String json) {
  Map<String, dynamic> data = jsonDecode(json);

  final String id = const Uuid().v4();
  final String uid = data['Card']['UID'] as String;
  String sakString = data['Card']['SAK'] as String;
  final int sak = hexToBytes(sakString)[0];
  String atqaString = data['Card']['ATQA'] as String;
  final List<int> atqa = [
    int.parse(atqaString.substring(2), radix: 16),
    int.parse(atqaString.substring(0, 2), radix: 16)
  ];
  final List<int> ats = [];
  final String name = uid;
  const Color color = Colors.deepOrange;
  final TagType tag;
  List<Uint8List> tagData = [];

  List<String> blocks = [];
  Map<String, dynamic> blockData = data['blocks'] as Map<String, dynamic>;
  for (int i = 0; blockData.containsKey(i.toString()); i++) {
    blocks.add(blockData[i.toString()] as String);
  }

  //Check if a block has more than 16 Bytes, Ultralight, return as unknown
  if (blocks[0].length > 32) {
    tag = TagType.unknown;
  } else {
    tag = mfClassicGetChameleonTagType(
        mfClassicGetCardTypeByBlockCount(blocks.length));
  }

  for (var block in blocks) {
    tagData.add(hexToBytes(block));
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

CardSave flipperNfcToCardSave(String data) {
  final String id = const Uuid().v4();
  final String uid =
      RegExp(r'UID:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;
  final int sak = hexToBytes(
      RegExp(r'SAK:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!)[0];
  String atqaString =
      RegExp(r'ATQA:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;
  final List<int> atqa = [
    int.parse(atqaString.substring(0, 2), radix: 16),
    int.parse(atqaString.substring(2), radix: 16)
  ];
  final List<int> ats = [];
  final String name = uid;
  const Color color = Colors.deepOrange;
  final TagType tag;
  List<Uint8List> tagData = [];
  List<String> blocks = [];
  for (var block in data.split("\n")) {
    if (block.startsWith("Block")) {
      blocks.add(block.split(":")[1].trim().replaceAll(' ', '').toUpperCase());
    }
  }

  //Check if a block has more than 16 Bytes, Ultralight, return as unknown
  if (blocks[0].replaceAll(' ', '').length > 32) {
    tag = TagType.unknown;
  } else {
    tag = mfClassicGetChameleonTagType(
        mfClassicGetCardTypeByBlockCount(blocks.length));
  }

  if (!isMifareClassic(tag) && blocks.any((block) => block.contains('?'))) {
    throw const FormatException(
      'Masked non-Classic blocks cannot be represented losslessly; retain the original source file.',
    );
  }

  for (var block in blocks) {
    tagData.add(block.contains('?') ? Uint8List(0) : hexToBytes(block));
  }

  final card = CardSave(
      id: id,
      uid: uid,
      sak: sak,
      name: name,
      tag: tag,
      data: tagData,
      color: color,
      ats: Uint8List.fromList(ats),
      atqa: Uint8List.fromList(atqa));
  if (blocks.length == 72 && tag == TagType.mifare1K) {
    if (blocks.any((block) => block.contains('?'))) {
      throw const FormatException(
        'Partial EV1 composite coverage cannot be represented by common profile v1; retain the original source file.',
      );
    }
    return card;
  }
  if (isMifareClassic(tag)) {
    final p = legacySl1(card).json;
    p['classic']['provenance'] = 'imported';
    for (var i = 0; i < blocks.length; i++) {
      p['classic']['blocks'][i] = {
        'data': blocks[i],
        'status': 'imported',
        'key': null,
        'errors': [],
      };
    }
    card.sl1Profile = Sl1Profile.fromJson(p);
  }
  return card;
}

CardSave mctToCardSave(String data) {
  final String id = const Uuid().v4();
  final String uid = data.split("\n")[1].substring(0, 8);
  final int sak = hexToBytes(data.split("\n")[1].substring(10, 12))[0];
  String atqaString = data.split("\n")[1].substring(12, 16);
  final List<int> atqa = [
    int.parse(atqaString.substring(2), radix: 16),
    int.parse(atqaString.substring(0, 2), radix: 16)
  ];
  final List<int> ats = [];
  final String name = uid;
  const Color color = Colors.deepOrange;
  final TagType tag;
  List<Uint8List> tagData = [];
  List<String> blocks = [];
  for (var block in data.split("\n")) {
    if (!block.startsWith("+Sector")) {
      blocks.add(block.trim());
    }
  }

  //Check if a block has more than 16 Bytes, Ultralight, return as unknown
  if (blocks[0].replaceAll(' ', '').length > 32) {
    tag = TagType.unknown;
  } else {
    tag = mfClassicGetChameleonTagType(
        mfClassicGetCardTypeByBlockCount(blocks.length));
  }

  for (var block in blocks) {
    tagData.add(hexToBytes(block));
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

CardSave flipperRfidToCardSave(String data) {
  final String id = const Uuid().v4();
  final String type = RegExp(r'Key type:\s+(.*)').firstMatch(data)!.group(1)!;
  const Color color = Colors.deepOrange;

  final TagType tag;
  String uid = RegExp(r'Data:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;

  switch (type) {
    case 'EM4100':
      tag = TagType.em410X64;
      break;
    case 'EM4100/32':
      tag = TagType.em410X32;
      break;
    case 'EM4100/16':
      tag = TagType.em410X16;
      break;
    case 'H10301':
      tag = TagType.hidProx;
      uid = HIDCard(
              hidType: 1,
              facilityCode: hexToBytes(uid)[0],
              uid: Uint8List.fromList(
                  [0, 0, 0, ...hexToBytes(uid).sublist(1, 3)]),
              issueLevel: 0,
              oem: 0)
          .toString();
      break;
    default:
      tag = TagType.unknown;
  }

  return CardSave(id: id, uid: uid, name: uid, tag: tag, color: color);
}
