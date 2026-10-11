import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum UiMode { mobile, desktop }

/// Phones have a shortest display side below this (logical pixels); tablets
/// and iPads are at or above it and keep the desktop layout.
const double phoneShortestSideLimit = 600;

/// Decides which interface to show.
///
/// Only Android and iOS devices with a phone sized display get the mobile UI.
/// The decision is based on the physical display, not the window, so resizing
/// a desktop window (or a tablet's split screen) never switches interfaces and
/// rotating a phone never switches to the tablet layout.
UiMode selectUiMode({
  required TargetPlatform platform,
  required Size displaySize,
  bool isWeb = false,
}) {
  if (isWeb) {
    return UiMode.desktop;
  }

  final isMobilePlatform =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  if (isMobilePlatform && displaySize.shortestSide < phoneShortestSideLimit) {
    return UiMode.mobile;
  }

  return UiMode.desktop;
}

/// Overrides [resolveUiMode] in tests.
@visibleForTesting
UiMode? debugUiModeOverride;

/// The interface to use for the current device.
UiMode resolveUiMode(BuildContext context) {
  final override = debugUiModeOverride;
  if (override != null) {
    return override;
  }

  final display = View.of(context).display;
  return selectUiMode(
    platform: defaultTargetPlatform,
    displaySize: display.size / display.devicePixelRatio,
    isWeb: kIsWeb,
  );
}
