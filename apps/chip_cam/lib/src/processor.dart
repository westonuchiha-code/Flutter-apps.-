import 'dart:async';
import 'dart:isolate';

import 'package:video_kit/video_kit.dart';

/// A job for the worker: one camera frame through one effect.
class _Job {
  const _Job(
    this.effectId,
    this.values,
    this.width,
    this.height,
    this.pixels,
    this.time,
    this.reset,
  );
  final String effectId;
  final Map<String, double> values;
  final int width, height;
  final TransferableTypedData pixels;
  final double time;
  final bool reset;
}

class _Result {
  const _Result(this.width, this.height, this.pixels, this.ms);
  final int width, height;
  final TransferableTypedData pixels;
  final int ms;
}

/// Runs effects away from the screen so the app stays smooth. Only one frame
/// is in flight; frames arriving meanwhile are dropped (live video).
abstract class Processor {
  Future<void> start();

  /// Processes [frame], or returns null if still busy with the last one.
  Future<VideoFrame?> process(
    VideoEffect effect,
    VideoFrame frame,
    double time, {
    bool reset = false,
  });

  /// Milliseconds the last frame took.
  int get lastMs;
  void dispose();
}

/// The worker isolate.
class IsolateProcessor implements Processor {
  Isolate? _isolate;
  SendPort? _send;
  final _replies = ReceivePort();
  Completer<_Result>? _pending;
  @override
  int lastMs = 0;

  @override
  Future<void> start() async {
    final ready = Completer<SendPort>();
    _replies.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is _Result) {
        _pending?.complete(m);
        _pending = null;
      }
    });
    _isolate = await Isolate.spawn(_worker, _replies.sendPort);
    _send = await ready.future;
  }

  static void _worker(SendPort reply) {
    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    final effects = {for (final e in allEffects()) e.id: e};
    inbox.listen((m) {
      if (m is! _Job) return;
      final sw = Stopwatch()..start();
      final e = effects[m.effectId]!;
      if (m.reset) e.reset();
      e.values.addAll(m.values);
      final px = m.pixels.materialize().asUint32List();
      final out = runEffect(e, VideoFrame(m.width, m.height, px), m.time);
      reply.send(
        _Result(
          out.width,
          out.height,
          TransferableTypedData.fromList([out.pixels]),
          sw.elapsedMilliseconds,
        ),
      );
    });
  }

  @override
  Future<VideoFrame?> process(
    VideoEffect effect,
    VideoFrame frame,
    double time, {
    bool reset = false,
  }) async {
    final send = _send;
    if (send == null || _pending != null) return null;
    final done = _pending = Completer<_Result>();
    send.send(
      _Job(
        effect.id,
        Map.of(effect.values),
        frame.width,
        frame.height,
        TransferableTypedData.fromList([frame.pixels]),
        time,
        reset,
      ),
    );
    final r = await done.future;
    lastMs = r.ms;
    return VideoFrame(r.width, r.height, r.pixels.materialize().asUint32List());
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _replies.close();
  }
}

/// Runs effects directly (tests).
class DirectProcessor implements Processor {
  final _effects = {for (final e in allEffects()) e.id: e};
  @override
  int lastMs = 0;

  @override
  Future<void> start() async {}

  @override
  Future<VideoFrame?> process(
    VideoEffect effect,
    VideoFrame frame,
    double time, {
    bool reset = false,
  }) async {
    final e = _effects[effect.id]!;
    if (reset) e.reset();
    e.values.addAll(effect.values);
    return runEffect(e, frame, time);
  }

  @override
  void dispose() {}
}
