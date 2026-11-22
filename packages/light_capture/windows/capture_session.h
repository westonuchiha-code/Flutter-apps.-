#ifndef LIGHT_CAPTURE_CAPTURE_SESSION_H_
#define LIGHT_CAPTURE_CAPTURE_SESSION_H_

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <future>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace light_capture {

struct CameraInfo {
  std::string id;    // Symbolic link (UTF-8).
  std::string name;  // Friendly name (UTF-8).
};

// Lists video capture devices. Requires MFStartup().
std::vector<CameraInfo> ListCameras();

// Reads frames from one webcam on a background thread using the Media
// Foundation source reader and keeps the newest luminance thumbnail.
class CaptureSession {
 public:
  // `on_update` is called from the capture thread whenever a new frame or an
  // error is available; it must only schedule work, not touch Flutter.
  explicit CaptureSession(std::function<void()> on_update);
  ~CaptureSession();

  CaptureSession(const CaptureSession&) = delete;
  CaptureSession& operator=(const CaptureSession&) = delete;

  // Opens the camera and starts the capture thread. Blocks until the camera is
  // open. Returns an empty string on success, otherwise an error message.
  std::string Start(const std::string& camera_id);
  void Stop();

  // Turns automatic exposure on or off. Returns false if unsupported.
  bool SetAutoExposure(bool enabled);

  int thumbnail_width() const { return thumb_width_; }
  int thumbnail_height() const { return thumb_height_; }

  // Takes the newest frame / error, if any (thread-safe).
  bool TakeFrame(std::vector<uint8_t>* pixels, int* width, int* height);
  bool TakeError(std::string* error);

 private:
  void Run(std::string camera_id, std::promise<std::string>* opened);

  std::function<void()> on_update_;
  std::thread thread_;
  std::atomic<bool> stop_requested_{false};

  std::mutex mutex_;
  std::vector<uint8_t> frame_;
  bool frame_ready_ = false;
  std::string error_;
  bool error_ready_ = false;
  // Exposure changes are applied on the capture thread (which owns the COM
  // objects); the caller waits on `exposure_cv_` for the outcome.
  std::condition_variable exposure_cv_;
  int exposure_request_ = -1;  // -1 none, 0 auto off, 1 auto on.
  int exposure_result_ = -1;   // -1 pending, 0 failed, 1 ok.
  bool running_ = false;

  int thumb_width_ = 0;
  int thumb_height_ = 0;
};

}  // namespace light_capture

#endif  // LIGHT_CAPTURE_CAPTURE_SESSION_H_
