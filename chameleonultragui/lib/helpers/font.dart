/* 
Copyright 2023 DING MINGZHE, https://github.com/LastMonopoly/chinese_font_library

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

class DynamicFont {
  final String fontFamily;
  final String uri;

  DynamicFont.file({required this.fontFamily, required String filepath})
      : uri = filepath;

  Future<bool> load() async {
    if (!await File(uri).exists()) return false;
    try {
      await loadFontFromList(
        await File(uri).readAsBytes(),
        fontFamily: fontFamily,
      );
      return true;
    } catch (e) {
      return false;
    }
  }
}

class SystemChineseFont {
  const SystemChineseFont._();

  /// Chinese font family fallback, for iOS & macOS
  static const List<String> appleFontFamily = [
    // '.SF UI Text',
    '.AppleSystemUIFont',
    'PingFang SC',
  ];

  /// Chinese font family fallback, for xiaomi & redmi phone
  static const List<String> xiaomiFontFamily = [
    'miui',
    'mipro',
  ];

  /// Chinese font family fallback, for windows
  static const List<String> windowsFontFamily = [
    'Microsoft YaHei',
  ];

  static const systemFont = "system-font";

  static bool systemFontLoaded = false;

  /// Chinese font family fallback, for VIVO Origin OS 1.0
  static final vivoSystemFont = DynamicFont.file(
    fontFamily: systemFont,
    filepath: '/system/fonts/DroidSansFallbackMonster.ttf',
  );

  /// Chinese font family fallback, for honor Magic UI 4.0
  static final honorSystemFont = DynamicFont.file(
    fontFamily: systemFont,
    filepath: '/system/fonts/DroidSansChinese.ttf',
  );

  /// Chinese font family fallback, for most platforms
  static List<String> get fontFamilyFallback {
    if (!systemFontLoaded) {
      // honorSystemFont.load();
      () async {
        final vivoFont = File("/system/fonts/VivoFont.ttf");
        if ((await vivoFont.exists()) &&
            (await vivoFont.resolveSymbolicLinks())
                .contains("DroidSansFallbackBBK")) {
          await vivoSystemFont.load();
        }
      }();
      systemFontLoaded = true;
    }

    return [
      systemFont,
      "sans-serif",
      ...appleFontFamily,
      ...xiaomiFontFamily,
      ...windowsFontFamily,
    ];
  }

  /// Text style with updated fontFamilyFallback & fontVariations
  static TextStyle get textStyle {
    return const TextStyle().useCustomSystemFont();
  }

  /// Text theme with updated fontFamilyFallback & fontVariations
  static TextTheme textTheme(Brightness brightness) {
    switch (brightness) {
      case Brightness.dark:
        return Typography.material2021()
            .white
            .apply(fontFamilyFallback: fontFamilyFallback);
      case Brightness.light:
        return Typography.material2021()
            .black
            .apply(fontFamilyFallback: fontFamilyFallback);
    }
  }
}

extension TextStyleUseCustomSystemFont on TextStyle {
  /// Add fontFamilyFallback & fontVariation to original font style
  TextStyle useCustomSystemFont() {
    return copyWith(
      fontFamilyFallback: [
        ...?fontFamilyFallback,
        ...SystemChineseFont.fontFamilyFallback,
      ],
      fontVariations: [
        ...?fontVariations,
        if (fontWeight != null)
          FontVariation('wght', (fontWeight!.index + 1) * 100),
      ],
    );
  }
}

extension TextThemeUseCustomSystemFont on TextTheme {
  /// Add fontFamilyFallback & fontVariation to original text theme
  TextTheme useCustomSystemFont(Brightness brightness) {
    return SystemChineseFont.textTheme(brightness).merge(this);
  }
}

extension ThemeDataUseCustomSystemFont on ThemeData {
  /// Add fontFamilyFallback & fontVariation to original theme data
  ThemeData useCustomSystemFont(Brightness brightness) {
    return copyWith(textTheme: textTheme.useCustomSystemFont(brightness));
  }
}
