import 'dart:typed_data';
import 'dart:convert';

/// Reject duplicate names before any profile/native/folder container is decoded.
/// The existing JSON decoder remains the sole JSON grammar parser.
dynamic decodeProfileContainerJson(String text) {
  // jsonDecode otherwise silently keeps the last occurrence of a field.
  final objects = <Set<String>?>[];
  final expectingKey = <bool>[];
  final tokens = RegExp(r'"(?:\\.|[^"\\])*"|[{}\[\],:]');
  for (final token in tokens.allMatches(text)) {
    final value = token.group(0)!;
    if (value == '{' || value == '[') {
      objects.add(value == '{' ? <String>{} : null);
      expectingKey.add(value == '{');
    } else if (value == '}' || value == ']') {
      if (objects.isNotEmpty) {
        objects.removeLast();
        expectingKey.removeLast();
      }
    } else if (value == ',' && objects.isNotEmpty) {
      expectingKey[expectingKey.length - 1] = objects.last != null;
    } else if (value.startsWith('"') &&
        objects.isNotEmpty &&
        objects.last != null &&
        expectingKey.last) {
      final key = jsonDecode(value) as String;
      if (!objects.last!.add(key)) {
        throw const FormatException('Duplicate JSON field');
      }
      expectingKey[expectingKey.length - 1] = false;
    }
  }
  return jsonDecode(text);
}

void requireProfileFields(dynamic value, List<String> names) {
  if (value is! Map ||
      value.length != names.length ||
      names.any((key) => !value.containsKey(key))) {
    throw const FormatException('Unexpected or missing profile fields');
  }
}

void requireProfileHex(dynamic value, int bytes, {bool unknown = false}) {
  if (value is! String ||
      value.length != bytes * 2 ||
      !RegExp(unknown ? r'^(?:[0-9A-F]{2}|\?\?)*$' : r'^(?:[0-9A-F]{2})*$')
          .hasMatch(value)) {
    throw const FormatException('Invalid uppercase hex or byte coverage');
  }
}

Uint8List decodeProfileHex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);
String encodeProfileHex(Iterable<int> value) =>
    value.map((v) => v.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
