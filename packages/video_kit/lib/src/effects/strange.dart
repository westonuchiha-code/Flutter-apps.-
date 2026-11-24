// Strange video machines and techniques.
import 'dart:math' as math;

import '../effect.dart';
import '../frame.dart';

/// Rutt/Etra scan processor (1970s video synthesizer): brightness bends each
/// scan line up, turning the picture into a landscape of glowing lines.
class RuttEtra extends VideoEffect {
  @override
  String get id => 'ruttetra';
  @override
  String get name => 'Rutt/Etra scan processor';
  @override
  String get about =>
      'Brightness lifts each scan line, drawn as glowing lines on black.';
  @override
  (int, int) inputSize(int inW, int inH) => byWidth(inW, inH, 160);
  @override
  List<Knob> get knobs => const [
    Knob('height', 'Lift', value: 0.5),
    Knob('lines', 'Line spacing', min: 2, max: 10, value: 4),
    Knob('colour', 'Lines', value: 0, choices: ['Green', 'Picture colour']),
  ];

  @override
  VideoFrame process(VideoFrame input, double time) {
    const scale = 2;
    final w = input.width * scale, h = input.height * scale;
    final out = VideoFrame(w, h)..pixels.fillRange(0, w * h, 0xFF000000);
    final lift = knob('height') * h * 0.35;
    final step = knob('lines').round().clamp(2, 10);
    final natural = knob('colour') >= 0.5;

    void plot(int x, int y, int c) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final o = out.pixels[y * w + x];
      // Additive, like a phosphor drawn twice.
      int add(int a, int b) => math.min(255, a + b);
      out.pixels[y * w + x] =
          0xFF000000 |
          (add((o >> 16) & 255, (c >> 16) & 255) << 16) |
          (add((o >> 8) & 255, (c >> 8) & 255) << 8) |
          add(o & 255, c & 255);
    }

    for (var row = 0; row < input.height; row += step) {
      int? px, py;
      for (var x = 0; x < input.width; x++) {
        final c = input.pixels[row * input.width + x];
        final l = lumaOf(c);
        final sx = x * scale,
            sy = (row * scale + h * 0.1 - l / 255 * lift).round();
        final col = natural
            ? c
            : (0xFF000000 | ((l ~/ 3) << 16) | (l << 8) | (l ~/ 3));
        if (px != null) {
          // Line from the previous point.
          final steps = math.max((sx - px).abs(), (sy - py!).abs());
          for (var k = 0; k <= steps; k++) {
            plot(
              px + ((sx - px) * k / math.max(1, steps)).round(),
              py + ((sy - py) * k / math.max(1, steps)).round(),
              col,
            );
          }
        }
        px = sx;
        py = sy;
      }
    }
    return out;
  }
}

/// Video feedback: a camera pointed at its own screen. The picture repeats
/// into a tunnel that zooms, turns and smears.
class VideoFeedback extends VideoEffect {
  VideoFrame? _prev;

  @override
  String get id => 'feedback';
  @override
  String get name => 'Video feedback';
  @override
  String get about =>
      'A camera filming its own screen: an endless zooming, turning tunnel.';
  @override
  (int, int) inputSize(int inW, int inH) => byWidth(inW, inH, 240);
  @override
  List<Knob> get knobs => const [
    Knob('zoom', 'Zoom', value: 0.4),
    Knob('turn', 'Turn', value: 0.3),
    Knob('keep', 'Trail length', value: 0.7),
  ];

  @override
  void reset() => _prev = null;

  @override
  VideoFrame process(VideoFrame input, double time) {
    final w = input.width, h = input.height;
    final prev = _prev ?? input;
    final out = VideoFrame(w, h);
    final zoom = 1.0 + knob('zoom') * 0.12;
    final turn = (knob('turn') - 0.5) * 0.2;
    final keep = 0.4 + knob('keep') * 0.55;
    final ca = math.cos(turn) / zoom, sa = math.sin(turn) / zoom;
    final cx = w / 2, cy = h / 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x - cx, dy = y - cy;
        final sx = (cx + dx * ca - dy * sa).round(),
            sy = (cy + dx * sa + dy * ca).round();
        final f = (sx >= 0 && sy >= 0 && sx < w && sy < h)
            ? prev.pixels[sy * w + sx]
            : 0xFF000000;
        final c = input.pixels[y * w + x];
        // The screen's own glow: the brighter of camera and screen wins,
        // with the screen slowly fading.
        int mix(int shift) {
          final a = (c >> shift) & 255,
              b = (((f >> shift) & 255) * keep).round();
          return math.max(a, b);
        }

        out.pixels[y * w + x] =
            0xFF000000 | (mix(16) << 16) | (mix(8) << 8) | mix(0);
      }
    }
    return _prev = out;
  }
}

/// Slit-scan / time displacement: every row comes from a different moment,
/// so movement bends and stretches like rubber.
class SlitScan extends VideoEffect {
  final _history = <VideoFrame>[];

  @override
  String get id => 'slitscan';
  @override
  String get name => 'Slit-scan';
  @override
  String get about =>
      'Each row from a different moment: movement bends like rubber.';
  @override
  (int, int) inputSize(int inW, int inH) => byWidth(inW, inH, 240);
  @override
  List<Knob> get knobs => const [
    Knob(
      'delay',
      'Time across the picture (frames)',
      min: 4,
      max: 60,
      value: 30,
    ),
    Knob(
      'direction',
      'Direction',
      value: 0,
      choices: ['Top to bottom', 'Left to right'],
    ),
  ];

  @override
  void reset() => _history.clear();

  @override
  VideoFrame process(VideoFrame input, double time) {
    final n = knob('delay').round().clamp(4, 60);
    _history.add(input);
    while (_history.length > n) {
      _history.removeAt(0);
    }
    final w = input.width, h = input.height;
    final out = VideoFrame(w, h);
    final across = knob('direction') >= 0.5;
    final len = _history.length;
    if (!across) {
      for (var y = 0; y < h; y++) {
        final f = _history[len - 1 - (y * (len - 1) ~/ math.max(1, h - 1))];
        out.pixels.setRange(y * w, (y + 1) * w, f.pixels, y * w);
      }
    } else {
      for (var x = 0; x < w; x++) {
        final f = _history[len - 1 - (x * (len - 1) ~/ math.max(1, w - 1))];
        for (var y = 0; y < h; y++) {
          out.pixels[y * w + x] = f.pixels[y * w + x];
        }
      }
    }
    return out;
  }
}

/// Slow-scan TV (as used by radio hams and on space missions): the picture
/// arrives one line at a time over many seconds, with radio noise and a
/// slant when the timing drifts.
class SlowScanTv extends VideoEffect {
  VideoFrame? _screen;
  double _line = 0;
  double _lastTime = 0;
  int _picture = 0;

  @override
  String get id => 'sstv';
  @override
  String get name => 'Slow-scan TV';
  @override
  String get about =>
      'Pictures sent by radio, painted line by line over seconds, with noise and slant.';
  @override
  (int, int) inputSize(int inW, int inH) => (160, 120);
  @override
  List<Knob> get knobs => const [
    Knob('seconds', 'Seconds per picture', min: 3, max: 36, value: 8),
    Knob('noise', 'Radio noise', value: 0.25),
    Knob('slant', 'Timing drift', value: 0.2),
  ];

  @override
  void reset() {
    _screen = null;
    _line = 0;
    _picture = 0;
  }

  @override
  VideoFrame process(VideoFrame input, double time) {
    final screen = _screen ??= VideoFrame(160, 120);
    final dt = (time - _lastTime).clamp(0, 0.5);
    _lastTime = time;
    final from = _line.floor();
    _line += dt * 120 / knob('seconds');
    final to = math.min(_line.floor(), 120);
    final noise = knob('noise');
    final slant = (knob('slant') - 0.5) * 0.6;
    final rnd = math.Random(_picture * 977 + from);
    for (var y = from; y < to; y++) {
      final shift =
          (y * slant + (rnd.nextDouble() < noise * 0.05 ? rnd.nextInt(30) : 0))
              .round();
      for (var x = 0; x < 160; x++) {
        final c = input.pixels[y * 160 + ((x - shift) % 160 + 160) % 160];
        final n = (rnd.nextDouble() - 0.5) * noise * 120;
        // Colour rides on audio tones: noise hits channels separately.
        int ch(int v, double k) => (v + n * k).round().clamp(0, 255);
        screen.pixels[y * 160 + x] =
            0xFF000000 |
            (ch((c >> 16) & 255, 1) << 16) |
            (ch((c >> 8) & 255, 0.6) << 8) |
            ch(c & 255, 1.3);
      }
    }
    if (_line >= 120) {
      _line = 0;
      _picture++;
    }
    final out = screen.copy();
    // The scanning line itself.
    final y = _line.floor().clamp(0, 119);
    for (var x = 0; x < 160; x++) {
      out.pixels[y * 160 + x] = 0xFFFFFFFF;
    }
    return out;
  }
}
