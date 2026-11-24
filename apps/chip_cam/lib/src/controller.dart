import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pixel_kit/pixel_kit.dart' as px;
import 'package:video_kit/video_kit.dart';

import 'processor.dart';
import 'source.dart';

/// Longest GIF clip.
const maxClipSeconds = 6.0;
const clipFps = 10;

class ChipCamController extends ChangeNotifier {
  ChipCamController({required this.processor, FrameSource? source})
    : source = source ?? FrameSource();

  final Processor processor;
  final FrameSource source;
  final effects = allEffects();
  List<SourceOption> sources = const [];
  SourceOption? current;
  int effectIndex = 0;
  bool crt = false;
  String? error;

  VideoFrame? output;
  ui.Image? image;
  int _imageVersion = 0;
  bool _resetNext = true;
  final _clock = Stopwatch()..start();
  int _frames = 0;
  double fps = 0;
  final _fpsWatch = Stopwatch()..start();

  // Clip recording.
  final clip = <VideoFrame>[];
  bool recording = false;
  double _lastClipTime = -1;

  VideoEffect get effect => effects[effectIndex];

  Future<void> init() async {
    await processor.start();
    sources = await source.list();
    notifyListeners();
    if (sources.isNotEmpty) {
      await useSource(sources.first);
    }
  }

  @override
  void dispose() {
    unawaited(source.stop());
    processor.dispose();
    image?.dispose();
    super.dispose();
  }

  Future<void> useSource(SourceOption o) async {
    current = o;
    error = null;
    _resetNext = true;
    notifyListeners();
    try {
      await source.start(o, _onFrame, (e) {
        error = e;
        notifyListeners();
      });
    } catch (e) {
      error = '$e';
      notifyListeners();
      // Fall back to the test card so there is always a picture.
      if (o.kind != 'test') {
        final test = sources.firstWhere((s) => s.kind == 'test');
        current = test;
        await source.start(test, _onFrame, (_) {});
      }
    }
  }

  void selectEffect(int i) {
    effectIndex = i.clamp(0, effects.length - 1);
    _resetNext = true;
    notifyListeners();
  }

  void setKnob(String id, double v) {
    effect.values[id] = v;
    notifyListeners();
  }

  void toggleCrt() {
    crt = !crt;
    notifyListeners();
  }

  double get time => _clock.elapsedMilliseconds / 1000;

  Future<void> _onFrame(VideoFrame f) async {
    final reset = _resetNext;
    final out = await processor.process(effect, f, time, reset: reset);
    if (out == null) {
      return;
    }
    if (reset) {
      _resetNext = false;
    }
    await showFrame(out);
  }

  /// Puts a processed frame on screen (and in the clip when recording).
  Future<void> showFrame(VideoFrame out) async {
    output = out;
    _frames++;
    if (_fpsWatch.elapsedMilliseconds > 1000) {
      fps = _frames * 1000 / _fpsWatch.elapsedMilliseconds;
      _frames = 0;
      _fpsWatch.reset();
    }
    if (recording) {
      final t = time;
      if (_lastClipTime < 0 || t - _lastClipTime >= 1 / clipFps - 0.005) {
        _lastClipTime = t;
        clip.add(
          out.width > 320
              ? out.resized(320, (320 * out.height / out.width).round())
              : out,
        );
        if (clip.length >= maxClipSeconds * clipFps) {
          recording = false;
        }
      }
    }
    final version = ++_imageVersion;
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      out.bgraBytes,
      out.width,
      out.height,
      ui.PixelFormat.bgra8888,
      c.complete,
    );
    final next = await c.future;
    if (version != _imageVersion) {
      next.dispose();
      return;
    }
    image?.dispose();
    image = next;
    notifyListeners();
  }

  void startClip() {
    clip.clear();
    _lastClipTime = -1;
    recording = true;
    notifyListeners();
  }

  void stopClip() {
    recording = false;
    notifyListeners();
  }

  /// The current picture as a PNG (scaled up so small machines look crisp).
  Uint8List? snapshotPng() {
    final f = output;
    if (f == null) {
      return null;
    }
    final scale = f.width < 200 ? 4 : (f.width < 400 ? 2 : 1);
    return img.encodePng(px.toImage(f.pixels, f.width, f.height, scale: scale));
  }
}

/// Builds an animated GIF from a clip. Frames with more than 255 colours get
/// a median-cut palette first (GIF holds 256 colours per frame).
Uint8List clipToGif(List<VideoFrame> frames, {int scale = 1}) {
  final first = frames.first;
  final s = px.Sprite.blank(first.width, first.height);
  for (var i = 0; i < frames.length; i++) {
    if (i > 0) {
      s.addFrame(copy: false);
    }
    var f = frames[i];
    if (f.width != first.width || f.height != first.height) {
      f = f.resized(first.width, first.height);
    }
    var pixels = f.pixels;
    if (pixels.toSet().length > 255) {
      final pal = px.paletteFromPixels(pixels, 255);
      pixels = px.reduceToPalette(pixels, f.width, pal);
    }
    s.cel(i, 0).setAll(0, pixels);
    s.frames[i].durationMs = 1000 ~/ clipFps;
  }
  return px.spriteToGif(s, scale: scale);
}
