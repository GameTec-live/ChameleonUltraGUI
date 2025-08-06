import 'package:flutter/material.dart';

const _themeColors = [
  Colors.deepOrange,
  Colors.deepPurple,
  Colors.blue,
  Colors.green,
  Colors.indigo,
  Colors.lime,
  Colors.red,
  Colors.yellow
];

const _themeComplementaryColors = [
  [
    Color.fromARGB(16, 202, 43, 43),
    Color.fromARGB(30, 116, 58, 183),
    Color.fromARGB(44, 62, 216, 243),
    Color.fromARGB(50, 175, 76, 172),
    Color.fromARGB(46, 130, 51, 196),
    Color.fromARGB(48, 110, 116, 29),
    Color.fromARGB(47, 188, 43, 201),
    Color.fromARGB(44, 58, 104, 202),
  ],
  [
    Color.fromARGB(255, 255, 236, 236),
    Color.fromARGB(255, 238, 227, 252),
    Color.fromARGB(255, 234, 252, 255),
    Color.fromARGB(255, 238, 255, 248),
    Color.fromARGB(248, 248, 239, 255),
    Color.fromARGB(255, 255, 255, 240),
    Color.fromARGB(255, 253, 238, 238),
    Color.fromARGB(255, 248, 252, 216),
  ]
];

int clampTheme(int theme) {
  if (theme < 0 || theme >= _themeColors.length) {
    theme = 0;
  }
  return theme;
}

MaterialColor getThemeColor(int theme) {
  return _themeColors[clampTheme(theme)];
}

Color getThemeComplementary(int themeMode, int theme) {
  if (themeMode != 1) {
    themeMode = 0;
  }
  return _themeComplementaryColors[themeMode][clampTheme(theme)];
}
