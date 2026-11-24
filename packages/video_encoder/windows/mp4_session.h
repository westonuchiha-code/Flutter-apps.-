#ifndef VIDEO_ENCODER_MP4_SESSION_H_
#define VIDEO_ENCODER_MP4_SESSION_H_

#include <windows.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <cstdint>
#include <string>

namespace video_encoder {

// Writes H.264 + AAC into an MP4 file with Media Foundation's sink writer
// (the encoders built into Windows). Input: I420 frames, 16-bit PCM.
class Mp4Session {
 public:
  Mp4Session() = default;
  ~Mp4Session();

  // Returns an error message, or empty on success.
  std::string Start(const std::wstring& path, uint32_t width, uint32_t height,
                    uint32_t fps, uint32_t bitrate, uint32_t sample_rate,
                    uint32_t channels, bool audio);
  std::string Frame(const uint8_t* i420, size_t size, int64_t index);
  std::string Audio(const uint8_t* pcm, size_t size, int64_t offset_frames);
  std::string Finish();

 private:
  std::string WriteBuffer(DWORD stream, const uint8_t* data, size_t size,
                          LONGLONG time, LONGLONG duration);

  Microsoft::WRL::ComPtr<IMFSinkWriter> writer_;
  DWORD video_stream_ = 0;
  DWORD audio_stream_ = 0;
  uint32_t width_ = 0, height_ = 0, fps_ = 30;
  uint32_t sample_rate_ = 44100, channels_ = 2;
  bool audio_ = false;
  bool finished_ = false;
};

}  // namespace video_encoder

#endif  // VIDEO_ENCODER_MP4_SESSION_H_
