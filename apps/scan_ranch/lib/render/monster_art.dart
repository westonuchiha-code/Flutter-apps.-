// Monster art: loads the sprite "material maps" from assets/monsters,
// recolours them with a palette, and applies the CRT look (glow, scan lines,
// vignette) that every monster always gets.
//
// Art hand-off: each silhouette is a 64x64 PNG where
//   R = material id (index into assets/monsters/manifest.json "materials"),
//   G = shade tone 0-4 (x50); for outlines, G = the touching material id,
//   B = 1 on the lit side of the outline, A = 255 where drawn.
// Replace a PNG to restyle a monster. To use full-colour art instead, set
// [MonsterArt.fullColour] to true and ship ready-coloured PNGs (palettes are
// then ignored, but the CRT look is still applied).
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../model/genome.dart';

/// Material ids used in the sprite maps.
enum ArtMat {
  none,
  body,
  back,
  belly,
  accent,
  claw,
  mouth,
  outline,
  eye,
  eyeglow,
  pupil,
  tooth,
  toothshade,
  toothtip,
  clawD,
  clawTip,
}

Color _hex(int v) => Color(0xFF000000 | v);

Color _lerp(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Five tones (deep shadow → highlight), hue-shifted toward [cool] / [warm].
List<Color> _ramp(int base, int cool, int warm) {
  final b = _hex(base), c = _hex(cool), w = _hex(warm);
  return [
    _lerp(b, c, 0.62),
    _lerp(b, c, 0.33),
    b,
    _lerp(b, w, 0.3),
    _lerp(b, w, 0.58),
  ];
}

/// A colour scheme for one monster.
class MonsterPalette {
  MonsterPalette({
    required this.name,
    required List<int> body,
    required List<int> back,
    required List<int> belly,
    required List<int> accent,
    required int outline,
    required int eye,
  }) : ramps = {
         ArtMat.body: _ramp(body[0], body[1], body[2]),
         ArtMat.back: _ramp(back[0], back[1], back[2]),
         ArtMat.belly: _ramp(belly[0], belly[1], belly[2]),
         ArtMat.accent: _ramp(accent[0], accent[1], accent[2]),
         ArtMat.claw: _ramp(0xE9E4D4, 0x6B6370, 0xFFFFFF),
         ArtMat.mouth: _ramp(0x3A0B16, 0x12030A, 0x5A1626),
       },
       outline = _hex(outline),
       eye = _hex(eye);

  final String name;
  final Map<ArtMat, List<Color>> ramps;
  final Color outline;
  final Color eye;

  Color get eyeGlow => _lerp(eye, Colors.white, 0.75);
}

/// The 12 palettes (edgy: dark bases, hot accents, glowing eyes).
final List<MonsterPalette> monsterPalettes = [
  MonsterPalette(
    name: 'Crimson',
    body: [0xB3263E, 0x2A0B2E, 0xFF9C6A],
    back: [0x7D1A33, 0x1A0820, 0xC2455A],
    belly: [0xE3B48F, 0x7A3B3B, 0xFFF1D6],
    accent: [0x2F3040, 0x07070F, 0x7A7F9A],
    outline: 0x12060C,
    eye: 0xFFD23F,
  ),
  MonsterPalette(
    name: 'Toxic',
    body: [0x3F7D3A, 0x0B2A24, 0xD7FF7A],
    back: [0x2A5A2F, 0x071A16, 0x6FAE48],
    belly: [0xC9D98A, 0x4A5A2A, 0xF8FFD0],
    accent: [0x6E2C8F, 0x1A0628, 0xD98AFF],
    outline: 0x08130E,
    eye: 0xFF3DF2,
  ),
  MonsterPalette(
    name: 'Steel',
    body: [0x41607F, 0x0B1424, 0xA8D8FF],
    back: [0x2C425B, 0x070D18, 0x5D84A8],
    belly: [0xC8D4E0, 0x4A5A70, 0xFFFFFF],
    accent: [0xD98A2B, 0x4A1A08, 0xFFD88A],
    outline: 0x070B14,
    eye: 0x39E0FF,
  ),
  MonsterPalette(
    name: 'Obsidian',
    body: [0x2B2B38, 0x05050A, 0x7A7AA0],
    back: [0x1C1C26, 0x040408, 0x45455A],
    belly: [0x4A4A5E, 0x10101A, 0x8A8AA8],
    accent: [0x00B8D4, 0x002A3A, 0x9AF6FF],
    outline: 0x040408,
    eye: 0x00F0FF,
  ),
  MonsterPalette(
    name: 'Magma',
    body: [0x3A2A2A, 0x0A0505, 0xA86A4A],
    back: [0x241818, 0x050202, 0x5A3A30],
    belly: [0xFF7A1A, 0x8A1A00, 0xFFE08A],
    accent: [0xFF5A00, 0x5A0A00, 0xFFD06A],
    outline: 0x0A0404,
    eye: 0xFFCF3A,
  ),
  MonsterPalette(
    name: 'Bone',
    body: [0xCFC3A6, 0x4A3A3A, 0xFFF6DC],
    back: [0x9A8C74, 0x2A2220, 0xCFC3A6],
    belly: [0xE8DCC0, 0x7A6A5A, 0xFFFFFF],
    accent: [0x8A2A1A, 0x2A0804, 0xE06A4A],
    outline: 0x1A1410,
    eye: 0xFF2A2A,
  ),
  MonsterPalette(
    name: 'Venom',
    body: [0x5A2A7A, 0x14061F, 0xC78AFF],
    back: [0x3E1A56, 0x0A0312, 0x7A4A9A],
    belly: [0xB6E04A, 0x3A5A10, 0xF0FFB0],
    accent: [0x9ADF2A, 0x2A4A05, 0xE8FF9A],
    outline: 0x0C0414,
    eye: 0xB6FF3A,
  ),
  MonsterPalette(
    name: 'Frost',
    body: [0x7FB2D0, 0x1A3050, 0xFFFFFF],
    back: [0x55819E, 0x0E1C30, 0x9FC8E0],
    belly: [0xE8F6FF, 0x6A8AA8, 0xFFFFFF],
    accent: [0x2A3A8A, 0x0A0F2A, 0x7A8AFF],
    outline: 0x0A1428,
    eye: 0x2AFFFF,
  ),
  MonsterPalette(
    name: 'Dune',
    body: [0xB08A50, 0x3A2410, 0xFFE0A0],
    back: [0x7C5C32, 0x24160A, 0xB08A50],
    belly: [0xE8D0A0, 0x7A6040, 0xFFF4D8],
    accent: [0x1E1A18, 0x050404, 0x5A524A],
    outline: 0x160E06,
    eye: 0xFF6A00,
  ),
  MonsterPalette(
    name: 'Swamp',
    body: [0x1F6F6A, 0x041A1C, 0x7AFFD6],
    back: [0x145049, 0x030F10, 0x2F8A80],
    belly: [0xE0C070, 0x6A4A20, 0xFFF0B0],
    accent: [0xE0702A, 0x4A1A05, 0xFFC07A],
    outline: 0x041012,
    eye: 0xFFE03A,
  ),
  MonsterPalette(
    name: 'Shadow',
    body: [0x3A3A44, 0x08080C, 0x8A8AA0],
    back: [0x26262E, 0x050508, 0x4A4A58],
    belly: [0x5A5A66, 0x18181E, 0x9A9AAA],
    accent: [0xC81E2E, 0x3A0408, 0xFF7A8A],
    outline: 0x060608,
    eye: 0xFF1E3A,
  ),
  MonsterPalette(
    name: 'Regal',
    body: [0x2A2420, 0x060404, 0x6A5A40],
    back: [0x1A1612, 0x040302, 0x3A3228],
    belly: [0x3A3228, 0x0A0806, 0x6A5A48],
    accent: [0xE8B030, 0x5A3A05, 0xFFF0A0],
    outline: 0x050403,
    eye: 0xFFE070,
  ),
];

/// Loads, recolours and caches monster images (with the CRT look baked in).
class MonsterArt {
  MonsterArt._();
  static final MonsterArt instance = MonsterArt._();

  /// Set when the PNGs are full-colour art rather than material maps.
  static bool fullColour = false;

  /// Pixel size each sprite pixel is rendered at before the CRT pass.
  static const crtScale = 4;

  /// Padding around the sprite so the glow is not cut off.
  static const pad = 8;

  List<String> _names = const [];
  final Map<int, Uint8List> _maps = {}; // silhouette -> RGBA map
  final Map<String, ui.Image> _images = {};
  final Map<String, Future<ui.Image>> _pending = {};
  int _size = 64;

  bool get loaded => _names.isNotEmpty;

  Future<void> load({AssetBundle? bundle}) async {
    if (loaded) return;
    final b = bundle ?? rootBundle;
    final manifest =
        jsonDecode(await b.loadString('assets/monsters/manifest.json')) as Map;
    final names = (manifest['silhouettes'] as List).cast<String>();
    for (var i = 0; i < names.length; i++) {
      final data = await b.load('assets/monsters/${names[i]}.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _size = frame.image.width;
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      _maps[i] = bytes!.buffer.asUint8List();
      frame.image.dispose();
    }
    // Only now is the art usable (avoids building images half-loaded).
    _names = names;
  }

  String silhouetteName(int i) =>
      _names.isEmpty ? '?' : _names[i % _names.length];

  /// The finished image for [silhouette] + [palette], or null while it is
  /// being made (it is then started in the background).
  ui.Image? imageFor(int silhouette, int palette) {
    final key = '$silhouette/$palette';
    final ready = _images[key];
    if (ready != null) return ready;
    if (loaded && !_pending.containsKey(key)) {
      _pending[key] = _build(silhouette, palette).then((img) {
        _images[key] = img;
        _pending.remove(key);
        return img;
      });
    }
    return null;
  }

  Future<ui.Image> imageAsync(int silhouette, int palette) async {
    final now = imageFor(silhouette, palette);
    if (now != null) return now;
    return _pending['$silhouette/$palette']!;
  }

  /// Recolours the material map with [palette].
  Uint8List colourise(Uint8List map, MonsterPalette pal) {
    final out = Uint8List(map.length);
    for (var i = 0; i < map.length; i += 4) {
      if (map[i + 3] == 0) continue;
      if (fullColour) {
        out.setRange(i, i + 4, map, i);
        continue;
      }
      final mat = ArtMat.values[map[i].clamp(0, ArtMat.values.length - 1)];
      final g = map[i + 1];
      Color c;
      switch (mat) {
        case ArtMat.outline:
          final touching = ArtMat.values[g.clamp(0, ArtMat.values.length - 1)];
          final ramp = pal.ramps[touching] ?? pal.ramps[ArtMat.body]!;
          c = map[i + 2] == 1
              ? _lerp(ramp[1], pal.outline, 0.35)
              : _lerp(ramp[0], pal.outline, 0.55);
        case ArtMat.eye:
          c = pal.eye;
        case ArtMat.eyeglow:
          c = pal.eyeGlow;
        case ArtMat.pupil:
          c = pal.outline;
        case ArtMat.tooth:
          c = const Color(0xFFF6F1E4);
        case ArtMat.toothshade:
          c = const Color(0xFFC9C0AE);
        case ArtMat.toothtip || ArtMat.clawD:
          c = const Color(0xFFD9D1BF);
        case ArtMat.clawTip:
          c = const Color(0xFFFFFAF0);
        default:
          final ramp = pal.ramps[mat] ?? pal.ramps[ArtMat.body]!;
          c = ramp[(g ~/ 50).clamp(0, 4)];
      }
      final argb = c.toARGB32();
      out[i] = (argb >> 16) & 0xFF;
      out[i + 1] = (argb >> 8) & 0xFF;
      out[i + 2] = argb & 0xFF;
      out[i + 3] = 255;
    }
    return out;
  }

  Future<ui.Image> _build(int silhouette, int palette) async {
    final map = _maps[silhouette % _maps.length]!;
    final pal = monsterPalettes[palette % monsterPalettes.length];
    final rgba = colourise(map, pal);
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      _size,
      _size,
      ui.PixelFormat.rgba8888,
      c.complete,
    );
    final sprite = await c.future;
    final crt = await _crt(sprite);
    sprite.dispose();
    return crt;
  }

  /// The CRT look: soft glow, scan lines and a vignette, on the monster only.
  Future<ui.Image> _crt(ui.Image sprite) async {
    final s = (_size * crtScale).toDouble();
    final total = s + pad * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final src = Rect.fromLTWH(0, 0, _size.toDouble(), _size.toDouble());
    final dst = Rect.fromLTWH(pad.toDouble(), pad.toDouble(), s, s);
    final bounds = Rect.fromLTWH(0, 0, total, total);

    canvas.saveLayer(bounds, Paint());
    canvas.drawImageRect(
      sprite,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.none,
    );
    // Glow: a blurred copy added on top.
    canvas.drawImageRect(
      sprite,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.none
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3)
        ..colorFilter = const ColorFilter.mode(
          Color(0x73FFFFFF),
          BlendMode.modulate,
        )
        ..blendMode = BlendMode.plus,
    );
    // Scan lines (only where the monster is drawn).
    final line = Paint()
      ..color = const Color(0x8C000000)
      ..blendMode = BlendMode.srcATop;
    for (var y = 2.0; y < total; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, total, 1), line);
    }
    // Vignette.
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.srcATop
        ..shader = ui.Gradient.radial(
          bounds.center,
          total * 0.7,
          [
            const Color(0x00000000),
            const Color(0x00000000),
            const Color(0x73000000),
          ],
          [0, 0.55, 1],
        ),
    );
    canvas.restore();
    return recorder.endRecording().toImage(total.toInt(), total.toInt());
  }

  /// Where the sprite sits inside a CRT image (for layout: the feet are at
  /// the bottom of this rect).
  Rect spriteRectIn(ui.Image img) {
    final s = (_size * crtScale).toDouble();
    return Rect.fromLTWH(pad.toDouble(), pad.toDouble(), s, s);
  }
}

/// Palette index for a creature (shiny ones use an alternate palette).
int paletteFor(Genome g, Individuality ind) => ind.shiny
    ? (g.palette + monsterPalettes.length ~/ 2) % monsterPalettes.length
    : g.palette;

/// A static portrait of a monster (box, details, scan result).
class MonsterPortrait extends StatefulWidget {
  const MonsterPortrait({
    super.key,
    required this.silhouette,
    required this.palette,
    this.flip = false,
  });

  final int silhouette;
  final int palette;
  final bool flip;

  @override
  State<MonsterPortrait> createState() => _MonsterPortraitState();
}

class _MonsterPortraitState extends State<MonsterPortrait> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(MonsterPortrait old) {
    super.didUpdateWidget(old);
    if (old.silhouette != widget.silhouette || old.palette != widget.palette) {
      _image = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final art = MonsterArt.instance;
    if (!art.loaded) await art.load();
    final img = await art.imageAsync(widget.silhouette, widget.palette);
    if (mounted) setState(() => _image = img);
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) return const SizedBox.expand();
    return Transform.flip(
      flipX: widget.flip,
      child: RawImage(
        image: img,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
