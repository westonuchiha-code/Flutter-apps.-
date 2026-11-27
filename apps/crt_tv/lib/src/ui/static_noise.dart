import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

/// Animated TV snow.
class StaticNoise extends StatefulWidget {
  const StaticNoise({super.key, this.label});

  /// Optional text in the middle, e.g. "NO SIGNAL".
  final String? label;

  @override
  State<StaticNoise> createState() => _StaticNoiseState();
}

class _StaticNoiseState extends State<StaticNoise> with SingleTickerProviderStateMixin {
  // A handful of noise frames, made once and shared. Flipping them at random
  // every frame looks like endless fresh snow.
  static List<ui.Image>? _frames;
  static Future<List<ui.Image>>? _loading;

  late final Ticker _ticker;
  final Random _random = Random();
  Duration _lastFrame = Duration.zero;
  int _pick = 0;
  double _band = 0;

  @override
  void initState() {
    super.initState();
    _loading ??= _makeFrames();
    _loading!.then((frames) {
      _frames = frames;
      if (mounted) setState(() {});
    });
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    if (elapsed - _lastFrame < const Duration(milliseconds: 33)) return;
    _lastFrame = elapsed;
    setState(() {
      _pick = _random.nextInt(1 << 20);
      _band = (elapsed.inMilliseconds / 2600.0) % 1.0;
    });
  }

  static Future<List<ui.Image>> _makeFrames() async {
    const width = 192;
    const height = 144;
    final random = Random();
    final frames = <ui.Image>[];
    for (var f = 0; f < 6; f++) {
      final pixels = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        var smear = random.nextInt(256);
        for (var x = 0; x < width; x++) {
          // Mostly random, smeared a little sideways like a real tuner.
          smear = (smear * 0.25 + random.nextInt(256) * 0.75).round();
          final i = (y * width + x) * 4;
          pixels[i] = smear;
          pixels[i + 1] = smear;
          pixels[i + 2] = smear;
          pixels[i + 3] = 255;
        }
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, done.complete);
      frames.add(await done.future);
    }
    return frames;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    final label = widget.label;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _NoisePainter(
            frames == null || frames.isEmpty ? null : frames[_pick % frames.length],
            _pick >> 8,
            _band,
          ),
        ),
        if (label != null)
          Center(
            child: LayoutBuilder(
              builder: (context, box) => Container(
                padding: EdgeInsets.symmetric(
                  horizontal: box.maxHeight * 0.04,
                  vertical: box.maxHeight * 0.015,
                ),
                color: Colors.black.withValues(alpha: 0.65),
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: max(12.0, box.maxHeight * 0.06),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Consolas', 'Courier New', 'DejaVu Sans Mono'],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NoisePainter extends CustomPainter {
  _NoisePainter(this.image, this.variant, this.band);

  final ui.Image? image;
  final int variant;
  final double band;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final img = image;
    if (img == null) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFF808080));
      return;
    }
    final flipX = (variant & 1) == 1;
    final flipY = (variant & 2) == 2;
    canvas.save();
    canvas.translate(flipX ? size.width : 0.0, flipY ? size.height : 0.0);
    canvas.scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();

    // A slow dark band rolling down through the snow.
    final bandHeight = size.height * 0.2;
    final top = band * (size.height + bandHeight) - bandHeight;
    final bandRect = Rect.fromLTWH(0, top, size.width, bandHeight);
    canvas.drawRect(
      bandRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.35),
            Colors.black.withValues(alpha: 0.0),
          ],
        ).createShader(bandRect),
    );
  }

  @override
  bool shouldRepaint(_NoisePainter oldDelegate) => true;
}
