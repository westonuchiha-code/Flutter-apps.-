import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'convert.dart';
import 'writer.dart';

/// H.264 + AAC in MP4 with the system's own encoders (Android MediaCodec,
/// Windows Media Foundation). One file at a time.
class Mp4Writer implements VideoWriter {
  Mp4Writer._(this.file, this.spec);

  static const _channel = MethodChannel('video_encoder');

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  static Future<Mp4Writer> open(File file, VideoSpec spec) async {
    await file.parent.create(recursive: true);
    if (await file.exists()) await file.delete();
    await _channel.invokeMethod<void>('start', {
      'path': file.path,
      'width': spec.width,
      'height': spec.height,
      'fps': spec.fps,
      'bitrate': spec.bitrate,
      'sampleRate': spec.sampleRate,
      'channels': spec.channels,
      'audio': spec.audio,
    });
    return Mp4Writer._(file, spec);
  }

  @override
  final File file;
  @override
  final VideoSpec spec;
  int _frames = 0, _audioFrames = 0;
  bool _done = false;

  @override
  Future<void> addFrame(Uint32List argb) async {
    final yuv = argbToI420(argb, spec.width, spec.height);
    await _channel.invokeMethod<void>('frame', {'data': yuv, 'index': _frames});
    _frames++;
  }

  @override
  Future<void> addAudio(Int16List pcm) async {
    if (!spec.audio || pcm.isEmpty) return;
    final bytes = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
    await _channel.invokeMethod<void>('audio', {
      'data': bytes,
      'offset': _audioFrames,
    });
    _audioFrames += pcm.length ~/ spec.channels;
  }

  @override
  Future<File> finish() async {
    if (!_done) {
      _done = true;
      await _channel.invokeMethod<void>('finish');
    }
    return file;
  }

  @override
  Future<void> cancel() async {
    if (_done) return;
    _done = true;
    try {
      await _channel.invokeMethod<void>('cancel');
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}
