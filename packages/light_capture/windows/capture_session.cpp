#include "capture_session.h"

// clang-format off
#include <windows.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <strmif.h>
#include <wrl/client.h>
// clang-format on

#include <chrono>
#include <cstdio>
#include <cstdlib>

#include "luma_downscale.h"

using Microsoft::WRL::ComPtr;

namespace light_capture {
namespace {

constexpr DWORD kVideoStream =
    static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);

std::string ToUtf8(const wchar_t* wide) {
  if (wide == nullptr) return {};
  const int len =
      WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (len <= 1) return {};
  std::string out(static_cast<size_t>(len) - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), len, nullptr, nullptr);
  return out;
}

std::wstring ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (len <= 1) return {};
  std::wstring out(static_cast<size_t>(len) - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), len);
  return out;
}

std::string HrMessage(const char* what, HRESULT hr) {
  char buffer[200];
  std::snprintf(buffer, sizeof(buffer), "%s (HRESULT 0x%08lX)", what,
                static_cast<unsigned long>(hr));
  return buffer;
}

std::string GetActivateString(IMFActivate* activate, REFGUID key) {
  WCHAR* value = nullptr;
  UINT32 length = 0;
  if (FAILED(activate->GetAllocatedString(key, &value, &length))) return {};
  std::string out = ToUtf8(value);
  CoTaskMemFree(value);
  return out;
}

HRESULT CreateDeviceSource(const std::wstring& symbolic_link,
                           IMFMediaSource** source) {
  ComPtr<IMFAttributes> attributes;
  HRESULT hr = MFCreateAttributes(&attributes, 2);
  if (SUCCEEDED(hr)) {
    hr = attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                             MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  }
  if (SUCCEEDED(hr)) {
    hr = attributes->SetString(
        MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
        symbolic_link.c_str());
  }
  if (SUCCEEDED(hr)) hr = MFCreateDeviceSource(attributes.Get(), source);
  return hr;
}

// Picks a native camera format around 640 px wide at >= 15 fps; a small frame
// is all we need and keeps CPU use low.
void SelectSmallNativeType(IMFSourceReader* reader) {
  ComPtr<IMFMediaType> best;
  unsigned long long best_score = ~0ull;
  for (DWORD i = 0;; ++i) {
    ComPtr<IMFMediaType> type;
    if (FAILED(reader->GetNativeMediaType(kVideoStream, i, &type))) break;
    UINT32 width = 0, height = 0;
    if (FAILED(MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &width,
                                  &height)) ||
        width == 0 || height == 0) {
      continue;
    }
    UINT32 num = 0, den = 0;
    MFGetAttributeRatio(type.Get(), MF_MT_FRAME_RATE, &num, &den);
    const double fps = den != 0 ? static_cast<double>(num) / den : 0.0;
    unsigned long long score =
        static_cast<unsigned long long>(std::abs(static_cast<int>(width) - 640)) *
        10;
    if (fps < 15.0) score += 100000;
    if (fps >= 15.0 && fps < 25.0) score += 1000;
    GUID subtype = GUID_NULL;
    type->GetGUID(MF_MT_SUBTYPE, &subtype);
    if (subtype == MFVideoFormat_MJPG) score += 50;  // Prefer uncompressed.
    if (score < best_score) {
      best_score = score;
      best = type;
    }
  }
  if (best) reader->SetCurrentMediaType(kVideoStream, nullptr, best.Get());
}

HRESULT SetOutputSubtype(IMFSourceReader* reader, const GUID& subtype) {
  ComPtr<IMFMediaType> type;
  HRESULT hr = MFCreateMediaType(&type);
  if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_SUBTYPE, subtype);
  if (SUCCEEDED(hr)) {
    hr = reader->SetCurrentMediaType(kVideoStream, nullptr, type.Get());
  }
  return hr;
}

struct FrameFormat {
  UINT32 width = 0;
  UINT32 height = 0;
  LONG stride = 0;
  PixelLayout layout = PixelLayout::kLuma8;
};

HRESULT ReadFrameFormat(IMFSourceReader* reader, FrameFormat* format) {
  ComPtr<IMFMediaType> type;
  HRESULT hr = reader->GetCurrentMediaType(kVideoStream, &type);
  if (FAILED(hr)) return hr;
  GUID subtype = GUID_NULL;
  hr = type->GetGUID(MF_MT_SUBTYPE, &subtype);
  if (FAILED(hr)) return hr;
  hr = MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &format->width,
                          &format->height);
  if (FAILED(hr)) return hr;

  LONG bytes_per_pixel = 1;
  if (subtype == MFVideoFormat_NV12 || subtype == MFVideoFormat_I420 ||
      subtype == MFVideoFormat_IYUV || subtype == MFVideoFormat_YV12) {
    format->layout = PixelLayout::kLuma8;
  } else if (subtype == MFVideoFormat_YUY2) {
    format->layout = PixelLayout::kYuyv;
    bytes_per_pixel = 2;
  } else if (subtype == MFVideoFormat_UYVY) {
    format->layout = PixelLayout::kUyvy;
    bytes_per_pixel = 2;
  } else if (subtype == MFVideoFormat_RGB32 ||
             subtype == MFVideoFormat_ARGB32) {
    format->layout = PixelLayout::kBgra32;
    bytes_per_pixel = 4;
  } else {
    return MF_E_INVALIDMEDIATYPE;
  }

  UINT32 stride = 0;
  if (SUCCEEDED(type->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride))) {
    format->stride = static_cast<LONG>(static_cast<INT32>(stride));
  } else {
    LONG computed = 0;
    if (SUCCEEDED(MFGetStrideForBitmapInfoHeader(subtype.Data1, format->width,
                                                 &computed))) {
      format->stride = computed;
    } else {
      format->stride = static_cast<LONG>(format->width) * bytes_per_pixel;
    }
  }
  return S_OK;
}

// Applies auto/manual mode to one IAMCameraControl / IAMVideoProcAmp property.
template <typename Control, typename Property>
bool SetAutoMode(Control* control, Property property, long auto_flag,
                 long manual_flag, bool enabled) {
  long lo = 0, hi = 0, step = 0, def = 0, caps = 0;
  if (FAILED(control->GetRange(property, &lo, &hi, &step, &def, &caps))) {
    return false;
  }
  if (enabled) {
    if ((caps & auto_flag) == 0) return false;
    return SUCCEEDED(control->Set(property, def, auto_flag));
  }
  if ((caps & manual_flag) == 0) return false;
  long value = def, flags = 0;
  control->Get(property, &value, &flags);  // Keep the current level.
  return SUCCEEDED(control->Set(property, value, manual_flag));
}

// Locks (or unlocks) exposure, plus gain where available, so the camera does
// not compensate for the light changes we want to measure.
bool ApplyAutoExposure(IMFMediaSource* source, bool enabled) {
  bool exposure_ok = false;
  ComPtr<IAMCameraControl> camera_control;
  if (SUCCEEDED(source->QueryInterface(IID_PPV_ARGS(&camera_control)))) {
    exposure_ok = SetAutoMode(camera_control.Get(), CameraControl_Exposure,
                              CameraControl_Flags_Auto,
                              CameraControl_Flags_Manual, enabled);
  }
  ComPtr<IAMVideoProcAmp> proc_amp;
  if (SUCCEEDED(source->QueryInterface(IID_PPV_ARGS(&proc_amp)))) {
    SetAutoMode(proc_amp.Get(), VideoProcAmp_Gain, VideoProcAmp_Flags_Auto,
                VideoProcAmp_Flags_Manual, enabled);
  }
  return exposure_ok;
}

}  // namespace

std::vector<CameraInfo> ListCameras() {
  std::vector<CameraInfo> cameras;
  ComPtr<IMFAttributes> attributes;
  if (FAILED(MFCreateAttributes(&attributes, 1)) ||
      FAILED(attributes->SetGUID(
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID))) {
    return cameras;
  }
  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  if (FAILED(MFEnumDeviceSources(attributes.Get(), &devices, &count))) {
    return cameras;
  }
  for (UINT32 i = 0; i < count; ++i) {
    CameraInfo info;
    info.id = GetActivateString(
        devices[i], MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK);
    info.name =
        GetActivateString(devices[i], MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME);
    if (info.name.empty()) info.name = "Camera " + std::to_string(i + 1);
    if (!info.id.empty()) cameras.push_back(std::move(info));
    devices[i]->Release();
  }
  CoTaskMemFree(devices);
  return cameras;
}

CaptureSession::CaptureSession(std::function<void()> on_update)
    : on_update_(std::move(on_update)) {}

CaptureSession::~CaptureSession() { Stop(); }

std::string CaptureSession::Start(const std::string& camera_id, bool color,
                                  int width) {
  Stop();
  stop_requested_ = false;
  color_ = color;
  requested_width_ = width < 16 ? 16
                     : (width > kMaxThumbnailWidth ? kMaxThumbnailWidth
                                                   : width);
  std::promise<std::string> opened;
  std::future<std::string> result = opened.get_future();
  thread_ = std::thread(&CaptureSession::Run, this, camera_id, &opened);
  std::string error = result.get();
  if (!error.empty() && thread_.joinable()) thread_.join();
  return error;
}

void CaptureSession::Stop() {
  stop_requested_ = true;
  if (thread_.joinable()) thread_.join();
}

bool CaptureSession::SetAutoExposure(bool enabled) {
  std::unique_lock<std::mutex> lock(mutex_);
  if (!running_) return false;
  exposure_request_ = enabled ? 1 : 0;
  exposure_result_ = -1;
  const bool finished = exposure_cv_.wait_for(
      lock, std::chrono::seconds(2),
      [this] { return exposure_result_ != -1 || !running_; });
  return finished && exposure_result_ == 1;
}

bool CaptureSession::TakeFrame(std::vector<uint8_t>* pixels, int* width,
                               int* height) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!frame_ready_) return false;
  frame_ready_ = false;
  pixels->swap(frame_);
  *width = thumb_width_;
  *height = thumb_height_;
  return true;
}

bool CaptureSession::TakeError(std::string* error) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!error_ready_) return false;
  error_ready_ = false;
  *error = error_;
  return true;
}

void CaptureSession::Run(std::string camera_id,
                         std::promise<std::string>* opened) {
  const HRESULT co_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    ComPtr<IMFMediaSource> source;
    ComPtr<IMFSourceReader> reader;
    FrameFormat format;

    // --- Open the camera. `opened` must not be used after set_value(). ---
    std::string open_error;
    HRESULT hr = CreateDeviceSource(ToWide(camera_id), &source);
    if (FAILED(hr)) {
      open_error = HrMessage(
          "Could not open the camera. Check that no other app is using it and "
          "that camera access for desktop apps is allowed in Windows "
          "Settings > Privacy & security > Camera",
          hr);
    }
    if (open_error.empty()) {
      ComPtr<IMFAttributes> reader_attributes;
      hr = MFCreateAttributes(&reader_attributes, 1);
      if (SUCCEEDED(hr)) {
        // Lets the reader decode MJPG and convert colour formats for us.
        hr = reader_attributes->SetUINT32(
            MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE);
      }
      if (SUCCEEDED(hr)) {
        hr = MFCreateSourceReaderFromMediaSource(
            source.Get(), reader_attributes.Get(), &reader);
      }
      if (FAILED(hr)) open_error = HrMessage("Could not read the camera", hr);
    }
    if (open_error.empty()) {
      SelectSmallNativeType(reader.Get());
      if (color_) {
        // Colour: let Media Foundation convert to RGB32 when it can.
        hr = SetOutputSubtype(reader.Get(), MFVideoFormat_RGB32);
        if (FAILED(hr)) hr = SetOutputSubtype(reader.Get(), MFVideoFormat_YUY2);
        if (FAILED(hr)) hr = SetOutputSubtype(reader.Get(), MFVideoFormat_NV12);
      } else {
        hr = SetOutputSubtype(reader.Get(), MFVideoFormat_NV12);
        if (FAILED(hr)) hr = SetOutputSubtype(reader.Get(), MFVideoFormat_YUY2);
        if (FAILED(hr)) hr = SetOutputSubtype(reader.Get(), MFVideoFormat_RGB32);
      }
      if (SUCCEEDED(hr)) hr = ReadFrameFormat(reader.Get(), &format);
      if (FAILED(hr)) {
        open_error = HrMessage("The camera's video format is not supported", hr);
      }
    }
    if (!open_error.empty()) {
      if (source) source->Shutdown();
      opened->set_value(open_error);
    } else {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        thumb_width_ = color_ ? requested_width_ : kThumbnailWidth;
        thumb_height_ = ThumbnailHeight(format.width, format.height, thumb_width_);
        running_ = true;
      }
      opened->set_value(std::string());

      // --- Capture loop. ---
      std::vector<uint8_t> thumbnail;
      while (!stop_requested_) {
        int exposure_request = -1;
        {
          std::lock_guard<std::mutex> lock(mutex_);
          exposure_request = exposure_request_;
          exposure_request_ = -1;
        }
        if (exposure_request != -1) {
          const bool ok = ApplyAutoExposure(source.Get(), exposure_request == 1);
          {
            std::lock_guard<std::mutex> lock(mutex_);
            exposure_result_ = ok ? 1 : 0;
          }
          exposure_cv_.notify_all();
        }

        DWORD flags = 0;
        ComPtr<IMFSample> sample;
        hr = reader->ReadSample(kVideoStream, 0, nullptr, &flags, nullptr,
                                &sample);
        std::string error;
        if (FAILED(hr)) {
          error = HrMessage("The camera stopped sending frames", hr);
        } else if ((flags & MF_SOURCE_READERF_ERROR) != 0 ||
                   (flags & MF_SOURCE_READERF_ENDOFSTREAM) != 0) {
          error = "The camera was disconnected";
        }
        if (!error.empty()) {
          {
            std::lock_guard<std::mutex> lock(mutex_);
            error_ = error;
            error_ready_ = true;
          }
          on_update_();
          break;
        }
        if ((flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) != 0) {
          if (SUCCEEDED(ReadFrameFormat(reader.Get(), &format))) {
            std::lock_guard<std::mutex> lock(mutex_);
            thumb_height_ =
                ThumbnailHeight(format.width, format.height, thumb_width_);
          }
        }
        if (!sample) continue;

        ComPtr<IMFMediaBuffer> buffer;
        if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) continue;
        const int width = static_cast<int>(format.width);
        const int height = static_cast<int>(format.height);
        const int thumb_width = thumb_width_;
        const int thumb_height = ThumbnailHeight(width, height, thumb_width);
        auto downscale = [&](const BYTE* first_row, std::ptrdiff_t stride) {
          if (color_) {
            DownscaleBgra(first_row, width, height, stride, format.layout,
                          thumb_width, thumb_height, &thumbnail);
          } else {
            DownscaleLuma(first_row, width, height, stride, format.layout,
                          thumb_width, thumb_height, &thumbnail);
          }
        };
        bool converted = false;

        ComPtr<IMF2DBuffer> buffer_2d;
        BYTE* scanline0 = nullptr;
        LONG pitch = 0;
        if (SUCCEEDED(buffer.As(&buffer_2d)) &&
            SUCCEEDED(buffer_2d->Lock2D(&scanline0, &pitch))) {
          downscale(scanline0, pitch);
          buffer_2d->Unlock2D();
          converted = true;
        } else {
          BYTE* data = nullptr;
          DWORD max_length = 0, current_length = 0;
          if (SUCCEEDED(buffer->Lock(&data, &max_length, &current_length))) {
            const LONG stride = format.stride;
            const DWORD needed =
                static_cast<DWORD>(std::abs(stride)) * format.height;
            if (stride != 0 && current_length >= needed) {
              const BYTE* first_row =
                  stride < 0 ? data + static_cast<size_t>(-stride) *
                                          (format.height - 1)
                             : data;
              downscale(first_row, stride);
              converted = true;
            }
            buffer->Unlock();
          }
        }
        if (!converted) continue;
        {
          std::lock_guard<std::mutex> lock(mutex_);
          frame_.swap(thumbnail);
          thumb_height_ = thumb_height;
          frame_ready_ = true;
        }
        on_update_();
      }

      source->Shutdown();
      {
        std::lock_guard<std::mutex> lock(mutex_);
        running_ = false;
      }
      exposure_cv_.notify_all();
    }
  }
  if (SUCCEEDED(co_hr)) CoUninitialize();
}

}  // namespace light_capture
