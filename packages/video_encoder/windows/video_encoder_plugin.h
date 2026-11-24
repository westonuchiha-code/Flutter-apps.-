#ifndef FLUTTER_PLUGIN_VIDEO_ENCODER_PLUGIN_H_
#define FLUTTER_PLUGIN_VIDEO_ENCODER_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "mp4_session.h"

namespace video_encoder {

// Method channel "video_encoder":
//   start {path, width, height, fps, bitrate, sampleRate, channels, audio}
//   frame {data: I420 bytes, index}
//   audio {data: 16-bit interleaved PCM, offset: sample frames so far}
//   finish / cancel
class VideoEncoderPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit VideoEncoderPlugin(flutter::PluginRegistrarWindows* registrar);
  ~VideoEncoderPlugin() override;

  VideoEncoderPlugin(const VideoEncoderPlugin&) = delete;
  VideoEncoderPlugin& operator=(const VideoEncoderPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool mf_started_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<Mp4Session> session_;
};

}  // namespace video_encoder

#endif  // FLUTTER_PLUGIN_VIDEO_ENCODER_PLUGIN_H_
