import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:video_kit/video_kit.dart';

import 'project.dart';

/// Draws a title card on the 4:3 canvas: chunky text in two colours only
/// (no smoothing), like a character generator.
Future<VideoFrame> renderTitle(Scene s) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawColor(Color(s.background), BlendMode.src);
  final lines = s.text.trim().isEmpty ? 1 : s.text.trim().split('\n').length;
  final size = lines <= 2 ? 30.0 : (lines <= 4 ? 22.0 : 16.0);
  final tp = TextPainter(
    text: TextSpan(
      text: s.text.trim().isEmpty ? ' ' : s.text.trim(),
      style: TextStyle(
        fontFamily: 'Roboto',
        color: Color(s.textColor),
        fontSize: size,
        fontWeight: FontWeight.w900,
        height: 1.15,
        letterSpacing: 1,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 8,
  )..layout(maxWidth: canvasWidth - 24);
  tp.paint(
    canvas,
    Offset((canvasWidth - tp.width) / 2, (canvasHeight - tp.height) / 2),
  );
  final image = await rec.endRecording().toImage(canvasWidth, canvasHeight);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  tp.dispose();
  final rgba = data.buffer.asUint8List();
  final out = VideoFrame(canvasWidth, canvasHeight);
  final bg = s.background, fg = s.textColor;
  int ch(int c, int shift) => (c >> shift) & 255;
  for (var i = 0; i < out.pixels.length; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    int d(int c) {
      final dr = r - ch(c, 16), dg = g - ch(c, 8), db = b - ch(c, 0);
      return dr * dr + dg * dg + db * db;
    }

    out.pixels[i] = (d(fg) < d(bg) ? fg : bg) | 0xFF000000;
  }
  return out;
}

/// ARGB frame → BGRA bytes for `decodeImageFromPixels`.
Uint8List bgraOf(VideoFrame f) => f.bgraBytes;

/// Draws a text overlay: two colours (text, and a black outline if on),
/// everything else see-through. Size steps 1–8 give 8 to 36 pixel text on
/// the canvas.
Future<VideoFrame> renderTextOverlay(SceneOverlay o) async {
  final size = 6.0 + o.scale * 4;
  final tp = TextPainter(
    text: TextSpan(
      text: o.text.trim().isEmpty ? ' ' : o.text.trim(),
      style: TextStyle(
        fontFamily: 'Roboto',
        color: const Color(0xFFFFFFFF),
        fontSize: size,
        fontWeight: FontWeight.w900,
        height: 1.1,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 4,
  )..layout(maxWidth: canvasWidth - 8);
  final pad = o.outline ? 2 : 0;
  final w = tp.width.ceil() + pad * 2, h = tp.height.ceil() + pad * 2;
  final rec = ui.PictureRecorder();
  tp.paint(Canvas(rec), Offset(pad.toDouble(), pad.toDouble()));
  final image = await rec.endRecording().toImage(w, h);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  tp.dispose();
  final rgba = data.buffer.asUint8List();
  final out = VideoFrame(w, h)..pixels.fillRange(0, w * h, 0);
  final solid = List<bool>.generate(w * h, (i) => rgba[i * 4 + 3] >= 128);
  for (var i = 0; i < w * h; i++) {
    if (solid[i]) out.pixels[i] = o.color | 0xFF000000;
  }
  if (o.outline) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (solid[y * w + x]) continue;
        var near = false;
        for (var dy = -1; dy <= 1 && !near; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx >= 0 && yy >= 0 && xx < w && yy < h && solid[yy * w + xx]) {
              near = true;
              break;
            }
          }
        }
        if (near) out.pixels[y * w + x] = 0xFF000000;
      }
    }
  }
  return out;
}
