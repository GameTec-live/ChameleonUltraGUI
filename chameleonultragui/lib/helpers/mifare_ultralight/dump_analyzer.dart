class MifareUltralightDumpAnalyzer {
  static String hexToAscii(String hex) {
    if (hex.length % 2 != 0) {
      return 'Invalid hex string';
    }

    StringBuffer ascii = StringBuffer();

    for (int i = 0; i < hex.length; i += 2) {
      try {
        int byte = int.parse(hex.substring(i, i + 2), radix: 16);

        if (byte >= 32 && byte <= 126) {
          ascii.write(String.fromCharCode(byte));
        } else {
          ascii.write('.');
        }
      } catch (e) {
        ascii.write('?');
      }
    }

    return ascii.toString();
  }

  static List<String> hexBlocksToAscii(List<String> hexBlocks) {
    return hexBlocks.map((block) => hexToAscii(block)).toList();
  }

  static bool isValidHex(String text) {
    return RegExp(r'^[0-9A-Fa-f-]*\$').hasMatch(text);
  }

  static bool isValidBlock(String text) {
    return RegExp(r'^[0-9A-Fa-f-]{8}\$').hasMatch(text.trim());
  }
}
