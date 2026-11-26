/// The pixel paint behind the save manager's buttons and title: rainbow
/// blobs that thin out before every edge, the same every time for a given
/// seed (ported from the PC's PaintSplash.gd).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

import 'art_images.dart';
import 'look.dart';

abstract final class PaintSplash {
  static const w = 104, h = 30;
  static const bigBlobs = 27, specks = 40;

  static final _made = <int, Pixels>{};

  /// The paint for [seed] (kept: there are only a handful in use).
  static Pixels pixels(int seed) => _made[seed] ??= make(seed);

  /// A fresh picture for [number]: 104×30 pixels, see-through around.
  static Pixels make(int number) {
    final rng = math.Random(number * 7919 + 17);
    double range(double a, double b) => a + rng.nextDouble() * (b - a);
    // x, y, radius, hue
    final blobs = <(double, double, double, double)>[
      for (var i = 0; i < bigBlobs; i++)
        (
          w * range(0.15, 0.85),
          h * range(0.33, 0.67),
          h * range(0.13, 0.32),
          rng.nextDouble() * 360,
        ),
      for (var i = 0; i < specks; i++)
        (
          w * range(0.04, 0.96),
          h * range(0.07, 0.93),
          1 + rng.nextDouble() * h * 0.07,
          rng.nextDouble() * 360,
        ),
    ];
    final out = Pixels(w, h);
    for (var y = 0; y < h; y++) {
      final near = [
        for (final b in blobs)
          if ((y - b.$2).abs() < b.$3 + 1.6) b,
      ];
      for (var x = 0; x < w; x++) {
        var best = 0.0, hue = 0.0;
        for (final b in near) {
          final reach = b.$3 + 1.6;
          final dx = (x - b.$1) * 0.75;
          if (dx.abs() >= reach) continue;
          final dy = y - b.$2;
          final v =
              b.$3 + rng.nextDouble() * 1.6 - math.sqrt(dx * dx + dy * dy);
          if (v > best) {
            best = v;
            hue = b.$4;
          }
        }
        final edge = math.min(math.min(x, y), math.min(w - 1 - x, h - 1 - y));
        best -= math.max(0, 3 - edge) * 2.2;
        if (best <= 0) continue;
        final at = (x / w * 300 + hue * 0.22 + number * 47) % 360;
        final light = best > h * 0.13 ? 0.46 : 0.58;
        final c = hsl((at / 14).floorToDouble() * 14 / 360, 0.92, light);
        out.set(x, y, c.$1, c.$2, c.$3);
      }
    }
    return out;
  }

  /// HSL (0..1 each) to 8-bit RGB.
  static (int, int, int) hsl(double hue, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final hp = hue * 6;
    final x = c * (1 - (hp % 2 - 1).abs());
    final (r, g, b) = switch (hp.floor() % 6) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    final m = l - c / 2;
    int k(double v) => ((v + m) * 255).round().clamp(0, 255);
    return (k(r), k(g), k(b));
  }
}

/// Draws the paint for [seed] stretched over the whole box, as big pixels,
/// with the PC's soft glow round it when [chosen].
class _SplashPainter extends CustomPainter {
  _SplashPainter(this.seed, this.chosen, this.alpha)
    : super(repaint: ArtImages.loaded);

  final int seed;
  final bool chosen;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    if (chosen) {
      // The PC grows the glow 34/26 px round a ~112 px tall button.
      final k = size.height / 112;
      Look.glow(
        canvas,
        Rect.fromLTRB(
          r.left - 34 * k,
          r.top - 26 * k,
          r.right + 34 * k,
          r.bottom + 26 * k,
        ),
        alpha: 0.8 * alpha,
      );
    }
    final img = ArtImages.peek(PaintSplash.pixels(seed));
    if (img == null) return;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      r,
      Paint()
        ..filterQuality = ui.FilterQuality.none
        ..color = Color.fromRGBO(255, 255, 255, alpha),
    );
  }

  @override
  bool shouldRepaint(_SplashPainter old) =>
      old.seed != seed || old.chosen != chosen || old.alpha != alpha;
}

/// A rainbow paint-splash button with heavy outlined words; [selected]
/// glows and turns the words yellow, like the PC's chosen button.
class PaintButton extends StatelessWidget {
  const PaintButton(
    this.label, {
    super.key,
    this.selected = false,
    this.onTap,
    this.seed = 1,
    this.width = 220,
    this.height = 64,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Which paint (the PC numbers its buttons 1, 2, 3...).
  final int seed;
  final double width, height;

  /// Off: drawn faint (the PC's 0.25 alpha while a menu is over it).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final alpha = enabled ? 1.0 : 0.25;
    final grow = selected ? 1.04 : 1.0;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: width,
          height: height,
          child: Transform.scale(
            scale: grow,
            child: CustomPaint(
              painter: _SplashPainter(seed, selected, alpha),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.06),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Opacity(
                      opacity: alpha,
                      child: OutlinedText(
                        label,
                        size: height * 0.32,
                        color: selected ? Look.yellow : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page title on its splash of paint ("MEMORY CARDS").
class PaintTitle extends StatelessWidget {
  const PaintTitle(
    this.text, {
    super.key,
    this.width = 300,
    this.height = 72,
    this.seed = 0,
    this.color = Colors.white,
  });

  final String text;
  final double width, height;
  final int seed;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    label: text,
    child: SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SplashPainter(seed, false, 1),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: width * 0.07),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: OutlinedText(text, size: height * 0.36, color: color),
            ),
          ),
        ),
      ),
    ),
  );
}
