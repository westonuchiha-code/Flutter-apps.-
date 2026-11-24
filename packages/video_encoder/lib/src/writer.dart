import 'dart:io';
import 'dart:typed_data';

import 'avi.dart';
import 'mp4.dart';

/// Picture and sound settings of a video.
class VideoSpec {
  const VideoSpec({
    required this.width,
    required this.height,
    this.fps = 30,
    this.sampleRate = 44100,
    this.channels = 2,
    this.audio = true,
    this.videoBitrate = 0,
  }) : assert(width % 2 == 0 && height % 2 == 0, 'sizes must be even');

  final int width, height, fps, sampleRate, channels;
  final bool audio;

  /// Bits per second (0: about 0.2 bits per pixel per frame, at least
  /// 2 Mbit/s, so blocky pixel art stays crisp).
  final int videoBitrate;

  int get bitrate => videoBitrate > 0
      ? videoBitrate
      : (width * height * fps * 0.2).round().clamp(2000000, 20000000);

  /// Sound frames (samples per channel) that belong to video frame [i]:
  /// spreads the remainder so audio and video never drift.
  int audioFramesFor(int i) =>
      ((i + 1) * sampleRate) ~/ fps - (i * sampleRate) ~/ fps;
}

/// Something that writes a video file frame by frame.
abstract class VideoWriter {
  VideoSpec get spec;
  File get file;

  /// Appends one picture: ARGB words (0xAARRGGBB), [VideoSpec.width] ×
  /// [VideoSpec.height].
  Future<void> addFrame(Uint32List argb);

  /// Appends interleaved 16-bit samples ([VideoSpec.channels] per frame).
  Future<void> addAudio(Int16List pcm);

  /// Finishes the file.
  Future<File> finish();

  /// Stops and deletes the file.
  Future<void> cancel();
}

/// Opens an MP4 writer where the system has an encoder, otherwise an AVI
/// writer. [basePath] has no extension; the right one is added.
Future<VideoWriter> openVideoWriter(
  String basePath,
  VideoSpec spec, {
  bool preferMp4 = true,
}) async {
  if (preferMp4 && Mp4Writer.isSupported) {
    return Mp4Writer.open(File('$basePath.mp4'), spec);
  }
  return AviWriter.open(File('$basePath.avi'), spec);
}
