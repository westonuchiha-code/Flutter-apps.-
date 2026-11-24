import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:video_kit/video_kit.dart';

import 'media.dart';
import 'mix.dart';
import 'preview.dart';
import 'project.dart';
import 'title.dart';

/// The storyboard being edited, its decoded media, and preview playback.
class VideoController extends ChangeNotifier {
  VideoController({
    required this.preview,
    this.locker,
    this.storage,
    this.withSound = true,
  });

  final PreviewEngine preview;
  final AssetLocker? locker;
  final AppStorage? storage;

  /// Play sound in previews (off in tests).
  final bool withSound;

  Project project = Project();
  final media = <String, Media>{};
  final titles = <String, VideoFrame>{};
  final failed = <String, String>{};
  final _drawn = <String>{};
  final _loading = <String>{};

  double position = 0;
  bool playing = false;
  ui.Image? image;
  int _imageVersion = 0;

  Timer? _saveTimer, _playTimer;
  final _clock = Stopwatch();
  double _playFrom = 0;
  ClipPlayer? _player;
  bool _soundDirty = true;
  File? _soundFile;

  static const _file = 'project.json';

  double get duration => project.duration;
  bool get tooLong => duration > maxSeconds + 1e-6;

  Future<void> init() async {
    await preview.start();
    try {
      final j = await storage?.readJson(_file);
      if (j != null) {
        project = Project.fromJson(j);
      }
    } catch (_) {
      // A broken save: start fresh.
    }
    await _projectChanged(save: false);
    for (final s in project.scenes) {
      if (s.asset != null) {
        unawaited(loadAsset(s.asset!));
      }
    }
    if (project.music != null) {
      unawaited(loadAsset(project.music!));
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _playTimer?.cancel();
    _player?.dispose();
    preview.dispose();
    image?.dispose();
    super.dispose();
  }

  /// Loads (once) and decodes an Asset Locker item.
  Future<Media?> loadAsset(Map<String, Object?> asset) async {
    final id = asset['id'] as String?;
    if (id == null) {
      return null;
    }
    if (media.containsKey(id)) {
      return media[id];
    }
    if (_loading.contains(id) || locker == null) {
      return null;
    }
    _loading.add(id);
    try {
      final info = AssetInfo.fromJson(asset);
      if (info == null) {
        throw const FormatException('Bad Asset Locker details');
      }
      final bytes = await locker!.read(info);
      if (bytes == null) {
        throw StateError('"${info.name}" is no longer in the Asset Locker');
      }
      final ext = info.extension;
      final m = await runInBackground(_decode, (ext, bytes));
      addMedia(id, m);
      return m;
    } catch (e) {
      failed[id] = '$e';
      notifyListeners();
      return null;
    } finally {
      _loading.remove(id);
    }
  }

  /// Adds already-decoded media (also used by tests).
  void addMedia(String id, Media m) {
    media[id] = m;
    failed.remove(id);
    preview.addMedia(id, m);
    _soundDirty = true;
    notifyListeners();
    unawaited(seek(position));
  }

  Future<void> _projectChanged({bool save = true}) async {
    for (final s in project.scenes) {
      if (s.kind == SceneKind.title) {
        final key = '${s.id}:${s.text}:${s.textColor}:${s.background}';
        if (!_drawn.contains(key)) {
          final f = await renderTitle(s);
          _drawn.add(key);
          titles[s.id] = f;
          preview.setTitle(s.id, f);
        }
      }
      for (final o in s.overlays) {
        if (o.kind == OverlayKind.text && !_drawn.contains(o.textKey)) {
          final f = await renderTextOverlay(o);
          _drawn.add(o.textKey);
          titles[o.id] = f;
          preview.setTitle(o.id, f);
        }
        if (o.asset != null) unawaited(loadAsset(o.asset!));
      }
    }
    preview.setProject(project);
    _soundDirty = true;
    if (position > duration) {
      position = duration;
    }
    notifyListeners();
    if (save) {
      _scheduleSave();
    }
    await seek(position);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(storage?.writeJson(_file, project.toJson())),
    );
  }

  /// Saves now (e.g. before closing).
  Future<void> flush() async {
    _saveTimer?.cancel();
    await storage?.writeJson(_file, project.toJson());
  }

  // ---- Editing ----

  Future<void> edit(void Function(Project p) change) async {
    await stop();
    change(project);
    await _projectChanged();
  }

  Future<void> addScene(Scene s) async {
    await edit((p) {
      s.duration = p.snapped(s.duration);
      p.scenes.add(s);
    });
    if (s.asset != null) {
      final m = await loadAsset(s.asset!);
      // Clips start out as long as they are.
      if (m is ClipMedia && s.kind == SceneKind.clip) {
        await edit(
          (p) =>
              s.duration = _fitBeats(p, m.clip.length.clamp(0.5, maxSeconds)),
        );
      } else if (m is AnimMedia && m.frames.length > 1) {
        await edit(
          (p) => s.duration = p.snapped(
            (m.total * (m.total < 1.5 ? 2 : 1)).clamp(1.0, 10.0),
          ),
        );
      }
    }
  }

  /// Turns beat snapping on (rounding every scene to whole beats) or off.
  Future<void> setSnap(bool on) => edit((p) {
    p.snap = on;
    for (final s in p.scenes) {
      s.duration = p.snapped(s.duration);
    }
  });

  Future<void> updateScene(Scene s, void Function(Scene s) change) =>
      edit((_) => change(s));

  Future<void> removeScene(Scene s) => edit((p) => p.scenes.remove(s));

  Future<void> duplicateScene(Scene s) => edit(
    (p) => p.scenes.insert(p.scenes.indexOf(s) + 1, s.copy(newId: true)),
  );

  /// Moves a scene; [to] is its index after the move.
  Future<void> moveScene(int from, int to) => edit((p) {
    final s = p.scenes.removeAt(from);
    p.scenes.insert(to.clamp(0, p.scenes.length), s);
  });

  Future<void> setMusic(Map<String, Object?>? asset) async {
    await edit((p) {
      p.music = asset;
      p.musicStart = 0;
      // Sample Pad mixes know their tempo.
      final extra = asset?['extra'];
      final bpm = extra is Map ? extra['bpm'] : null;
      if (bpm is num && bpm >= 30 && bpm <= 300) p.bpm = bpm.toDouble();
    });
    if (asset != null) {
      await loadAsset(asset);
    }
  }

  Future<void> newProject() async {
    await edit((p) {
      p
        ..scenes.clear()
        ..music = null
        ..name = 'My video'
        ..musicStart = 0;
    });
    position = 0;
    await seek(0);
  }

  /// Start time of the scene under the playhead.
  int get currentScene =>
      project.scenes.isEmpty ? -1 : project.sceneAt(position).$1;

  // ---- Preview ----

  Future<void> seek(double t) async {
    position = t.clamp(0.0, duration);
    await _show(position);
    notifyListeners();
  }

  Future<void> _show(double t) async {
    if (project.scenes.isEmpty) {
      image?.dispose();
      image = null;
      return;
    }
    final f = await preview.render(t);
    if (f == null) {
      return;
    }
    final v = ++_imageVersion;
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      f.bgraBytes,
      f.width,
      f.height,
      ui.PixelFormat.bgra8888,
      c.complete,
    );
    final next = await c.future;
    if (v != _imageVersion) {
      next.dispose();
      return;
    }
    image?.dispose();
    image = next;
    notifyListeners();
  }

  Future<void> play() async {
    if (project.scenes.isEmpty) {
      return;
    }
    if (position >= duration - 0.05) {
      position = 0;
    }
    playing = true;
    notifyListeners();
    if (withSound) {
      await _startSound();
    }
    _playFrom = position;
    _clock
      ..reset()
      ..start();
    _playTimer?.cancel();
    _playTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final t = _playFrom + _clock.elapsedMilliseconds / 1000;
      if (t >= duration) {
        unawaited(stop());
        return;
      }
      position = t;
      unawaited(_show(t));
    });
  }

  Future<void> _startSound() async {
    try {
      if (_soundDirty || _soundFile == null) {
        final p = Project.fromJson(project.toJson());
        final m = Map<String, Media>.of(media);
        final pcm = await runInBackground(_mix, (p, m));
        final dir = await Directory.systemTemp.createTemp('lofi');
        final f = File('${dir.path}${Platform.pathSeparator}preview.wav');
        await f.writeAsBytes(
          buildWav(
            const WavFormat(sampleRate: mixRate, channels: 2),
            pcm.buffer.asUint8List(),
          ),
        );
        final old = _soundFile;
        _soundFile = f;
        _soundDirty = false;
        _player ??= ClipPlayer();
        await _player!.load(f);
        if (old != null) {
          unawaited(
            old.parent.delete(recursive: true).catchError((_) => old.parent),
          );
        }
      }
      await _player?.play(from: position);
    } catch (_) {
      // Picture without sound is still useful.
    }
  }

  Future<void> stop() async {
    if (!playing) {
      return;
    }
    playing = false;
    _playTimer?.cancel();
    _clock.stop();
    await _player?.stop();
    notifyListeners();
  }
}

Media _decode((String, Uint8List) a) => decodeMedia(a.$1, a.$2);
Int16List _mix((Project, Map<String, Media>) a) => mixAudio(a.$1, a.$2);

/// [seconds] in whole beats when snapping, never longer than [seconds]
/// (a clip can't play past its end).
double _fitBeats(Project p, double seconds) {
  if (!p.snap) return seconds;
  final beats = (seconds / p.beat).floor();
  return beats >= 1 ? beats * p.beat : seconds;
}
