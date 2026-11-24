import 'dart:async';
import 'dart:isolate';

import 'package:video_kit/video_kit.dart';

import 'media.dart';
import 'project.dart';
import 'render.dart';

/// Draws preview frames (canvas size, with effects) away from the screen.
abstract class PreviewEngine {
  Future<void> start();
  void setProject(Project p);
  void addMedia(String id, Media m);
  void setTitle(String sceneId, VideoFrame f);

  /// The frame at [t], or null when still busy with the previous one.
  Future<VideoFrame?> render(double t);
  void dispose();
}

/// Same thread (tests).
class DirectPreview implements PreviewEngine {
  final _media = <String, Media>{};
  final _titles = <String, VideoFrame>{};
  Renderer? _r;

  @override
  Future<void> start() async {}

  @override
  void setProject(Project p) =>
      _r = Renderer(Project.fromJson(p.toJson()), _media, _titles);

  @override
  void addMedia(String id, Media m) => _media[id] = m;

  @override
  void setTitle(String sceneId, VideoFrame f) => _titles[sceneId] = f;

  @override
  Future<VideoFrame?> render(double t) async => _r?.frameAt(t);

  @override
  void dispose() {}
}

class IsolatePreview implements PreviewEngine {
  SendPort? _to;
  Isolate? _isolate;
  ReceivePort? _from;
  Completer<VideoFrame?>? _waiting;
  final _queued = <Object>[];

  @override
  Future<void> start() async {
    final from = ReceivePort();
    _from = from;
    final ready = Completer<SendPort>();
    from.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is (int, int, TransferableTypedData)) {
        final (w, h, data) = m;
        final c = _waiting;
        _waiting = null;
        c?.complete(VideoFrame(w, h, data.materialize().asUint32List()));
      }
    });
    _isolate = await Isolate.spawn(_main, from.sendPort);
    _to = await ready.future;
    for (final q in _queued) {
      _to!.send(q);
    }
    _queued.clear();
  }

  void _send(Object m) => _to == null ? _queued.add(m) : _to!.send(m);

  @override
  void setProject(Project p) => _send(('project', p.toJson()));

  @override
  void addMedia(String id, Media m) => _send(('media', id, m));

  @override
  void setTitle(String sceneId, VideoFrame f) => _send(('title', sceneId, f));

  @override
  Future<VideoFrame?> render(double t) {
    if (_waiting != null || _to == null) return Future.value(null);
    final c = _waiting = Completer<VideoFrame?>();
    _to!.send(('frame', t));
    return c.future;
  }

  @override
  void dispose() {
    _isolate?.kill();
    _from?.close();
    _waiting?.complete(null);
    _waiting = null;
  }

  static void _main(SendPort out) {
    final port = ReceivePort();
    out.send(port.sendPort);
    final media = <String, Media>{};
    final titles = <String, VideoFrame>{};
    Renderer? r;
    port.listen((m) {
      switch (m) {
        case ('project', Map<String, Object?> json):
          r = Renderer(Project.fromJson(json), media, titles);
        case ('media', String id, Media v):
          media[id] = v;
        case ('title', String id, VideoFrame f):
          titles[id] = f;
        case ('frame', double t):
          final f =
              r?.frameAt(t) ?? solid(canvasWidth, canvasHeight, 0xFF000000);
          out.send((
            f.width,
            f.height,
            TransferableTypedData.fromList([f.pixels]),
          ));
      }
    });
  }
}
