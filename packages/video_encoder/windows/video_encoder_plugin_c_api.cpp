#include "include/video_encoder/video_encoder_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "video_encoder_plugin.h"

void VideoEncoderPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  video_encoder::VideoEncoderPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
