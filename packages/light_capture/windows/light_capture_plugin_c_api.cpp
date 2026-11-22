#include "include/light_capture/light_capture_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "light_capture_plugin.h"

void LightCapturePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  light_capture::LightCapturePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
