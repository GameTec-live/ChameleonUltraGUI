import 'package:flutter/material.dart';
import 'package:chameleonultragui/main.dart';

ButtonStyle customCardButtonStyle(ChameleonGUIState appState) {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith<Color>(
      (Set<WidgetState> states) {
        return appState.sharedPreferencesProvider.getThemeComplementaryColor();
      },
    ),
    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
      ),
    ),
  );
}
