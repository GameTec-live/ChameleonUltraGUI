import 'package:chameleonultragui/gui/mobile/platform_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only phone sized Android/iOS displays use the mobile UI', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final phone in [const Size(360, 800), const Size(932, 430)]) {
        expect(
          selectUiMode(platform: platform, displaySize: phone),
          UiMode.mobile,
        );
      }
      // Tablets and iPads keep the existing UI.
      expect(
        selectUiMode(platform: platform, displaySize: const Size(800, 1280)),
        UiMode.desktop,
      );
      expect(
        selectUiMode(platform: platform, displaySize: const Size(600, 960)),
        UiMode.desktop,
      );
    }
  });

  test('desktop platforms and web never use the mobile UI', () {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    ]) {
      for (final size in [const Size(320, 480), const Size(1920, 1080)]) {
        expect(
          selectUiMode(platform: platform, displaySize: size),
          UiMode.desktop,
        );
      }
    }

    expect(
      selectUiMode(
        platform: TargetPlatform.android,
        displaySize: const Size(360, 800),
        isWeb: true,
      ),
      UiMode.desktop,
    );
  });
}
