# video_encoder

Video files with sound.

- `Mp4Writer`: H.264 + AAC in MP4 using the system's encoders (Android
  `MediaCodec` + `MediaMuxer`, Windows Media Foundation sink writer). Input
  frames are converted to I420 in Dart. One file at a time.
- `AviWriter`: pure Dart, Motion-JPEG + 16-bit PCM AVI. Works everywhere
  (tested here with ffprobe/ffmpeg).
- `openVideoWriter(basePath, spec)` picks MP4 where available.
- `VideoSpec.audioFramesFor(i)` gives the sound for video frame `i` so
  sound and picture never drift.
- `upscaleNearest` scales pixel art up sharply.

Linux has no native MP4 path (apps can convert the AVI with ffmpeg).
The native code is compiled by CI; run an app's test export on a device to
check it.
