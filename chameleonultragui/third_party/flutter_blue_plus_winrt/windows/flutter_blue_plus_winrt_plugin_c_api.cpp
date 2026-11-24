#include "include/flutter_blue_plus_winrt/flutter_blue_plus_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_blue_plus_winrt_plugin.h"

void FlutterBluePlusPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_blue_plus_winrt::FlutterBluePlusWinrtPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
