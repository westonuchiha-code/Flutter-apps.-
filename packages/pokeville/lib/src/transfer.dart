// The transfer, played whenever a Pokémon moves between a game and
// Pokéville: ported from the PC's PokeTransfer.gd (the approved mock-up,
// mockups/transfer.html). The ball drops on the game's pad and rattles,
// sparks, it turns to light, rides the link cable trailing bubbles, comes
// down at the other end, a ball forms and the Pokémon pops out. The game's
// end is its console (Game Boy, Game Boy Color, GBA). Drawn on a 480x270
// pixel canvas, blown up to fit. It waits at the cable's end until the save
// has really changed ([Transfer.done]); if the change failed, the Pokémon
// rides back. A / B skip. The PC's timing, about 3x quicker (~2 s).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'look.dart';
import 'sprites.dart';
import 'store.dart';

/// One transfer's state; [advance] moves it on.
class Transfer {
  Transfer({
    required this.mon,
    required this.console,
    required this.toBox,
    required this.gameName,
    required this.label,
  });

  /// The PC's mock-up timing (scene seconds), played [speed] times faster.
  static const speed = 3.4;
  static const holdT = 3.95; // waits here until done()
  static const endT = 6.4;
  static const failS = 1.2; // riding back
  static const failRead = 6.0; // then the message stays this long

  final Mon mon;

  /// gb / gbc / gba.
  final String console;

  /// Game -> Pokéville (else Pokéville -> game).
  final bool toBox;
  final String gameName;

  /// "GOLD · DUDE".
  final String label;

  double t = 0;
  double clock = 0;

  /// 0 waiting, 1 done, -1 failed.
  int result = 0;
  String failText = '';
  double failT = 0;
  bool playing = true;

  /// The save has changed (or couldn't be).
  void done(bool ok, [String why = '']) {
    result = ok ? 1 : -1;
    failText = why;
  }

  /// A / B: hurry it along. It can't pass the waiting point before the
  /// change is really done.
  void skip() {
    if (!playing) return;
    if (result == 0) {
      t = math.max(t, holdT);
    } else if (result < 0) {
      if (failT >= failS) {
        playing = false;
      } else {
        failT = failS;
      }
    } else {
      playing = false;
    }
  }

  /// [dt] real seconds later.
  void advance(double dt) {
    if (!playing) return;
    final d = dt * speed;
    clock += d;
    if (result < 0 && t >= holdT) {
      failT += d;
      if (failT > failS + failRead) playing = false;
    } else {
      t += d;
      if (result == 0 && t > holdT) t = holdT;
      if (t >= endT) playing = false;
    }
  }

  /// The words under the scene now, and how visible (0..1).
  (String, double) get words {
    final name =
        (mon.egg
                ? 'the Egg'
                : (mon.nickname.isNotEmpty
                      ? mon.nickname
                      : (mon.name.isEmpty ? 'it' : mon.name)))
            .toUpperCase();
    final where = toBox ? 'Pokéville' : gameName;
    if (result < 0 && failT > 0) {
      return ('$name came back. $failText', (failT * 4 / speed).clamp(0, 1));
    }
    if (t > 5.2) {
      return (
        toBox ? 'Pokéville received $name!' : '$name went to $where!',
        ((t - 5.2) * 4).clamp(0, 1),
      );
    }
    if (t < 1.2) {
      return ('Sending $name to $where...', 1 - seg(t, 0.9, 1.2));
    }
    return ('', 0);
  }

  static double seg(double t, double a, double b) {
    final x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }
}

const _ink = Color(0xFF2B3070);
const _path = [
  Offset(166, 160),
  Offset(192, 160),
  Offset(192, 52),
  Offset(374, 52),
  Offset(374, 76),
];
const _sendAt = Offset(138, 150);
const _mx = 320.0;
const _my = 84.0;
const _boxPad = Offset(_mx + 54, _my + 58);

double _rnd(double n) {
  final x = math.sin(n * 12.9898) * 43758.5453;
  return x - x.floorToDouble();
}

/// Paints [tr] over the whole [size] (screen dp). [wide]: the PC's
/// 1920x1080 layout scaled by [scale] at [offset] (the scene and the words
/// where the PC puts them); else the scene fits the width and the words go
/// under it.
void paintTransfer(
  Canvas canvas,
  Size size,
  Transfer tr,
  PokeSprites sprites, {
  required bool wide,
  double scale = 1,
  Offset offset = Offset.zero,
}) {
  canvas.drawRect(Offset.zero & size, Paint()..color = Look.bg);
  final double px;
  final Offset origin;
  if (wide) {
    px = scale * 4;
    origin = offset;
  } else {
    px = math.min(size.width / 480, (size.height - 120) / 270);
    origin = Offset(
      (size.width - 480 * px) / 2,
      math.max(8, (size.height - 120 - 270 * px) / 2),
    );
  }
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  canvas.scale(px);
  canvas.clipRect(const Rect.fromLTWH(0, 0, 480, 270));
  _Scene(canvas, tr, sprites).draw();
  canvas.restore();
  // the words
  final k = Pen(canvas, u: wide ? scale : 0.5);
  Offset at(double x, double y) => wide
      ? Offset(x * scale + offset.dx, y * scale + offset.dy)
      : origin + Offset(x / 4 * px, y / 4 * px);
  final lfs = wide ? 34 * scale : math.max(11.0, 34 * px / 4);
  void tagAt(String s, Offset p) {
    final w = k.width(s, Face.title, lfs) + lfs * 1.4;
    final r = Rect.fromLTWH(p.dx, p.dy, w, lfs * 1.9);
    k.panel(r, fill: Look.white, radius: 20 * lfs / 34, rings: false);
    k.say(
      s,
      Offset(r.left + lfs * 0.7, r.center.dy + lfs * 0.36),
      Face.title,
      lfs,
      Look.ink,
    );
  }

  tagAt(tr.label, at(110, 670));
  tagAt('POKéVILLE', at(1420, 822));
  final (msg, a) = tr.words;
  if (a > 0) {
    final Rect r;
    if (wide) {
      r = Rect.fromLTWH(
        400 * scale + offset.dx,
        892 * scale + offset.dy,
        1120 * scale,
        150 * scale,
      );
    } else {
      final top = origin.dy + 270 * px + 10;
      r = Rect.fromLTWH(
        12,
        top,
        size.width - 24,
        math.min(96, size.height - top - 8),
      );
    }
    final ra = Rect.fromLTRB(r.left, r.top, r.right, math.max(r.bottom, r.top));
    canvas.saveLayer(
      ra.inflate(8),
      Paint()..color = Color.fromRGBO(0, 0, 0, a.toDouble()),
    );
    k.panel(ra, radius: 16);
    var fs = wide ? 46 * scale : 17.0;
    if (k.width(msg, Face.title, fs) > ra.width - fs * 1.7) {
      fs = wide ? 32 * scale : 13.0;
    }
    final lines = _wrap(k, msg, fs, ra.width - fs * 1.7);
    final lh = fs * 1.22;
    for (var i = 0; i < lines.length; i++) {
      k.say(
        lines[i],
        Offset(
          ra.left + fs * 0.85,
          ra.center.dy + fs * 0.36 + (i - (lines.length - 1) / 2) * lh,
        ),
        Face.title,
        fs,
        Look.ink,
        maxW: ra.width - fs * 1.7,
      );
    }
    canvas.restore();
  }
  k.say(
    tr.result >= 0 ? 'A  skip' : 'A  OK',
    wide
        ? Offset(1880 * scale + offset.dx, 60 * scale + offset.dy)
        : Offset(size.width - 12, 22),
    Face.title,
    wide ? 26 * scale : 12,
    Look.soft,
    align: 2,
  );
}

List<String> _wrap(Pen k, String s, double fs, double w) {
  final out = <String>[];
  var line = '';
  for (final word in s.split(' ')) {
    final next = line.isEmpty ? word : '$line $word';
    if (k.width(next, Face.title, fs) > w && line.isNotEmpty) {
      out.add(line);
      line = word;
    } else {
      line = next;
    }
  }
  out.add(line);
  return out;
}

/// The 480x270 scene (PokeTransfer.gd's _scene and its pieces).
class _Scene {
  _Scene(this.c, this.tr, this.sprites);

  final Canvas c;
  final Transfer tr;
  final PokeSprites sprites;
  final _p = Paint();

  void _r(double x, double y, double w, double h, Color col) {
    _p
      ..color = col
      ..style = PaintingStyle.fill;
    c.drawRect(
      Rect.fromLTWH(
        x.roundToDouble(),
        y.roundToDouble(),
        w.roundToDouble(),
        h.roundToDouble(),
      ),
      _p,
    );
  }

  void _disc(double cx, double cy, int r, Color col) {
    _p
      ..color = col
      ..style = PaintingStyle.fill;
    for (var y = -r; y <= r; y++) {
      final w = math.sqrt(r * r - y * y).round();
      c.drawRect(
        Rect.fromLTWH(
          (cx - w).roundToDouble(),
          (cy + y).roundToDouble(),
          w * 2.0,
          1,
        ),
        _p,
      );
    }
  }

  void _frame(double x, double y, double w, double h, Color fill) {
    _r(x, y, w, h, _ink);
    _r(x + 2, y + 2, w - 4, h - 4, fill);
  }

  ui.Image? get _monImage =>
      tr.mon.egg ? null : sprites.image(tr.mon.species, tr.mon.shiny);

  void _image(ui.Image img, Rect dst, [double alpha = 1]) {
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()
        ..filterQuality = FilterQuality.none
        ..color = Color.fromRGBO(255, 255, 255, alpha),
    );
  }

  void draw() {
    final t = tr.t;
    final seg = Transfer.seg;
    _wash(tr.clock);
    final lit = t > 2.0 && t < 4.3 && tr.failT < Transfer.failS;
    _cable(lit);
    final port = _console();
    _sendPad(110, 158);
    _r(port.dx, port.dy, 106 - port.dx + 4, 4, _ink);
    _r(106, port.dy, 4, 156 - port.dy, _ink);
    _r(106, 156, 8, 4, _ink);
    final src = tr.toBox ? _sendAt : _boxPad;
    final dst = tr.toBox ? _boxPad : _sendAt;
    final charging = t > 1.1 && t < 2.1;
    final arriving = t > 4.1 && t < 4.9 && tr.result > 0;
    var glow = 0.0;
    if ((arriving && tr.toBox) || (charging && !tr.toBox)) {
      glow = 0.5 + 0.5 * math.sin(t * 40);
    } else if (t > 4.9 && tr.toBox && tr.result > 0) {
      glow = 0.3;
    }
    _machine(_mx, _my, glow);
    final img = _monImage;
    // 1) the ball drops on its pad, rattles, sparks and turns to light
    if (t < 2.05) {
      final drop = seg(t, 0, 0.45);
      final bounce = t > 0.45 && t < 0.7
          ? math.sin((t - 0.45) / 0.25 * math.pi) * 6
          : 0.0;
      final wob = t > 0.7 && t < 1.2 ? math.sin(t * 38) * 0.35 : 0.0;
      _ball(src.dx, src.dy - 60 * (1 - drop) - bounce, 1 - seg(t, 1.6, 2), wob);
      if (charging) {
        _sparks(src.dx, src.dy, t, 0);
        _orb(src.dx, src.dy, (6 + 8 * seg(t, 1.5, 2)).round(), seg(t, 1.3, 2));
      }
    }
    // 2) along the cable (and back if the change failed)
    if (t >= 2.0 && (t <= 4.25 || tr.result < 0)) {
      var pr = seg(t, 2.05, 4.15);
      if (tr.result < 0 && tr.failT > 0) {
        pr *= 1 - seg(tr.failT, 0, Transfer.failS);
      }
      if (tr.failT < Transfer.failS) {
        final along = tr.toBox ? pr : 1 - pr;
        var trail = tr.toBox ? -1.0 : 1.0;
        if (tr.result < 0 && tr.failT > 0) trail = -trail;
        for (var i = 1; i < 7; i++) {
          final q = (along + trail * i * 0.025).clamp(0.0, 1.0);
          final b = _cablePoint(q);
          _disc(
            b.dx,
            b.dy - 2 - i * 2 - math.sin(tr.clock * 9 + i) * 2,
            2 + i % 2,
            Color.fromRGBO(255, 255, 255, 0.55 - i * 0.08),
          );
        }
        var at = _cablePoint(along);
        if (tr.result == 0 && t >= Transfer.holdT) {
          at = at.translate(0, math.sin(tr.clock * 6) * 1.5);
        }
        _disc(at.dx, at.dy, 14, _ink);
        _disc(at.dx, at.dy, 12, const Color(0xFFFFFDF4));
        if (img != null) {
          _image(
            img,
            Rect.fromLTWH(
              (at.dx - 18).roundToDouble(),
              (at.dy - 22).roundToDouble(),
              36,
              36,
            ),
          );
        }
      } else {
        _ball(
          src.dx,
          src.dy,
          seg(tr.failT, Transfer.failS, Transfer.failS + 0.3),
          0,
        );
      }
    }
    if (tr.result <= 0) return;
    // 3) the light comes down; the ball forms on the other pad
    if (arriving) {
      final fromY = tr.toBox ? _my - 4 : _path[0].dy;
      final fromX = tr.toBox ? dst.dx : _path[0].dx;
      final q = seg(t, 4.1, 4.6);
      _orb(
        fromX + (dst.dx - fromX) * q,
        tr.toBox ? _my - 4 + 64 * q : fromY + (dst.dy - fromY) * q,
        (14 - 8 * seg(t, 4.5, 4.9)).round(),
        1 - seg(t, 4.75, 4.9),
      );
      _sparks(dst.dx, dst.dy - 2, t, 9);
    }
    if (t > 4.6) {
      _ball(
        dst.dx,
        dst.dy,
        seg(t, 4.6, 4.9),
        t < 5.1 ? math.sin(t * 40) * 0.25 : 0,
      );
    }
    // 4) out it pops
    if (t > 5.05) {
      final pop = seg(t, 5.05, 5.35);
      _disc(
        dst.dx,
        dst.dy - 24,
        (30 * pop).round(),
        Color.fromRGBO(255, 255, 255, 0.6 * (1 - seg(t, 5.3, 5.6))),
      );
      final s = (72 * pop).roundToDouble();
      if (img != null && s > 0) {
        _image(
          img,
          Rect.fromLTWH(
            (dst.dx - s / 2).roundToDouble(),
            (dst.dy - 18 - s).roundToDouble(),
            s,
            s,
          ),
        );
      } else if (tr.mon.egg && s > 0) {
        Pen(c).egg(Offset(dst.dx, dst.dy - 18 - s / 2), s * 0.5);
      }
    }
  }

  void _wash(double t) {
    c.drawRect(
      const Rect.fromLTWH(0, 0, 480, 270),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(480, 270),
          const [Color(0xFFDFF2FF), Color(0xFFF7F2E8), Color(0xFFFFE1EC)],
          const [0, 0.5, 1],
        ),
    );
    const cols = [
      Color.fromRGBO(161, 209, 255, 0.35),
      Color.fromRGBO(255, 191, 214, 0.3),
      Color.fromRGBO(199, 240, 191, 0.3),
    ];
    for (var i = 0; i < 6; i++) {
      final x =
          (_rnd(i.toDouble()) * 520 + t * 6 * (i.isOdd ? 1 : -1)) % 520 - 20;
      _disc(
        x,
        30 + _rnd(i + 9) * 210,
        (30 + _rnd(i + 3) * 30).round(),
        cols[i % 3],
      );
    }
  }

  void _sendPad(double x, double y) {
    _frame(x, y, 56, 8, const Color(0xFF7D8FD8));
    _frame(x + 6, y + 8, 44, 18, const Color(0xFFCFD6FF));
  }

  // The Box machine: desk, screen on top, two pipes, a pad with a tube.
  void _machine(double x, double y, double glow) {
    _frame(x - 6, y + 70, 120, 50, const Color(0xFFCFD6FF));
    _r(x - 2, y + 96, 112, 4, const Color(0xFF9AA6E8));
    _disc(x + 10, y + 108, 6, const Color(0xFFE8463C));
    _disc(x + 98, y + 108, 6, const Color(0xFFE8463C));
    _frame(x + 22, y - 8, 64, 48, const Color(0xFF9AB8FF));
    _r(
      x + 28,
      y - 2,
      52,
      36,
      glow > 0
          ? Color.fromARGB(
              255,
              160 + (glow * 90).toInt(),
              210 + (glow * 40).toInt(),
              255,
            )
          : const Color(0xFF5F86E8),
    );
    _frame(x - 12, y + 6, 36, 10, const Color(0xFFA9C9FF));
    _frame(x + 84, y + 6, 36, 10, const Color(0xFFA9C9FF));
    _frame(x - 16, y + 6, 10, 70, const Color(0xFFA9C9FF));
    _frame(x + 114, y + 6, 10, 70, const Color(0xFFA9C9FF));
    _frame(x + 34, y + 40, 40, 32, const Color(0xFFE7ECFF));
    _r(
      x + 38,
      y + 44,
      32,
      24,
      Color.fromRGBO(190, 230, 255, 0.35 + glow * 0.5),
    );
    _frame(x + 26, y + 70, 56, 8, const Color(0xFF7D8FD8));
  }

  // Right angles, like Red/Blue's trade cable. Yellow while something rides.
  void _cable(bool lit) {
    for (var i = 1; i < _path.length; i++) {
      final a = _path[i - 1], b = _path[i];
      final x = math.min(a.dx, b.dx) - 2;
      final y = math.min(a.dy, b.dy) - 2;
      final w = (b.dx - a.dx).abs() + 4;
      final h = (b.dy - a.dy).abs() + 4;
      _r(x - 1, y - 1, w + 2, h + 2, _ink);
      _r(x, y, w, h, lit ? const Color(0xFFFFD54A) : const Color(0xFFE8463C));
      _r(
        x + 1,
        y + 1,
        w - 2,
        h - 2,
        lit ? const Color(0xFFFFF3B0) : const Color(0xFFFFB03A),
      );
    }
  }

  Offset _cablePoint(double q) {
    var total = 0.0;
    for (var i = 1; i < _path.length; i++) {
      total += (_path[i] - _path[i - 1]).distance;
    }
    var d = q * total;
    for (var i = 1; i < _path.length; i++) {
      final l = (_path[i] - _path[i - 1]).distance;
      if (d <= l) return Offset.lerp(_path[i - 1], _path[i], d / l)!;
      d -= l;
    }
    return _path.last;
  }

  void _ball(double cx, double cy, double alpha, double wob) {
    if (alpha <= 0) return;
    c.save();
    c.translate(cx.roundToDouble(), cy.roundToDouble());
    c.rotate(wob);
    final b = sprites.ballImage;
    if (b != null) {
      _image(b, const Rect.fromLTWH(-15, -15, 30, 30), alpha);
    } else {
      _disc(0, 0, 11, _ink.withValues(alpha: alpha));
      _disc(0, 0, 9, Color.fromRGBO(232, 69, 61, alpha));
      _r(-9, 0, 18, 9, Color.fromRGBO(255, 255, 255, alpha));
      _disc(0, 0, 3, _ink.withValues(alpha: alpha));
    }
    c.restore();
  }

  void _orb(double cx, double cy, int r, double a) {
    if (a <= 0) return;
    _disc(cx, cy, r + 4, Color.fromRGBO(191, 232, 255, a * 0.5));
    _disc(cx, cy, r, Color.fromRGBO(255, 255, 255, a));
  }

  void _bolt(Offset a, Offset b, double seed, Color col) {
    final path = Path()..moveTo(a.dx, a.dy);
    for (var i = 1; i < 5; i++) {
      final q = Offset.lerp(a, b, i / 5)!;
      path.lineTo(
        q.dx + (_rnd(seed + i) - 0.5) * 12,
        q.dy + (_rnd(seed + i * 7) - 0.5) * 12,
      );
    }
    path.lineTo(b.dx, b.dy);
    c.drawPath(
      path,
      Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _sparks(double cx, double cy, double t, int k) {
    for (var i = 0; i < 5; i++) {
      final a = i / 5 * 2 * math.pi + t * 3;
      _bolt(
        Offset(cx, cy),
        Offset(cx + math.cos(a) * 22, cy + math.sin(a) * 18),
        (t * 20).floorToDouble() * 31 + i * 5 + k,
        i.isOdd ? Look.white : const Color(0xFF9AE6FF),
      );
    }
  }

  /// The game's console, left of the pad; returns where its cable comes out.
  Offset _console() => switch (tr.console) {
    'gb' => _handheld(
      30,
      74,
      const Color(0xFFC9C9C0),
      const Color(0xFF8BAC0F),
      const Color(0xFFA3195B),
      const Color(0xFF6B6B80),
    ),
    'gba' => _gba(10, 96),
    _ => _handheld(
      30,
      74,
      const Color(0xFFF3F3F6),
      const Color(0xFF8FD16A),
      const Color(0xFFD93A3A),
      const Color(0xFF3A3F66),
    ),
  };

  Offset _handheld(
    double x,
    double y,
    Color body,
    Color screen,
    Color btn,
    Color bezel,
  ) {
    _frame(x, y, 64, 92, body);
    _frame(x + 8, y + 8, 48, 36, bezel);
    _r(x + 12, y + 12, 40, 28, screen);
    _r(x + 10, y + 52, 6, 18, _ink);
    _r(x + 4, y + 58, 18, 6, _ink);
    _disc(x + 46, y + 56, 4, btn);
    _disc(x + 54, y + 64, 4, btn);
    for (var i = 0; i < 3; i++) {
      _r(x + 40 + i * 5, y + 78, 2, 8, const Color(0xFF9AA0C8));
    }
    _r(x + 64, y + 20, 6, 10, _ink);
    return Offset(x + 70, y + 24);
  }

  Offset _gba(double x, double y) {
    _frame(x, y, 92, 54, const Color(0xFF5B4FC4));
    _r(x + 4, y - 2, 18, 4, _ink);
    _r(x + 70, y - 2, 18, 4, _ink);
    _frame(x + 24, y + 8, 44, 36, const Color(0xFF3A3F66));
    _r(x + 28, y + 12, 36, 28, const Color(0xFF9AD0FF));
    _r(x + 10, y + 20, 4, 14, _ink);
    _r(x + 5, y + 25, 14, 4, _ink);
    _disc(x + 78, y + 22, 3, const Color(0xFFC9C9E8));
    _disc(x + 84, y + 30, 3, const Color(0xFFC9C9E8));
    _r(x + 92, y + 20, 6, 10, _ink);
    return Offset(x + 98, y + 24);
  }
}
