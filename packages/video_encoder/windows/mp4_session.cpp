#include "mp4_session.h"

#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>

#include <cstring>
#include <sstream>

namespace video_encoder {

using Microsoft::WRL::ComPtr;

namespace {

std::string Fail(const char* what, HRESULT hr) {
  std::ostringstream s;
  s << what << " failed (0x" << std::hex << static_cast<uint32_t>(hr) << ")";
  return s.str();
}

// AAC encoder accepts only these byte rates.
UINT32 AacBytesPerSecond(uint32_t channels) {
  return channels >= 2 ? 24000 : 16000;
}

}  // namespace

#define CHECK(what, expr)              \
  do {                                 \
    HRESULT hr_ = (expr);              \
    if (FAILED(hr_)) return Fail(what, hr_); \
  } while (0)

Mp4Session::~Mp4Session() {
  // Not finished: drop the writer (the partial file is deleted by Dart).
  writer_.Reset();
}

std::string Mp4Session::Start(const std::wstring& path, uint32_t width,
                              uint32_t height, uint32_t fps, uint32_t bitrate,
                              uint32_t sample_rate, uint32_t channels,
                              bool audio) {
  width_ = width;
  height_ = height;
  fps_ = fps;
  sample_rate_ = sample_rate;
  channels_ = channels;
  audio_ = audio;

  ComPtr<IMFAttributes> attrs;
  CHECK("Attributes", MFCreateAttributes(&attrs, 2));
  CHECK("Attributes", attrs->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE));
  CHECK("Attributes", attrs->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE));
  CHECK("Creating the MP4 file", MFCreateSinkWriterFromURL(path.c_str(), nullptr, attrs.Get(), &writer_));

  // Video: H.264 out, I420 in.
  ComPtr<IMFMediaType> out;
  CHECK("Video type", MFCreateMediaType(&out));
  CHECK("Video type", out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
  CHECK("Video type", out->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264));
  CHECK("Video type", out->SetUINT32(MF_MT_AVG_BITRATE, bitrate));
  CHECK("Video type", out->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive));
  CHECK("Video type", out->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Main));
  CHECK("Video type", MFSetAttributeSize(out.Get(), MF_MT_FRAME_SIZE, width, height));
  CHECK("Video type", MFSetAttributeRatio(out.Get(), MF_MT_FRAME_RATE, fps, 1));
  CHECK("Video type", MFSetAttributeRatio(out.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1));
  CHECK("Adding the video stream", writer_->AddStream(out.Get(), &video_stream_));

  ComPtr<IMFMediaType> in;
  CHECK("Video input type", MFCreateMediaType(&in));
  CHECK("Video input type", in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
  CHECK("Video input type", in->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_I420));
  CHECK("Video input type", in->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive));
  CHECK("Video input type", in->SetUINT32(MF_MT_DEFAULT_STRIDE, width));
  CHECK("Video input type", MFSetAttributeSize(in.Get(), MF_MT_FRAME_SIZE, width, height));
  CHECK("Video input type", MFSetAttributeRatio(in.Get(), MF_MT_FRAME_RATE, fps, 1));
  CHECK("Video input type", MFSetAttributeRatio(in.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1));
  CHECK("Setting the video input", writer_->SetInputMediaType(video_stream_, in.Get(), nullptr));

  if (audio) {
    ComPtr<IMFMediaType> aout;
    CHECK("Audio type", MFCreateMediaType(&aout));
    CHECK("Audio type", aout->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio));
    CHECK("Audio type", aout->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC));
    CHECK("Audio type", aout->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16));
    CHECK("Audio type", aout->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sample_rate));
    CHECK("Audio type", aout->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels));
    CHECK("Audio type", aout->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, AacBytesPerSecond(channels)));
    CHECK("Adding the audio stream", writer_->AddStream(aout.Get(), &audio_stream_));

    ComPtr<IMFMediaType> ain;
    CHECK("Audio input type", MFCreateMediaType(&ain));
    CHECK("Audio input type", ain->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio));
    CHECK("Audio input type", ain->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM));
    CHECK("Audio input type", ain->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16));
    CHECK("Audio input type", ain->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sample_rate));
    CHECK("Audio input type", ain->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels));
    CHECK("Audio input type", ain->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, channels * 2));
    CHECK("Audio input type", ain->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, sample_rate * channels * 2));
    CHECK("Setting the audio input", writer_->SetInputMediaType(audio_stream_, ain.Get(), nullptr));
  }

  CHECK("Starting to write", writer_->BeginWriting());
  return {};
}

std::string Mp4Session::WriteBuffer(DWORD stream, const uint8_t* data,
                                    size_t size, LONGLONG time,
                                    LONGLONG duration) {
  ComPtr<IMFMediaBuffer> buffer;
  CHECK("Buffer", MFCreateMemoryBuffer(static_cast<DWORD>(size), &buffer));
  BYTE* dst = nullptr;
  CHECK("Buffer", buffer->Lock(&dst, nullptr, nullptr));
  std::memcpy(dst, data, size);
  buffer->Unlock();
  CHECK("Buffer", buffer->SetCurrentLength(static_cast<DWORD>(size)));
  ComPtr<IMFSample> sample;
  CHECK("Sample", MFCreateSample(&sample));
  CHECK("Sample", sample->AddBuffer(buffer.Get()));
  CHECK("Sample", sample->SetSampleTime(time));
  CHECK("Sample", sample->SetSampleDuration(duration));
  CHECK("Writing", writer_->WriteSample(stream, sample.Get()));
  return {};
}

std::string Mp4Session::Frame(const uint8_t* i420, size_t size, int64_t index) {
  if (!writer_ || finished_) return "No video is being written";
  if (size < static_cast<size_t>(width_) * height_ * 3 / 2) return "Frame too small";
  const LONGLONG t = index * 10000000LL / fps_;
  const LONGLONG next = (index + 1) * 10000000LL / fps_;
  return WriteBuffer(video_stream_, i420, static_cast<size_t>(width_) * height_ * 3 / 2, t, next - t);
}

std::string Mp4Session::Audio(const uint8_t* pcm, size_t size, int64_t offset_frames) {
  if (!writer_ || finished_) return "No video is being written";
  if (!audio_ || size == 0) return {};
  const size_t frames = size / (channels_ * 2);
  const LONGLONG t = offset_frames * 10000000LL / sample_rate_;
  const LONGLONG d = static_cast<LONGLONG>(frames) * 10000000LL / sample_rate_;
  return WriteBuffer(audio_stream_, pcm, frames * channels_ * 2, t, d);
}

std::string Mp4Session::Finish() {
  if (!writer_ || finished_) return "No video is being written";
  finished_ = true;
  CHECK("Finishing the MP4 file", writer_->Finalize());
  writer_.Reset();
  return {};
}

}  // namespace video_encoder
