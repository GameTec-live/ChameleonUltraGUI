import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

const int maxNameLength = 19;

String? validateName(String? value, AppLocalizations l) {
  if (value == null || value.isEmpty) {
    return l.please_enter_name;
  }

  if (value.length > maxNameLength) {
    return l.too_long_name;
  }

  return null;
}

String? validateUid(
  String? value,
  AppLocalizations l,
  TagType tagType, {
  bool isCreate = false,
}) {
  if (value == null || value.isEmpty) {
    return l.please_enter_something(l.uid);
  }

  String cleanValue = value.replaceAll(" ", "");

  if (chameleonTagToFrequency(tagType) == TagFrequency.hf) {
    if (isCreate && isMifareUltralight(tagType)) {
      if (cleanValue.length != 14) {
        return l.must_be(7, l.uid);
      }
    } else if (isCreate) {
      if (cleanValue.length != 8 && cleanValue.length != 14) {
        return l.must_or("4", "7", l.uid);
      }
    } else {
      if (!(cleanValue.length == 8 ||
          cleanValue.length == 14 ||
          cleanValue.length == 20)) {
        return l.must_or("4, 7", "10", l.uid);
      }
    }
  } else if (chameleonTagToFrequency(tagType) == TagFrequency.lf) {
    if (cleanValue.length != uidSizeForLfTag(tagType) * 2) {
      return l.must_be(uidSizeForLfTag(tagType), l.uid);
    }
  }

  return null;
}

String? validateHex(
  String? value,
  AppLocalizations l, {
  int? exactBytes,
  String? fieldName,
  bool required = false,
}) {
  if (value == null || value.isEmpty) {
    if (required) {
      return l.please_enter_something(fieldName ?? '');
    }
    return null;
  }

  String cleanValue = value.replaceAll(" ", "");

  if (cleanValue.isNotEmpty && !isValidHexString(cleanValue)) {
    return l.must_be_valid_hex;
  }

  if (cleanValue.length % 2 != 0) {
    return l.must_be_valid_hex;
  }

  if (exactBytes != null && cleanValue.isNotEmpty) {
    if (cleanValue.length != exactBytes * 2) {
      return l.must_be(exactBytes, fieldName ?? '');
    }
  }

  return null;
}

final _numberFormat = NumberFormat.decimalPattern('en');

String? validateIntRange(
  String? value,
  AppLocalizations l, {
  required int min,
  required int max,
  bool required = true,
  String? emptyMessage,
}) {
  if (value == null || value.isEmpty) {
    if (required) {
      return emptyMessage ??
          l.must_be_between(
              _numberFormat.format(min), _numberFormat.format(max));
    }
    return null;
  }

  int? parsed = int.tryParse(value);
  if (parsed == null || parsed < min || parsed > max) {
    return l.must_be_between(
        _numberFormat.format(min), _numberFormat.format(max));
  }

  return null;
}

String? validateBlePin(String? value, AppLocalizations l) {
  if (value == null ||
      value.isEmpty ||
      value.length != 6 ||
      double.tryParse(value) == null) {
    return l.pin_must_be_6_digits;
  }
  return null;
}

List<FilteringTextInputFormatter> hexFormatter = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f: ]'))
];
