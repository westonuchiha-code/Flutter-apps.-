// Linux implementation of light_capture using Video4Linux2 (V4L2).
// Same channel protocol as the Windows implementation; see
// windows/light_capture_plugin.h.
#include "include/light_capture/light_capture_plugin.h"

#include <fcntl.h>
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "luma_downscale.h"

namespace {

using light_capture::DownscaleBgra;
using light_capture::DownscaleLuma;
using light_capture::kThumbnailWidth;
using light_capture::PixelLayout;
using light_capture::ThumbnailHeight;

int Xioctl(int fd, unsigned long request, void* arg) {
  int r;
  do {
    r = ioctl(fd, request, arg);
  } while (r == -1 && errno == EINTR);
  return r;
}

std::string ErrnoMessage(const std::string& what) {
  return what + ": " + std::strerror(errno);
}

struct CameraInfo {
  std::string id;
  std::string name;
};

std::vector<CameraInfo> ListCameras() {
  std::vector<CameraInfo> cameras;
  for (int i = 0; i < 64; ++i) {
    const std::string path = "/dev/video" + std::to_string(i);
    const int fd = open(path.c_str(), O_RDWR | O_NONBLOCK);
    if (fd < 0) continue;
    v4l2_capability cap = {};
    if (Xioctl(fd, VIDIOC_QUERYCAP, &cap) == 0) {
      const uint32_t caps = (cap.capabilities & V4L2_CAP_DEVICE_CAPS)
                                ? cap.device_caps
                                : cap.capabilities;
      if ((caps & V4L2_CAP_VIDEO_CAPTURE) && (caps & V4L2_CAP_STREAMING)) {
        cameras.push_back({path, reinterpret_cast<const char*>(cap.card)});
      }
    }
    close(fd);
  }
  return cameras;
}

// Captures from one V4L2 device on a background thread.
class CaptureSession {
 public:
  explicit CaptureSession(std::function<void()> on_update)
      : on_update_(std::move(on_update)) {}
  ~CaptureSession() { Stop(); }

  // Returns an empty string on success.
  // With [color], frames are BGRA [width] pixels wide; otherwise 8-bit luma.
  std::string Start(const std::string& path, bool color = false,
                    int width = kThumbnailWidth) {
    color_ = color;
    thumb_width_ = color ? std::clamp(width, 16, light_capture::kMaxThumbnailWidth)
                         : kThumbnailWidth;
    fd_ = open(path.c_str(), O_RDWR | O_NONBLOCK);
    if (fd_ < 0) return ErrnoMessage("Could not open " + path);

    v4l2_format fmt = {};
    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmt.fmt.pix.width = 640;
    fmt.fmt.pix.height = 480;
    fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
    fmt.fmt.pix.field = V4L2_FIELD_ANY;
    if (Xioctl(fd_, VIDIOC_S_FMT, &fmt) < 0) {
      // Fall back to whatever the device is currently set to.
      fmt = {};
      fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
      if (Xioctl(fd_, VIDIOC_G_FMT, &fmt) < 0) {
        return Fail(ErrnoMessage("Could not read the camera format"));
      }
    }
    width_ = static_cast<int>(fmt.fmt.pix.width);
    height_ = static_cast<int>(fmt.fmt.pix.height);
    stride_ = static_cast<int>(fmt.fmt.pix.bytesperline);
    switch (fmt.fmt.pix.pixelformat) {
      case V4L2_PIX_FMT_YUYV:
        layout_ = PixelLayout::kYuyv;
        if (stride_ == 0) stride_ = width_ * 2;
        break;
      case V4L2_PIX_FMT_UYVY:
        layout_ = PixelLayout::kUyvy;
        if (stride_ == 0) stride_ = width_ * 2;
        break;
      case V4L2_PIX_FMT_GREY:
      case V4L2_PIX_FMT_NV12:
      case V4L2_PIX_FMT_NV21:
      case V4L2_PIX_FMT_YUV420:
      case V4L2_PIX_FMT_YVU420:
        layout_ = PixelLayout::kLuma8;
        if (stride_ == 0) stride_ = width_;
        break;
      default:
        return Fail("The camera's video format is not supported "
                    "(needs YUYV, UYVY, NV12, YUV420 or GREY)");
    }
    thumb_height_ = ThumbnailHeight(width_, height_, thumb_width_);

    v4l2_requestbuffers req = {};
    req.count = 4;
    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_MMAP;
    if (Xioctl(fd_, VIDIOC_REQBUFS, &req) < 0 || req.count < 2) {
      return Fail(ErrnoMessage("Could not allocate camera buffers"));
    }
    for (uint32_t i = 0; i < req.count; ++i) {
      v4l2_buffer buf = {};
      buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
      buf.memory = V4L2_MEMORY_MMAP;
      buf.index = i;
      if (Xioctl(fd_, VIDIOC_QUERYBUF, &buf) < 0) {
        return Fail(ErrnoMessage("Could not query camera buffer"));
      }
      void* start = mmap(nullptr, buf.length, PROT_READ | PROT_WRITE,
                         MAP_SHARED, fd_, buf.m.offset);
      if (start == MAP_FAILED) {
        return Fail(ErrnoMessage("Could not map camera buffer"));
      }
      buffers_.push_back({start, buf.length});
      if (Xioctl(fd_, VIDIOC_QBUF, &buf) < 0) {
        return Fail(ErrnoMessage("Could not queue camera buffer"));
      }
    }
    v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (Xioctl(fd_, VIDIOC_STREAMON, &type) < 0) {
      return Fail(ErrnoMessage("Could not start the camera"));
    }
    streaming_ = true;
    stop_requested_ = false;
    thread_ = std::thread([this] { Run(); });
    return std::string();
  }

  void Stop() {
    stop_requested_ = true;
    if (thread_.joinable()) thread_.join();
    if (streaming_) {
      v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
      Xioctl(fd_, VIDIOC_STREAMOFF, &type);
      streaming_ = false;
    }
    for (const Buffer& b : buffers_) munmap(b.start, b.length);
    buffers_.clear();
    if (fd_ >= 0) {
      close(fd_);
      fd_ = -1;
    }
  }

  // Turns automatic exposure on or off. Returns false if unsupported.
  bool SetAutoExposure(bool enabled) {
    if (fd_ < 0) return false;
    v4l2_control control = {};
    control.id = V4L2_CID_EXPOSURE_AUTO;
    control.value = enabled ? V4L2_EXPOSURE_APERTURE_PRIORITY
                            : V4L2_EXPOSURE_MANUAL;
    bool ok = Xioctl(fd_, VIDIOC_S_CTRL, &control) == 0;
    if (!ok && enabled) {
      control.value = V4L2_EXPOSURE_AUTO;
      ok = Xioctl(fd_, VIDIOC_S_CTRL, &control) == 0;
    }
    v4l2_control gain = {};
    gain.id = V4L2_CID_AUTOGAIN;
    gain.value = enabled ? 1 : 0;
    Xioctl(fd_, VIDIOC_S_CTRL, &gain);  // Best effort.
    return ok;
  }

  int thumbnail_height() const { return thumb_height_; }
  int thumbnail_width() const { return thumb_width_; }
  int channels() const { return color_ ? 4 : 1; }

  bool TakeFrame(std::vector<uint8_t>* pixels) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!frame_ready_) return false;
    frame_ready_ = false;
    pixels->swap(frame_);
    return true;
  }

  bool TakeError(std::string* error) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!error_ready_) return false;
    error_ready_ = false;
    *error = error_;
    return true;
  }

 private:
  struct Buffer {
    void* start;
    size_t length;
  };

  std::string Fail(const std::string& message) {
    Stop();
    return message;
  }

  void ReportError(const std::string& message) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      error_ = message;
      error_ready_ = true;
    }
    on_update_();
  }

  void Run() {
    std::vector<uint8_t> thumbnail;
    while (!stop_requested_) {
      pollfd pfd = {fd_, POLLIN, 0};
      const int ready = poll(&pfd, 1, 200);
      if (ready < 0) {
        if (errno == EINTR) continue;
        ReportError(ErrnoMessage("Camera error"));
        return;
      }
      if (ready == 0) continue;
      if (pfd.revents & (POLLERR | POLLHUP)) {
        ReportError("The camera was disconnected");
        return;
      }
      v4l2_buffer buf = {};
      buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
      buf.memory = V4L2_MEMORY_MMAP;
      if (Xioctl(fd_, VIDIOC_DQBUF, &buf) < 0) {
        if (errno == EAGAIN) continue;
        ReportError(ErrnoMessage("The camera stopped sending frames"));
        return;
      }
      const Buffer& b = buffers_[buf.index];
      const size_t needed = static_cast<size_t>(stride_) * height_;
      if (buf.bytesused >= needed || buf.bytesused == 0) {
        if (color_) {
          DownscaleBgra(static_cast<const uint8_t*>(b.start), width_, height_,
                        stride_, layout_, thumb_width_, thumb_height_,
                        &thumbnail);
        } else {
          DownscaleLuma(static_cast<const uint8_t*>(b.start), width_, height_,
                        stride_, layout_, thumb_width_, thumb_height_,
                        &thumbnail);
        }
        {
          std::lock_guard<std::mutex> lock(mutex_);
          frame_.swap(thumbnail);
          frame_ready_ = true;
        }
        on_update_();
      }
      if (Xioctl(fd_, VIDIOC_QBUF, &buf) < 0) {
        ReportError(ErrnoMessage("Camera buffer error"));
        return;
      }
    }
  }

  std::function<void()> on_update_;
  int fd_ = -1;
  int width_ = 0;
  int height_ = 0;
  int stride_ = 0;
  int thumb_height_ = 0;
  int thumb_width_ = kThumbnailWidth;
  bool color_ = false;
  PixelLayout layout_ = PixelLayout::kYuyv;
  std::vector<Buffer> buffers_;
  bool streaming_ = false;
  std::thread thread_;
  std::atomic<bool> stop_requested_{false};

  std::mutex mutex_;
  std::vector<uint8_t> frame_;
  bool frame_ready_ = false;
  std::string error_;
  bool error_ready_ = false;
};

}  // namespace

#define LIGHT_CAPTURE_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), light_capture_plugin_get_type(), \
                              LightCapturePlugin))

struct _LightCapturePlugin {
  GObject parent_instance;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  gboolean listening;
  CaptureSession* session;
  std::atomic<bool>* wakeup_pending;
};

G_DEFINE_TYPE(LightCapturePlugin, light_capture_plugin, g_object_get_type())

static void deliver_pending(LightCapturePlugin* self) {
  if (self->session == nullptr) return;
  std::string error;
  if (self->session->TakeError(&error) && self->listening) {
    fl_event_channel_send_error(self->event_channel, "camera_error",
                                error.c_str(), nullptr, nullptr, nullptr);
  }
  std::vector<uint8_t> pixels;
  if (self->session->TakeFrame(&pixels) && self->listening) {
    g_autoptr(FlValue) event = fl_value_new_map();
    fl_value_set_string_take(event, "width",
                             fl_value_new_int(self->session->thumbnail_width()));
    fl_value_set_string_take(event, "height",
                             fl_value_new_int(self->session->thumbnail_height()));
    fl_value_set_string_take(event, "channels",
                             fl_value_new_int(self->session->channels()));
    fl_value_set_string_take(
        event, "pixels", fl_value_new_uint8_list(pixels.data(), pixels.size()));
    fl_event_channel_send(self->event_channel, event, nullptr, nullptr);
  }
}

static gboolean wakeup_cb(gpointer user_data) {
  LightCapturePlugin* self = LIGHT_CAPTURE_PLUGIN(user_data);
  self->wakeup_pending->store(false);
  deliver_pending(self);
  return G_SOURCE_REMOVE;
}

// Called on the capture thread.
static void notify_main_thread(LightCapturePlugin* self) {
  if (self->wakeup_pending->exchange(true)) return;
  g_main_context_invoke_full(nullptr, G_PRIORITY_DEFAULT, wakeup_cb,
                             g_object_ref(self), g_object_unref);
}

static void stop_session(LightCapturePlugin* self) {
  delete self->session;
  self->session = nullptr;
}

static FlMethodResponse* handle_start(LightCapturePlugin* self, FlValue* args) {
  FlValue* id = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                    ? fl_value_lookup_string(args, "id")
                    : nullptr;
  if (id == nullptr || fl_value_get_type(id) != FL_VALUE_TYPE_STRING) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad_args", "Missing camera id", nullptr));
  }
  stop_session(self);
  auto* session = new CaptureSession([self] { notify_main_thread(self); });
  FlValue* color = fl_value_lookup_string(args, "color");
  FlValue* width = fl_value_lookup_string(args, "width");
  const bool want_color = color != nullptr &&
                          fl_value_get_type(color) == FL_VALUE_TYPE_BOOL &&
                          fl_value_get_bool(color);
  const int want_width = width != nullptr &&
                                 fl_value_get_type(width) == FL_VALUE_TYPE_INT
                             ? static_cast<int>(fl_value_get_int(width))
                             : kThumbnailWidth;
  const std::string error =
      session->Start(fl_value_get_string(id), want_color, want_width);
  if (!error.empty()) {
    delete session;
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("camera_error", error.c_str(), nullptr));
  }
  self->session = session;
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "width",
                           fl_value_new_int(session->thumbnail_width()));
  fl_value_set_string_take(result, "height",
                           fl_value_new_int(session->thumbnail_height()));
  fl_value_set_string_take(result, "channels",
                           fl_value_new_int(session->channels()));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  LightCapturePlugin* self = LIGHT_CAPTURE_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "listCameras") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    for (const CameraInfo& camera : ListCameras()) {
      FlValue* entry = fl_value_new_map();
      fl_value_set_string_take(entry, "id",
                               fl_value_new_string(camera.id.c_str()));
      fl_value_set_string_take(entry, "name",
                               fl_value_new_string(camera.name.c_str()));
      fl_value_append_take(list, entry);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (strcmp(method, "start") == 0) {
    response = handle_start(self, args);
  } else if (strcmp(method, "stop") == 0) {
    stop_session(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setAutoExposure") == 0) {
    FlValue* enabled =
        args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
            ? fl_value_lookup_string(args, "enabled")
            : nullptr;
    if (enabled == nullptr || fl_value_get_type(enabled) != FL_VALUE_TYPE_BOOL) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad_args", "Missing 'enabled'", nullptr));
    } else {
      const bool ok =
          self->session != nullptr &&
          self->session->SetAutoExposure(fl_value_get_bool(enabled));
      g_autoptr(FlValue) result = fl_value_new_bool(ok);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static FlMethodErrorResponse* listen_cb(FlEventChannel* channel, FlValue* args,
                                        gpointer user_data) {
  LIGHT_CAPTURE_PLUGIN(user_data)->listening = TRUE;
  return nullptr;
}

static FlMethodErrorResponse* cancel_cb(FlEventChannel* channel, FlValue* args,
                                        gpointer user_data) {
  LIGHT_CAPTURE_PLUGIN(user_data)->listening = FALSE;
  return nullptr;
}

static void light_capture_plugin_dispose(GObject* object) {
  LightCapturePlugin* self = LIGHT_CAPTURE_PLUGIN(object);
  stop_session(self);
  g_clear_object(&self->method_channel);
  g_clear_object(&self->event_channel);
  G_OBJECT_CLASS(light_capture_plugin_parent_class)->dispose(object);
}

static void light_capture_plugin_finalize(GObject* object) {
  delete LIGHT_CAPTURE_PLUGIN(object)->wakeup_pending;
  G_OBJECT_CLASS(light_capture_plugin_parent_class)->finalize(object);
}

static void light_capture_plugin_class_init(LightCapturePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = light_capture_plugin_dispose;
  G_OBJECT_CLASS(klass)->finalize = light_capture_plugin_finalize;
}

static void light_capture_plugin_init(LightCapturePlugin* self) {
  self->wakeup_pending = new std::atomic<bool>(false);
}

void light_capture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  LightCapturePlugin* plugin = LIGHT_CAPTURE_PLUGIN(
      g_object_new(light_capture_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  plugin->method_channel = fl_method_channel_new(
      messenger, "light_capture", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->method_channel, method_call_cb, g_object_ref(plugin),
      g_object_unref);

  plugin->event_channel = fl_event_channel_new(
      messenger, "light_capture/frames", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->event_channel, listen_cb,
                                       cancel_cb, g_object_ref(plugin),
                                       g_object_unref);

  g_object_unref(plugin);
}
