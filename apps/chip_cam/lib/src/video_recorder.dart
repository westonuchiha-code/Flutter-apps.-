import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_kit/audio_kit.dart';
import 'package:video_kit/video_kit.dart';

/// Longest video recording.
const maxVideoSeconds = 60.0;

/// Frames per second kept in a video recording (lo-fi, and keeps files small).
const videoFps = 15;

/// Records what Chip Cam shows (each effect's own resolution, at most 320
/// wide) with microphone sound, into a Chip Cam clip. Frames are encoded in
/// a worker isolate as they arrive.
class VideoRecorder {
  VideoRecorder({this.withSound = true});

  final bool withSound;
  final _watch = Stopwatch();
  SendPort? _worker;
  Isolate? _isolate;
  ReceivePort? _replies;
  final _pending = <Completer<Object?>>[];
  MicRecorder? _mic;
  File? _wav;
  double _lastTime = -1;
  int _inFlight = 0;
  bool recording = false;

  /// Set when sound could not be recorded (the video still is).
  String? soundError;

  double get seconds => _watch.elapsedMilliseconds / 1000;

  Future<void> start(Directory temp) async {
    final replies = ReceivePort();
    _replies = replies;
    final ready = Completer<SendPort>();
    replies.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m == 'frame') {
        _inFlight--;
      } else if (_pending.isNotEmpty) {
        _pending.removeAt(0).complete(m);
      }
    });
    final path =
        '${temp.path}${Platform.pathSeparator}rec_${DateTime.now().millisecondsSinceEpoch}.$clipExtension';
    _isolate = await Isolate.spawn(_workerMain, (replies.sendPort, path));
    _worker = await ready.future;
    if (withSound) {
      final mic = MicRecorder();
      final wav = File('$path.wav');
      if (await mic.start(wav)) {
        _mic = mic;
        _wav = wav;
      } else {
        soundError = mic.error ?? 'No microphone';
        mic.dispose();
      }
    }
    _lastTime = -1;
    _watch
      ..reset()
      ..start();
    recording = true;
  }

  /// Offers a shown frame; keeps up to [videoFps] a second.
  void addFrame(VideoFrame f) {
    if (!recording) return;
    final t = seconds;
    if (_lastTime >= 0 && t - _lastTime < 1 / videoFps - 0.004) return;
    // The worker is behind (slow phone): skip rather than pile up.
    if (_inFlight > 3) return;
    _lastTime = t;
    final small = f.width > 320
        ? f.resized(320, (320 * f.height / f.width).round())
        : f;
    _inFlight++;
    _worker!.send((
      'frame',
      TransferableTypedData.fromList([small.pixels]),
      small.width,
      small.height,
      t,
    ));
  }

  Future<Object?> _ask(Object message) {
    final c = Completer<Object?>();
    _pending.add(c);
    _worker!.send(message);
    return c.future;
  }

  /// Stops and returns the finished clip file (null if nothing was recorded).
  Future<File?> stop({Map<String, Object?> extra = const {}}) async {
    if (!recording) return null;
    recording = false;
    final length = seconds;
    _watch.stop();
    Int16List? sound;
    var rate = 48000;
    final mic = _mic, wav = _wav;
    if (mic != null && wav != null) {
      final info = await mic.stop();
      mic.dispose();
      if (info != null) {
        rate = info.format.sampleRate;
        final bytes = await wav.readAsBytes();
        final data = Uint8List.fromList(
          bytes.sublist(info.dataOffset, info.dataOffset + info.dataLength),
        );
        sound = data.buffer.asInt16List(0, data.length ~/ 2);
      }
      try {
        await wav.delete();
      } catch (_) {}
    }
    final result = await _ask((
      'finish',
      sound == null ? null : TransferableTypedData.fromList([sound]),
      rate,
      length,
      extra,
    ));
    _close();
    return result is String ? File(result) : null;
  }

  Future<void> cancel() async {
    if (!recording) return;
    recording = false;
    await _mic?.stop();
    _mic?.dispose();
    try {
      await _wav?.delete();
    } catch (_) {}
    await _ask(('cancel',));
    _close();
  }

  void _close() {
    _isolate?.kill();
    _isolate = null;
    _replies?.close();
    _replies = null;
    _worker = null;
  }
}

Future<void> _workerMain((SendPort, String) args) async {
  final (reply, path) = args;
  final port = ReceivePort();
  reply.send(port.sendPort);
  final writer = await ClipWriter.create(File(path));
  // Messages are handled one at a time, in order.
  await for (final m in port) {
    switch (m) {
      case ('frame', TransferableTypedData data, int w, int h, double t):
        final px = data.materialize().asUint32List();
        await writer.addFrame(VideoFrame(w, h, px), t);
        reply.send('frame');
      case (
        'finish',
        TransferableTypedData? sound,
        int rate,
        double length,
        Map<String, Object?> extra,
      ):
        if (writer.frames.length < 2) {
          await writer.cancel();
          reply.send(null);
        } else {
          final s = sound?.materialize().asInt16List();
          await writer.finish(
            sound: s,
            sampleRate: rate,
            length: length,
            extra: extra,
          );
          reply.send(path);
        }
        port.close();
      case ('cancel',):
        await writer.cancel();
        reply.send(null);
        port.close();
    }
  }
}
