# audio_kit

Shared audio tools (Windows, Android, Linux).

- `MicRecorder`: records the microphone to a 16-bit mono WAV, streaming to
  disk; live peaks, level, clip detection, markers, pause. Asks Android for
  the microphone permission. Uses `flutter_recorder` (pinned).
- WAV: `parseWav`, `readWavInfo`, `buildWav`, `WavFileWriter`, `extractWav`,
  `filePeaks` (8/16/24/32-bit PCM and 32-bit float, any channel count).
- `WaveformView`: waveform with trim handles, markers, playhead, tap to seek;
  `live` mode scrolls while recording. `LevelMeter`, `waveformPng`.
- `ClipPlayer`: plays a file or a range of it via `flutter_soloud`.

Linux builds need `libasound2-dev` (ALSA headers).
