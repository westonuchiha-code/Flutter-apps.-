#ifndef FLUTTER_PLUGIN_LIGHT_CAPTURE_PLUGIN_H_
#define FLUTTER_PLUGIN_LIGHT_CAPTURE_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>

#include <atomic>
#include <memory>
#include <optional>
#include <string>

#include "capture_session.h"

namespace light_capture {

// Exposes webcam brightness frames to Dart.
//
// Method channel "light_capture":
//   listCameras -> [{id, name}]
//   start {id}  -> {width, height}
//   stop
//   setAutoExposure {enabled} -> bool (whether the camera accepted it)
// Event channel "light_capture/frames":
//   {width, height, pixels: Uint8List}  (8-bit luminance thumbnail)
class LightCapturePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit LightCapturePlugin(flutter::PluginRegistrarWindows* registrar);
  ~LightCapturePlugin() override;

  LightCapturePlugin(const LightCapturePlugin&) = delete;
  LightCapturePlugin& operator=(const LightCapturePlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Runs on the platform thread when the capture thread has news.
  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);
  void NotifyPlatformThread();
  void DeliverPending();

  flutter::PluginRegistrarWindows* registrar_;
  int window_proc_id_ = -1;
  UINT wakeup_message_;
  bool mf_started_ = false;
  HWND target_window_ = nullptr;
  std::atomic<bool> wakeup_pending_{false};

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::unique_ptr<CaptureSession> session_;
};

}  // namespace light_capture

#endif  // FLUTTER_PLUGIN_LIGHT_CAPTURE_PLUGIN_H_
