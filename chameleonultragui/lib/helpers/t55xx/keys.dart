import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';

/// Optional trailing byte on the firmware's T55xx write commands. Firmware that reports
/// [t55xxWriteFeaturePasswordOptIn] writes no password when the byte is absent.
const int t55xxWriteFlagNoPassword = 0x01;
const int t55xxWriteFlagSetPassword = 0x02;

/// Bit returned by the T55xx write features command: password mode is opt-in and the
/// flags byte above is understood.
const int t55xxWriteFeaturePasswordOptIn = 1 << 0;

/// Password written by firmware that predates opt-in passwords, and the default the app
/// tries when rewriting a tag.
const String t55xxDefaultPassword = "20206666";

/// Key sent with no password on opt-in firmware: block 7 is always written, so this leaves
/// it blank, as on a new tag, rather than showing a password that isn't in use.
const String t55xxNoPasswordKey = "00000000";

/// Old keys to try before a T55xx write. On opt-in firmware the default password is always
/// tried, so tags locked by earlier firmware stay rewritable without the user typing it.
/// Older firmware gets the keys as the write form has always sent them.
List<Uint8List> t55xxOldKeys(String currentKey, {required bool passwordOptIn}) =>
    passwordOptIn
        ? [
            if (currentKey.isNotEmpty) hexToBytes(currentKey),
            hexToBytes(t55xxDefaultPassword),
            Uint8List(4),
          ]
        : [hexToBytes(currentKey), Uint8List(4)];

/// The part of a T55xx write request that follows the card data: the new key, the old
/// keys to try, then the flags byte when [setPassword] is given.
///
/// Leave [setPassword] null for firmware without the flags byte: it always turns password
/// mode on with [newKey].
Uint8List buildT55xxKeyTail(
  Uint8List newKey,
  List<Uint8List> oldKeys, {
  bool? setPassword,
}) {
  return Uint8List.fromList([
    ...newKey,
    for (final key in oldKeys) ...key,
    if (setPassword != null)
      setPassword ? t55xxWriteFlagSetPassword : t55xxWriteFlagNoPassword,
  ]);
}
