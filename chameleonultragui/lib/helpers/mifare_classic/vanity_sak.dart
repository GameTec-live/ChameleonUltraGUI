import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';

bool mfClassicVanitySakVisibleInEdit(TagType type, List<Uint8List> data) =>
    isMifareClassic(type) && data.isNotEmpty && data[0].isNotEmpty;

bool mfClassicVanitySakVisibleInWrite(TagType type, List<Uint8List> data) =>
    isMifareClassic(type) && (data.isEmpty || data[0].isEmpty);

bool? mfClassicVanitySakFromUidHex(String uidHex) {
  final text = uidHex.replaceAll(' ', '');
  if (text.length != 8 && text.length != 14) {
    return null;
  }
  return text.length == 14;
}

bool? mfClassicVanitySakFromData(
    {required Uint8List uid, required int sak, required Uint8List block0}) {
  if (block0.length != 16 || (uid.length != 4 && uid.length != 7)) {
    return null;
  }
  // SAK sits at byte 5 for 4-byte UIDs, byte 7 for 7-byte UIDs.
  final sakIdx = uid.length == 4 ? 5 : 7;
  final stored = block0[sakIdx];
  if (stored == (sak | 0x80)) return true;
  if (stored == sak) return false;
  return null;
}
