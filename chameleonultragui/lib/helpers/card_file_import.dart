import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/sharedprefsprovider.dart';

import 'card_save_converters.dart';
import 'sl1_card_save.dart';
import 'sl1_profile.dart';

/// Structured files must never be reinterpreted as raw memory after a parse
/// failure, even when their byte length happens to match a Classic image.
bool isStructuredCardFile(Uint8List bytes, {String? filename}) {
  // A declared JSON file must fail closed even when its UTF-8 is malformed.
  if (filename?.toLowerCase().endsWith('.json') ?? false) {
    return true;
  }
  final candidate = utf8.decode(bytes, allowMalformed: true).trimLeft();
  final objectMember = RegExp(r'^\{\s*"(?:\\.|[^"\\])*"\s*:');
  if (objectMember.hasMatch(candidate)) {
    // Inspect complete string tokens in a bounded opening object, so member
    // order/escaping cannot turn malformed supported text into raw memory.
    final opening = candidate.substring(0, candidate.length.clamp(0, 65536));
    final strings = RegExp(r'"(?:\\.|[^"\\])*"');
    for (final token in strings.allMatches(opening)) {
      if (!opening.substring(token.end).trimLeft().startsWith(':')) continue;
      try {
        if (const {
          'id',
          'uid',
          'Card',
          'blocks',
          'Created',
          'format',
        }.contains(jsonDecode(token.group(0)!))) {
          return true;
        }
      } on FormatException {
        // Recognizable object grammar with an invalid member escape is text.
        return true;
      }
    }
  }
  if (RegExp(r'^\+Sector:\s*\d+').hasMatch(candidate) ||
      (candidate.startsWith('#') && candidate.contains('+Sector: 0'))) {
    return true;
  }

  if ((objectMember.hasMatch(candidate) &&
          candidate.contains('chameleon-sl1-profile')) ||
      candidate.startsWith('Filetype: Flipper')) {
    return true;
  }
  final String text;
  try {
    text = utf8.decode(bytes).trimLeft();
  } on FormatException {
    return false;
  }
  // Raw card UIDs can begin with JSON punctuation (or whitespace). Require
  // actual text grammar; a single leading byte is never enough evidence.
  if (text.codeUnits.any((c) => c < 32 && ![9, 10, 13].contains(c))) {
    return false;
  }
  if (text.contains('+Sector: 0')) return true;
  try {
    final value = jsonDecode(text);
    if (value is Map || value is List) return true;
  } on FormatException {
    // A truncated object with a quoted member is still recognizable JSON.
  }
  return RegExp(r'^\s*(?:\{\s*"(?:\\.|[^"\\])*"\s*:|\[\s*(?:\{|"))')
      .hasMatch(text);
}

/// Shared by the actual file-picker route and device-free import regressions.
CardSave importCardText(String source, {required String filename}) {
  dynamic decoded;
  bool decodedJson = false;
  try {
    decoded = jsonDecode(source);
    decodedJson = true;
  } catch (_) {
    /* Text converters below. */
  }
  if ((decoded is Map && decoded['format'] == 'chameleon-sl1-profile') ||
      (!decodedJson && source.contains('chameleon-sl1-profile'))) {
    return sl1ToCard(Sl1Profile.parse(source));
  }
  final CardSave card;
  if (source.contains('"Created": "proxmark3",')) {
    card = pm3JsonToCardSave(source);
  } else if (source.contains('Filetype: Flipper NFC device')) {
    card = flipperNfcToCardSave(source);
  } else if (source.contains('+Sector: 0')) {
    card = mctToCardSave(source);
  } else if (source.contains('Filetype: Flipper RFID key')) {
    card = flipperRfidToCardSave(source);
  } else {
    card = CardSave.fromJson(source);
  }
  card.name = filename.contains('.') ? filename.split('.')[0] : filename;
  return card;
}
