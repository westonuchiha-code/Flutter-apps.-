#include "video_encoder_plugin.h"

#include <flutter/standard_method_codec.h>
#include <mfapi.h>

#include <string>
#include <variant>
#include <vector>

namespace video_encoder {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* Arg(const flutter::MethodCall<EncodableValue>& call,
                          const char* key) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (args == nullptr) return nullptr;
  auto it = args->find(EncodableValue(key));
  return it == args->end() ? nullptr : &it->second;
}

int64_t IntArg(const flutter::MethodCall<EncodableValue>& call, const char* key) {
  const auto* v = Arg(call, key);
  if (v == nullptr) return 0;
  if (const auto* i = std::get_if<int32_t>(v)) return *i;
  if (const auto* l = std::get_if<int64_t>(v)) return *l;
  return 0;
}

std::wstring Widen(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                    static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      out.data(), n);
  return out;
}

}  // namespace

// static
void VideoEncoderPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<VideoEncoderPlugin>(registrar));
}

VideoEncoderPlugin::VideoEncoderPlugin(flutter::PluginRegistrarWindows* registrar) {
  mf_started_ = SUCCEEDED(MFStartup(MF_VERSION));
  const auto& codec = flutter::StandardMethodCodec::GetInstance();
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "video_encoder", &codec);
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

VideoEncoderPlugin::~VideoEncoderPlugin() {
  channel_->SetMethodCallHandler(nullptr);
  session_.reset();
  if (mf_started_) MFShutdown();
}

void VideoEncoderPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  std::string error;
  if (method == "start") {
    if (!mf_started_) {
      result->Error("encoder", "Media Foundation is not available on this PC");
      return;
    }
    const auto* path = Arg(call, "path");
    const auto* audio = Arg(call, "audio");
    if (path == nullptr || !std::holds_alternative<std::string>(*path)) {
      result->Error("encoder", "Missing path");
      return;
    }
    session_ = std::make_unique<Mp4Session>();
    error = session_->Start(
        Widen(std::get<std::string>(*path)),
        static_cast<uint32_t>(IntArg(call, "width")),
        static_cast<uint32_t>(IntArg(call, "height")),
        static_cast<uint32_t>(IntArg(call, "fps")),
        static_cast<uint32_t>(IntArg(call, "bitrate")),
        static_cast<uint32_t>(IntArg(call, "sampleRate")),
        static_cast<uint32_t>(IntArg(call, "channels")),
        audio != nullptr && std::holds_alternative<bool>(*audio) && std::get<bool>(*audio));
    if (!error.empty()) session_.reset();
  } else if (method == "frame" || method == "audio") {
    const auto* data = Arg(call, "data");
    const auto* bytes = data == nullptr ? nullptr : std::get_if<std::vector<uint8_t>>(data);
    if (!session_) {
      error = "No video is being written";
    } else if (bytes == nullptr) {
      error = "Missing data";
    } else if (method == "frame") {
      error = session_->Frame(bytes->data(), bytes->size(), IntArg(call, "index"));
    } else {
      error = session_->Audio(bytes->data(), bytes->size(), IntArg(call, "offset"));
    }
  } else if (method == "finish") {
    error = session_ ? session_->Finish() : "No video is being written";
    session_.reset();
  } else if (method == "cancel") {
    session_.reset();
  } else {
    result->NotImplemented();
    return;
  }
  if (error.empty()) {
    result->Success();
  } else {
    result->Error("encoder", error);
  }
}

}  // namespace video_encoder
