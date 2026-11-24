#include "light_capture_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <mfapi.h>

#include <variant>

namespace light_capture {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* GetArgument(const flutter::MethodCall<EncodableValue>& call,
                                  const char* key) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (args == nullptr) return nullptr;
  auto it = args->find(EncodableValue(key));
  return it == args->end() ? nullptr : &it->second;
}

}  // namespace

// static
void LightCapturePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<LightCapturePlugin>(registrar));
}

LightCapturePlugin::LightCapturePlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      wakeup_message_(RegisterWindowMessage(L"LightCapturePluginWakeup")) {
  mf_started_ = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));

  const auto& codec = flutter::StandardMethodCodec::GetInstance();
  method_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "light_capture", &codec);
  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  event_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "light_capture/frames", &codec);
  event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* /*arguments*/,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            event_sink_ = std::move(events);
            return nullptr;
          },
          [this](const EncodableValue* /*arguments*/)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            event_sink_.reset();
            return nullptr;
          }));

  window_proc_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

LightCapturePlugin::~LightCapturePlugin() {
  session_.reset();  // Joins the capture thread.
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  method_channel_->SetMethodCallHandler(nullptr);
  event_channel_->SetStreamHandler(nullptr);
  if (mf_started_) MFShutdown();
}

void LightCapturePlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "listCameras") {
    EncodableList list;
    if (mf_started_) {
      for (const CameraInfo& camera : ListCameras()) {
        list.push_back(EncodableValue(EncodableMap{
            {EncodableValue("id"), EncodableValue(camera.id)},
            {EncodableValue("name"), EncodableValue(camera.name)},
        }));
      }
    }
    result->Success(EncodableValue(list));
    return;
  }

  if (method == "start") {
    const EncodableValue* id_value = GetArgument(call, "id");
    const auto* id = id_value ? std::get_if<std::string>(id_value) : nullptr;
    if (id == nullptr || id->empty()) {
      result->Error("bad_args", "Missing camera id");
      return;
    }
    if (!mf_started_) {
      result->Error("camera_error", "Media Foundation is not available");
      return;
    }
    if (flutter::FlutterView* view = registrar_->GetView()) {
      target_window_ = GetAncestor(view->GetNativeWindow(), GA_ROOT);
    }
    session_.reset();
    auto session =
        std::make_unique<CaptureSession>([this] { NotifyPlatformThread(); });
    const EncodableValue* color_value = GetArgument(call, "color");
    const auto* color = color_value ? std::get_if<bool>(color_value) : nullptr;
    const EncodableValue* width_value = GetArgument(call, "width");
    const auto* req_width =
        width_value ? std::get_if<int32_t>(width_value) : nullptr;
    const std::string error = session->Start(
        *id, color != nullptr && *color, req_width ? *req_width : 160);
    if (!error.empty()) {
      result->Error("camera_error", error);
      return;
    }
    const int width = session->thumbnail_width();
    const int height = session->thumbnail_height();
    const int channels = session->channels();
    session_ = std::move(session);
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("width"), EncodableValue(width)},
        {EncodableValue("height"), EncodableValue(height)},
        {EncodableValue("channels"), EncodableValue(channels)},
    }));
    return;
  }

  if (method == "stop") {
    session_.reset();
    result->Success();
    return;
  }

  if (method == "setAutoExposure") {
    const EncodableValue* enabled_value = GetArgument(call, "enabled");
    const auto* enabled =
        enabled_value ? std::get_if<bool>(enabled_value) : nullptr;
    if (enabled == nullptr) {
      result->Error("bad_args", "Missing 'enabled'");
      return;
    }
    const bool ok = session_ ? session_->SetAutoExposure(*enabled) : false;
    result->Success(EncodableValue(ok));
    return;
  }

  result->NotImplemented();
}

void LightCapturePlugin::NotifyPlatformThread() {
  // Called on the capture thread; only one wake-up message is queued at a time.
  if (wakeup_pending_.exchange(true)) return;
  HWND window = target_window_;
  if (window == nullptr || !PostMessage(window, wakeup_message_, 0, 0)) {
    wakeup_pending_ = false;
  }
}

std::optional<LRESULT> LightCapturePlugin::HandleWindowProc(
    HWND /*hwnd*/, UINT message, WPARAM /*wparam*/, LPARAM /*lparam*/) {
  if (message != wakeup_message_) return std::nullopt;
  wakeup_pending_ = false;
  DeliverPending();
  return 0;
}

void LightCapturePlugin::DeliverPending() {
  if (!session_) return;
  std::string error;
  if (session_->TakeError(&error) && event_sink_) {
    event_sink_->Error("camera_error", error);
  }
  std::vector<uint8_t> pixels;
  int width = 0, height = 0;
  if (session_->TakeFrame(&pixels, &width, &height) && event_sink_) {
    event_sink_->Success(EncodableValue(EncodableMap{
        {EncodableValue("width"), EncodableValue(width)},
        {EncodableValue("height"), EncodableValue(height)},
        {EncodableValue("channels"), EncodableValue(session_->channels())},
        {EncodableValue("pixels"), EncodableValue(std::move(pixels))},
    }));
  }
}

}  // namespace light_capture
