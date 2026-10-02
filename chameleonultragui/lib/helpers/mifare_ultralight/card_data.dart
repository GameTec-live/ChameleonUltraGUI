import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

Uint8List mfUltralightGetRestorePageData(CardSave card, int page) {
  final passwordPage = mfUltralightGetPasswordPage(card.tag);
  if (passwordPage != 0 &&
      page == passwordPage &&
      card.extraData.ultralightPassword.length == 4) {
    return Uint8List.fromList(card.extraData.ultralightPassword);
  }

  return Uint8List.fromList(card.data[page]);
}

Uint8List mfUltralightPasswordAfterDumpEdit(
    CardSave card, List<Uint8List> updatedData) {
  final savedPassword = card.extraData.ultralightPassword;
  if (savedPassword.length != 4) {
    return Uint8List.fromList(savedPassword);
  }

  final passwordPage = mfUltralightGetPasswordPage(card.tag);
  if (passwordPage == 0 ||
      passwordPage >= card.data.length ||
      passwordPage >= updatedData.length) {
    return Uint8List.fromList(savedPassword);
  }

  if (!_bytesEqual(card.data[passwordPage], updatedData[passwordPage])) {
    return Uint8List.fromList(updatedData[passwordPage]);
  }

  return Uint8List.fromList(savedPassword);
}

Uint8List mfUltralightPasswordAfterTypeChange(
    CardSave card, TagType selectedType) {
  if (selectedType == card.tag) {
    return Uint8List.fromList(card.extraData.ultralightPassword);
  }

  final oldPasswordPage = mfUltralightGetPasswordPage(card.tag);
  final newPasswordPage = mfUltralightGetPasswordPage(selectedType);

  if (oldPasswordPage != 0 &&
      oldPasswordPage == newPasswordPage) {
    return Uint8List.fromList(card.extraData.ultralightPassword);
  }

  return Uint8List(0);
}
