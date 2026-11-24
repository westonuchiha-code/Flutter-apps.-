import 'dart:convert';
import 'dart:typed_data';

import 'color.dart';

/// A layer's settings (its pixels live in each frame's cels).
class LayerInfo {
  LayerInfo({required this.name, this.visible = true, this.opacity = 1});
  String name;
  bool visible;
  double opacity;

  LayerInfo copy() => LayerInfo(name: name, visible: visible, opacity: opacity);
}

/// One animation frame: one cel (ARGB pixels) per layer.
class Frame {
  Frame(this.cels, {this.durationMs = 100});
  final List<Uint32List> cels;
  int durationMs;

  Frame copy() => Frame([
    for (final c in cels) Uint32List.fromList(c),
  ], durationMs: durationMs);
}

/// A pixel image with layers and animation frames.
class Sprite {
  Sprite._(this.width, this.height, this.layers, this.frames);

  factory Sprite.blank(int width, int height, {int background = 0}) {
    final cel = Uint32List(width * height);
    if (background != 0) cel.fillRange(0, cel.length, background);
    return Sprite._(
      width,
      height,
      [LayerInfo(name: 'Layer 1')],
      [
        Frame([cel]),
      ],
    );
  }

  static const kind = 'pixel_sprite';
  static const maxSize = 512;

  final int width, height;
  final List<LayerInfo> layers;
  final List<Frame> frames;

  int get pixelCount => width * height;
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  Uint32List cel(int frame, int layer) => frames[frame].cels[layer];

  // ---- Layers ----

  void addLayer(String name, {int at = -1}) {
    final i = at < 0 ? layers.length : at;
    layers.insert(i, LayerInfo(name: name));
    for (final f in frames) {
      f.cels.insert(i, Uint32List(pixelCount));
    }
  }

  void removeLayer(int i) {
    if (layers.length <= 1) return;
    layers.removeAt(i);
    for (final f in frames) {
      f.cels.removeAt(i);
    }
  }

  void moveLayer(int from, int to) {
    final l = layers.removeAt(from);
    layers.insert(to, l);
    for (final f in frames) {
      final c = f.cels.removeAt(from);
      f.cels.insert(to, c);
    }
  }

  void duplicateLayer(int i) {
    layers.insert(i + 1, layers[i].copy()..name = '${layers[i].name} copy');
    for (final f in frames) {
      f.cels.insert(i + 1, Uint32List.fromList(f.cels[i]));
    }
  }

  /// Merges layer [i] into the one below it.
  void mergeDown(int i) {
    if (i <= 0) return;
    for (final f in frames) {
      final top = f.cels[i], bottom = f.cels[i - 1];
      for (var p = 0; p < pixelCount; p++) {
        bottom[p] = blendOver(bottom[p], top[p], layers[i].opacity);
      }
    }
    removeLayer(i);
  }

  // ---- Frames ----

  void addFrame({int after = -1, bool copy = true}) {
    final i = after < 0 ? frames.length - 1 : after;
    final f = copy
        ? frames[i].copy()
        : Frame([
            for (var l = 0; l < layers.length; l++) Uint32List(pixelCount),
          ], durationMs: frames[i].durationMs);
    frames.insert(i + 1, f);
  }

  void removeFrame(int i) {
    if (frames.length > 1) frames.removeAt(i);
  }

  // ---- Output ----

  /// All visible layers of [frame] flattened.
  Uint32List flatten(int frame, {Set<int> hidden = const {}}) {
    final out = Uint32List(pixelCount);
    for (var l = 0; l < layers.length; l++) {
      final info = layers[l];
      if (!info.visible || hidden.contains(l) || info.opacity <= 0) continue;
      final c = frames[frame].cels[l];
      final full = info.opacity >= 1;
      for (var p = 0; p < pixelCount; p++) {
        final v = c[p];
        if (v == 0) continue;
        out[p] = full && alphaOf(v) == 255
            ? v
            : blendOver(out[p], v, info.opacity);
      }
    }
    return out;
  }

  /// Every colour used (opaque ones), most used first.
  List<int> usedColors() {
    final count = <int, int>{};
    for (final f in frames) {
      for (final c in f.cels) {
        for (final v in c) {
          if (alphaOf(v) > 0) count[v] = (count[v] ?? 0) + 1;
        }
      }
    }
    return count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
  }

  Sprite copy() => Sprite._(
    width,
    height,
    [for (final l in layers) l.copy()],
    [for (final f in frames) f.copy()],
  );

  /// New size; the picture stays at the top-left (cropped or padded).
  Sprite resized(int w, int h) {
    final s = Sprite._(w, h, [for (final l in layers) l.copy()], []);
    for (final f in frames) {
      s.frames.add(
        Frame([
          for (final c in f.cels)
            Uint32List(w * h)..setAll(0, [
              for (var y = 0; y < h; y++)
                for (var x = 0; x < w; x++)
                  x < width && y < height ? c[y * width + x] : 0,
            ]),
        ], durationMs: f.durationMs),
      );
    }
    return s;
  }

  // ---- File format ----

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'width': width,
    'height': height,
    'layers': [
      for (final l in layers)
        {'name': l.name, 'visible': l.visible, 'opacity': l.opacity},
    ],
    'frames': [
      for (final f in frames)
        {
          'duration': f.durationMs,
          // Little-endian ARGB words, base64.
          'cels': [
            for (final c in f.cels)
              base64Encode(
                c.buffer.asUint8List(c.offsetInBytes, c.lengthInBytes),
              ),
          ],
        },
    ],
  };

  factory Sprite.fromJson(Object? j) {
    if (j is! Map || j['kind'] != kind) {
      throw const FormatException('Not a Pixel Forge sprite');
    }
    final w = (j['width'] as num).toInt(), h = (j['height'] as num).toInt();
    if (w < 1 || h < 1 || w > maxSize || h > maxSize) {
      throw const FormatException('Bad size');
    }
    final layers = [
      for (final l in (j['layers'] as List?) ?? const [])
        if (l is Map)
          LayerInfo(
            name: (l['name'] as String?) ?? 'Layer',
            visible: l['visible'] != false,
            opacity: ((l['opacity'] as num?) ?? 1).toDouble().clamp(0, 1),
          ),
    ];
    if (layers.isEmpty) layers.add(LayerInfo(name: 'Layer 1'));
    final frames = <Frame>[];
    for (final f in (j['frames'] as List?) ?? const []) {
      if (f is! Map) continue;
      final cels = <Uint32List>[];
      for (var l = 0; l < layers.length; l++) {
        final raw = l < ((f['cels'] as List?)?.length ?? 0)
            ? (f['cels'] as List)[l]
            : null;
        final bytes = raw is String ? base64Decode(raw) : Uint8List(0);
        final cel = Uint32List(w * h);
        if (bytes.length == w * h * 4) {
          cel.setAll(0, Uint8List.fromList(bytes).buffer.asUint32List());
        }
        cels.add(cel);
      }
      frames.add(
        Frame(
          cels,
          durationMs: ((f['duration'] as num?) ?? 100).toInt().clamp(10, 10000),
        ),
      );
    }
    if (frames.isEmpty) {
      frames.add(
        Frame([for (var l = 0; l < layers.length; l++) Uint32List(w * h)]),
      );
    }
    return Sprite._(w, h, layers, frames);
  }
}
