import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart' show runInBackground;
import 'package:video_encoder/video_encoder.dart';
import 'package:video_kit/video_kit.dart';

import 'media.dart';
import 'mix.dart';
import 'project.dart';
import 'render.dart';

/// Export sizes (all 4:3).
const exportSizes = [(320, 240), (640, 480), (960, 720)];
const exportRates = [12, 15, 24, 30];

class ExportJob {
  ExportJob({
    required this.project,
    required this.media,
    required this.titles,
    this.width = 640,
    this.height = 480,
    this.fps = 30,
    this.preferMp4 = true,
  });

  final Project project;
  final Map<String, Media> media;
  final Map<String, VideoFrame> titles;
  final int width, height, fps;
  final bool preferMp4;

  /// 0..1 while running.
  final progress = StreamController<double>.broadcast();
  bool _cancelled = false;
  Isolate? _isolate;

  int get frameCount => math.max(1, (project.duration * fps).ceil());

  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
  }

  /// Writes the video to [basePath] + .mp4 (or .avi where MP4 can't be
  /// made). Returns the file, or null if cancelled.
  Future<File?> run(String basePath) async {
    final spec = VideoSpec(
      width: width,
      height: height,
      fps: fps,
      sampleRate: mixRate,
    );
    final p = project, m = media;
    final sound = await runInBackground(_mix, (p, m));
    if (_cancelled) return null;
    final writer = await openVideoWriter(basePath, spec, preferMp4: preferMp4);
    final frames = ReceivePort();
    final queue = StreamIterator(frames);
    try {
      _isolate = await Isolate.spawn(_worker, (
        frames.sendPort,
        p.toJson(),
        m,
        titles,
        width,
        height,
        fps,
        frameCount,
      ));
      if (!await queue.moveNext()) throw StateError('Renderer did not start');
      final credits = queue.current as SendPort;
      var audioPos = 0;
      for (var i = 0; i < frameCount; i++) {
        if (_cancelled || !await queue.moveNext()) break;
        credits.send(1);
        final px = (queue.current as TransferableTypedData)
            .materialize()
            .asUint32List();
        await writer.addFrame(px);
        final n = spec.audioFramesFor(i);
        final chunk = Int16List(n * 2);
        final have = math.max(0, math.min(n, sound.length ~/ 2 - audioPos));
        chunk.setRange(0, have * 2, sound, audioPos * 2);
        audioPos += n;
        await writer.addAudio(chunk);
        progress.add((i + 1) / frameCount);
      }
      if (_cancelled) {
        await writer.cancel();
        return null;
      }
      var file = await writer.finish();
      if (file.path.endsWith('.avi')) file = await _tryMp4(file);
      return file;
    } catch (e) {
      await writer.cancel();
      rethrow;
    } finally {
      _isolate?.kill();
      await queue.cancel();
      frames.close();
      await progress.close();
    }
  }

  /// On Linux (no system MP4 encoder), converts with ffmpeg if installed.
  static Future<File> _tryMp4(File avi) async {
    if (!Platform.isLinux) return avi;
    final mp4 = File('${avi.path.substring(0, avi.path.length - 4)}.mp4');
    try {
      final r = await Process.run('ffmpeg', [
        '-y',
        '-loglevel',
        'error',
        '-i',
        avi.path,
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-preset',
        'fast',
        '-crf',
        '18',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        mp4.path,
      ]);
      if (r.exitCode == 0 && await mp4.exists()) {
        await avi.delete();
        return mp4;
      }
    } catch (_) {
      // No ffmpeg: keep the AVI.
    }
    return avi;
  }
}

/// Renders frames ahead of the writer (at most 3 waiting).
Future<void> _worker(
  (
    SendPort,
    Map<String, Object?>,
    Map<String, Media>,
    Map<String, VideoFrame>,
    int,
    int,
    int,
    int,
  )
  args,
) async {
  final (out, json, media, titles, w, h, fps, count) = args;
  final credits = ReceivePort();
  out.send(credits.sendPort);
  final renderer = Renderer(Project.fromJson(json), media, titles);
  var available = 3;
  Completer<void>? wait;
  credits.listen((_) {
    available++;
    wait?.complete();
    wait = null;
  });
  for (var i = 0; i < count; i++) {
    while (available <= 0) {
      wait = Completer<void>();
      await wait!.future;
    }
    available--;
    final px = outputPixels(renderer.frameAt(i / fps), w, h);
    out.send(TransferableTypedData.fromList([px]));
  }
  credits.close();
}

Int16List _mix((Project, Map<String, Media>) a) => mixAudio(a.$1, a.$2);
