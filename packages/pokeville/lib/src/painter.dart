// Draws Pokéville. Three layouts:
//  - wide (desktop, TV, tablets): the PC's 1920×1080 layout (mock-a.png):
//    PKMN DATA panel / big box / strip / button hints, scaled to fit;
//  - side (landscape handhelds like the Retroid Pocket Classic, ~450×390 dp,
//    and phones held sideways): banner, box and a narrow data panel beside
//    it, the strip and touch buttons below;
//  - tall (phones upright, ~390×844): title, banner, box, data panel under
//    it, strip, touch buttons.
// Check (status / moves / Box Dex) and the X menu have each layout too.
//
// While painting it notes where each tappable thing is ([Hits]), so taps go
// exactly where things were drawn. Text that doesn't fit is cut with "…",
// never overflows.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'controller.dart';
import 'folder.dart';
import 'look.dart';
import 'sprites.dart';
import 'store.dart';

enum LayoutKind { wide, side, tall }

/// Which layout a screen of [s] dp gets.
LayoutKind layoutFor(Size s) {
  if (s.width >= 864 && s.height >= 486) return LayoutKind.wide;
  return s.width >= s.height ? LayoutKind.side : LayoutKind.tall;
}

enum HitKind {
  slot,
  pagePrev,
  pageNext,
  strip,
  button, // 0 A, 1 Y, 2 X, 3 B
  data,
  tab,
  dexPrev,
  dexNext,
  checkPrev,
  checkNext,
  menuRow,
  menuOutside,
}

class Hit {
  const Hit(this.rect, this.kind, [this.index = 0]);

  final Rect rect;
  final HitKind kind;
  final int index;
}

/// Where the last paint put each tappable thing (in screen dp).
class Hits {
  final list = <Hit>[];

  /// The topmost thing at [p], or null.
  Hit? at(Offset p) {
    for (final h in list.reversed) {
      if (h.rect.contains(p)) return h;
    }
    return null;
  }

  /// The slot under [p] (dragging), or null.
  int? slotAt(Offset p) {
    for (final h in list.reversed) {
      if (h.kind == HitKind.menuOutside || h.kind == HitKind.menuRow) {
        return null;
      }
      if (h.kind == HitKind.slot && h.rect.contains(p)) return h.index;
    }
    return null;
  }
}

class PokevillePainter extends CustomPainter {
  PokevillePainter(this.c, this.sprites, this.hits, {required this.sway})
    : super(repaint: Listenable.merge([c, sprites]));

  final PokevilleController c;
  final PokeSprites sprites;
  final Hits hits;

  /// -1..1, the carried ball's sway.
  final double sway;

  late Pen _k;
  late Size _size;
  double _scale = 1;
  Offset _off = Offset.zero;

  // ---- hits ---------------------------------------------------------------------

  void _hit(Rect r, HitKind kind, [int i = 0]) {
    hits.list.add(
      Hit(
        Rect.fromLTWH(
          r.left * _scale + _off.dx,
          r.top * _scale + _off.dy,
          r.width * _scale,
          r.height * _scale,
        ),
        kind,
        i,
      ),
    );
  }

  ui.Image? _tex(Mon m) => m.egg ? null : sprites.image(m.species, m.shiny);

  @override
  void paint(Canvas canvas, Size size) {
    hits.list.clear();
    _size = size;
    final kind = layoutFor(size);
    c.tabCount = kind == LayoutKind.wide ? 2 : 3;
    if (kind == LayoutKind.wide) {
      _scale = math.min(size.width / 1920, size.height / 1080);
      _off = Offset(
        (size.width - 1920 * _scale) / 2,
        (size.height - 1080 * _scale) / 2,
      );
      final w = Pen(canvas);
      final blobs = c.view == PokeView.check
          ? const [
              (1600.0, 80.0, 520.0, 0xFFFFD0DE),
              (120.0, 760.0, 460.0, 0xFFBFE2FF),
              (900.0, 1060.0, 460.0, 0xFFD6F5C5),
            ]
          : const [
              (1650.0, 100.0, 520.0, 0xFFA8D8FF),
              (100.0, 900.0, 460.0, 0xFFFFC6DC),
              (1050.0, 1050.0, 420.0, 0xFFC9F2C0),
              (480.0, 40.0, 380.0, 0xFFFFE3A3),
            ];
      w.wash(Offset.zero & size, [
        for (final (x, y, r, col) in blobs)
          (x * _scale + _off.dx, y * _scale + _off.dy, r * _scale, col),
      ]);
      canvas.save();
      canvas.translate(_off.dx, _off.dy);
      canvas.scale(_scale);
      _k = Pen(canvas);
    } else {
      _scale = 1;
      _off = Offset.zero;
      _k = Pen(canvas, u: kind == LayoutKind.side ? 0.4 : 0.5);
      final s = size;
      _k.wash(Offset.zero & s, [
        (s.width * 0.9, s.height * 0.05, s.shortestSide * 0.6, 0xFFA8D8FF),
        (s.width * 0.05, s.height * 0.85, s.shortestSide * 0.55, 0xFFFFC6DC),
        (s.width * 0.55, s.height, s.shortestSide * 0.5, 0xFFC9F2C0),
        (s.width * 0.25, 0, s.shortestSide * 0.45, 0xFFFFE3A3),
      ]);
    }
    if (c.state != BoxState.ready) {
      _message(kind);
    } else if (c.view == PokeView.check) {
      kind == LayoutKind.wide ? _wideCheck() : _compactCheck(kind);
    } else {
      switch (kind) {
        case LayoutKind.wide:
          _wideBox();
        case LayoutKind.side:
          _sideBox();
        case LayoutKind.tall:
          _tallBox();
      }
    }
    if (c.menuOpen) _menu(kind);
    _notice(kind);
    if (kind == LayoutKind.wide) canvas.restore();
  }

  // ---- the box: wide (the PC's layout) ------------------------------------------

  static const _grid = Rect.fromLTWH(640, 250, 1060, 600);
  static const _data = Rect.fromLTWH(60, 160, 520, 760);

  void _wideBox() {
    final k = _k;
    k.say('POKéMON BOX', const Offset(70, 92), Face.title, 58, Look.line);
    k.say(
      '${_pokemon(c.total)} · ${c.pageCount} boxes · in Pokéville',
      const Offset(74, 134),
      Face.title,
      24,
      Look.soft,
    );
    _wideData();
    _box(
      grid: _grid,
      banner: Rect.fromLTWH(_grid.center.dx - 260, 168, 520, 72),
      cell: const Size(160, 112),
      sprite: 112,
      bannerFs: 40,
      tag: 'POKéVILLE   (X: menu)',
      tagFs: 22,
      captionFs: 20,
      captionLimit: 1900,
    );
    _strip(
      x: 640,
      y: 880,
      w: 164,
      h: 150,
      step: 178,
      n: 6,
      tagFs: 18,
      arrowS: 18,
    );
    final a = c.holding ? 'Put down' : 'Pick up';
    final names = [a, 'Check', 'Menu', c.holding ? 'Let go' : 'Back'];
    const keys = ['A', 'Y', 'X', 'B'];
    for (var i = 0; i < 4; i++) {
      final r = k.button(
        keys[i],
        names[i],
        Offset(1714, 430 + i * 80.0),
        w: 180,
      );
      _hit(r, HitKind.button, i);
    }
    k.say('LB / RB', const Offset(1726, 790), Face.title, 20, Look.soft);
    k.say('change box', const Offset(1726, 814), Face.title, 20, Look.soft);
  }

  void _wideData() {
    final k = _k;
    k.panel(_data);
    _hit(_data, HitKind.data);
    k.label('PKMN DATA', _data.topLeft + const Offset(24, 20));
    final frame = Rect.fromLTWH(_data.left + 30, _data.top + 66, 460, 300);
    k.checker(frame, const Color(0xFFD8ECFF), const Color(0xFFC4E1FF));
    final m = c.shown;
    if (m == null) {
      k.say(
        'Nothing here',
        frame.center + const Offset(0, 10),
        Face.title,
        30,
        Look.faint,
        align: 1,
      );
      if (c.row < 0) return;
      k.say(
        'Point at a Pokémon to see',
        Offset(_data.left + 36, frame.bottom + 60),
        Face.text,
        24,
        Look.soft,
      );
      k.say(
        'its data here.',
        Offset(_data.left + 36, frame.bottom + 94),
        Face.text,
        24,
        Look.soft,
      );
      return;
    }
    _picture(m, frame.center, 288, 200);
    if (m.shiny) k.star(frame.topLeft + const Offset(420, 40), 22, Look.star);
    final x = _data.left + 36;
    final y = frame.bottom;
    final nw = k.say(
      m.shownName,
      Offset(x, y + 64),
      Face.title,
      44,
      Look.ink,
      maxW: 380,
    );
    if (m.gender < 2 && !m.egg) {
      k.genderMark(Offset(x + nw + 28, y + 46), m.gender == 0, s: 1.2);
    }
    if (m.egg) {
      k.say(
        "An Egg. Something's moving inside.",
        Offset(x, y + 108),
        Face.text,
        24,
        Look.ink,
      );
    } else {
      k.say(_kind(m), Offset(x, y + 108), Face.text, 26, Look.ink, maxW: 450);
    }
    var cx = x;
    for (final t in m.types) {
      cx +=
          k.chip(t.toUpperCase(), Offset(cx, y + 126), Look.typeColor(t)) + 10;
    }
    if (m.shiny) {
      k.chip('★ SHINY', Offset(cx, y + 126), Look.star, ink: Look.ink);
    }
    k.say(_otLine(m), Offset(x, y + 208), Face.text, 24, Look.ink, maxW: 450);
    final moves = m.moves;
    for (var i = 0; i < math.min(moves.length, 4); i++) {
      final r = Rect.fromLTWH(
        x + (i % 2) * 226,
        y + 232 + (i ~/ 2) * 54,
        216,
        46,
      );
      k.box(r, Look.white, Look.line, 3, 8);
      k.say(
        moves[i],
        r.topLeft + const Offset(12, 32),
        Face.text,
        22,
        Look.ink,
        maxW: 196,
      );
    }
    if (m.item.isNotEmpty) {
      k.say(
        'Holds ${m.item}',
        Offset(x, y + 370),
        Face.text,
        22,
        Look.soft,
        maxW: 450,
      );
    }
  }

  /// A Pokémon's picture centred at [at]: the sprite [size] big, an egg
  /// [eggSize] big, or a ball when there's no picture.
  void _picture(Mon m, Offset at, double size, double eggSize) {
    if (m.egg) {
      _k.egg(at, eggSize);
      return;
    }
    final img = _tex(m);
    if (img != null) {
      _k.sprite(
        img,
        Rect.fromCenter(
          center: at - Offset(0, size * 6 / 288),
          width: size,
          height: size,
        ),
      );
    } else {
      _k.miniBall(at, size * 0.12, sprites.ballImage);
    }
  }

  // ---- the box itself (every layout) --------------------------------------------

  Rect _cellRect(Rect grid, Size cell, int i) {
    final origin =
        grid.center - Offset(c.cols * cell.width, c.rows * cell.height) / 2;
    return Rect.fromLTWH(
      origin.dx + (i % c.cols) * cell.width,
      origin.dy + (i ~/ c.cols) * cell.height,
      cell.width,
      cell.height,
    );
  }

  void _box({
    required Rect grid,
    required Rect banner,
    required Size cell,
    required double sprite,
    required double bannerFs,
    required String tag,
    required double tagFs,
    required double captionFs,
    required double captionLimit,
  }) {
    final k = _k;
    final u = k.u;
    k.wallPanel(grid, Look.wallOf(c.page));
    // the banner: which box
    k.box(banner.shift(Offset(0, 5 * u)), Look.line, Look.line, 0, 12 * u);
    k.box(
      banner,
      c.row == -1 ? Look.lit : Look.white,
      Look.line,
      5 * u,
      12 * u,
    );
    final as = banner.height * 0.25;
    k.say(
      c.pageTitle(c.page),
      banner.center + Offset(0, bannerFs * 0.37),
      Face.title,
      bannerFs,
      Look.ink,
      align: 1,
      maxW: banner.width - as * 5,
    );
    k.arrow(Offset(banner.left + as * 2, banner.center.dy), -1, s: as);
    k.arrow(Offset(banner.right - as * 2, banner.center.dy), 1, s: as);
    _hit(
      Rect.fromLTRB(
        banner.left,
        banner.top,
        banner.left + banner.width / 3,
        banner.bottom,
      ),
      HitKind.pagePrev,
    );
    _hit(
      Rect.fromLTRB(
        banner.right - banner.width / 3,
        banner.top,
        banner.right,
        banner.bottom,
      ),
      HitKind.pageNext,
    );
    k.tag(
      tag,
      grid.topLeft + Offset(24 * u, -tagFs * 0.75),
      Look.line,
      fs: tagFs,
      maxW: grid.width - 48 * u,
    );
    for (var i = 0; i < PokeBoxStore.slots; i++) {
      final r = _cellRect(grid, cell, i);
      _hit(r, HitKind.slot, i);
      final m = c.pageMon(c.page, i);
      if (m == null || c.heldIsHere(i)) continue;
      final at = r.center;
      if (m.egg) {
        k.egg(at, sprite * 76 / 112);
      } else {
        final img = _tex(m);
        if (img != null) {
          k.sprite(
            img,
            Rect.fromCenter(center: at, width: sprite, height: sprite),
          );
        } else {
          k.miniBall(at, sprite * 22 / 112, sprites.ballImage);
        }
      }
      if (m.shiny) {
        k.star(
          Offset(
            r.right - sprite * 30 / 112 + (cell.width - sprite) * 0,
            r.top + sprite * 22 / 112,
          ),
          sprite * 13 / 112,
          Look.star,
        );
      }
    }
    if (c.row < 0) return;
    final r = _cellRect(grid, cell, c.slotIndex);
    final cs = math.min(sprite, math.min(cell.width, cell.height) - 4 * u);
    final cur = Rect.fromCenter(center: r.center, width: cs, height: cs);
    k.cursor(cur, c.holding);
    final h = c.held;
    if (h == null) return;
    final rad = sprite * 72 / 112;
    final bc = cur.center + Offset(sprite * 58 / 112, -sprite * 50 / 112);
    k.glassBall(bc, rad, _tex(h.mon), -0.2 + sway * 0.04, egg: h.mon.egg);
    final cap = '${h.mon.shownName}, from ${c.heldWhere}';
    final cw = math.min(
      k.width(cap, Face.title, captionFs) + captionFs * 1.4,
      captionLimit - 8 * u,
    );
    var cr = Rect.fromLTWH(
      bc.dx + rad * 1.17,
      bc.dy - rad * 0.83,
      cw,
      captionFs * 1.9,
    );
    if (cr.right > captionLimit) cr = cr.shift(Offset(-(rad * 2.34 + cw), 0));
    if (cr.left < 4) cr = cr.shift(Offset(4 - cr.left, rad * 1.4));
    k.box(cr, Look.white, Look.line, 3 * u, 8 * u);
    k.say(
      cap,
      cr.topLeft + Offset(captionFs * 0.7, captionFs * 1.35),
      Face.title,
      captionFs,
      Look.ink,
      maxW: cw - captionFs * 1.4,
    );
  }

  // ---- the strip: the boxes along the bottom ------------------------------------

  void _strip({
    required double x,
    required double y,
    required double w,
    required double h,
    required double step,
    required int n,
    required double tagFs,
    required double arrowS,
  }) {
    final k = _k;
    final u = k.u;
    final count = c.pageCount;
    final first = (c.page - n ~/ 2 + 1)
        .clamp(0, math.max(0, count - n))
        .toInt();
    for (var j = 0; j < math.min(n, count); j++) {
      final p = first + j;
      final r = Rect.fromLTWH(x + j * step, y, w, h);
      _hit(r.inflate(4 * u), HitKind.strip, p);
      if (p == c.page) k.box(r.inflate(8 * u), Look.gold, Look.gold, 0, 16 * u);
      k.wallPanel(r, Look.wallOf(p), radius: 12, bw: 4);
      final cell = math.min(
        (w - 16 * u) / c.cols,
        (h - 8 * u - tagFs) / c.rows,
      );
      final origin =
          r.center -
          Offset(c.cols * cell, c.rows * cell) / 2 +
          Offset(0, tagFs * 0.45);
      for (var i = 0; i < PokeBoxStore.slots; i++) {
        final m = c.pageMon(p, i);
        if (m == null) continue;
        final at =
            origin +
            Offset((i % c.cols) * cell, (i ~/ c.cols) * cell) +
            Offset(cell / 2, cell / 2);
        if (m.egg) {
          k.c.drawCircle(
            at,
            cell * 0.25,
            Paint()..color = const Color(0xFFF4F1DC),
          );
          continue;
        }
        final img = cell >= 14 ? _tex(m) : null;
        if (img != null) {
          final s = cell * 32 / 24;
          k.sprite(img, Rect.fromCenter(center: at, width: s, height: s));
        } else {
          k.c.drawCircle(at, cell * 0.22, Paint()..color = Look.red);
        }
      }
      k.tag(
        c.pageTitle(p),
        r.topLeft + Offset(6 * u, -tagFs * 0.67),
        const Color(0xFF3F7FD0),
        fs: tagFs,
        maxW: w - 12 * u,
      );
    }
    final mid = y + h / 2;
    if (first > 0) {
      final a = Rect.fromCenter(
        center: Offset(x - arrowS * 1.45, mid),
        width: arrowS * 2.4,
        height: h,
      );
      k.arrow(a.center, -1, s: arrowS);
      _hit(a, HitKind.pagePrev);
    }
    if (first + n < count) {
      final a = Rect.fromCenter(
        center: Offset(x + n * step - (step - w) + arrowS * 1.45, mid),
        width: arrowS * 2.4,
        height: h,
      );
      k.arrow(a.center, 1, s: arrowS);
      _hit(a, HitKind.pageNext);
    }
  }

  // ---- the box: side (landscape handhelds) --------------------------------------

  static const _hintH = 30.0;

  void _sideBox() {
    final w = _size.width;
    final h = _size.height;
    const m = 8.0;
    final hintTop = h - m - _hintH;
    const stripH = 50.0;
    final stripTop = hintTop - 8 - stripH;
    const bannerH = 30.0;
    final gridTop = m + bannerH + 12;
    final gh = stripTop - 12 - gridTop;
    const fp = 6.0;
    var ch = (gh - 2 * fp) / 5;
    var cw = ch * 1.15;
    var gw = 6 * cw + 2 * fp;
    const minData = 130.0;
    if (w - 3 * m - gw < minData) {
      gw = w - 3 * m - minData;
      cw = (gw - 2 * fp) / 6;
      ch = math.min(ch, cw);
    }
    final grid = Rect.fromLTWH(m, gridTop, gw, gh);
    final bw = math.min(gw * 0.8, 240.0);
    _box(
      grid: grid,
      banner: Rect.fromLTWH(grid.center.dx - bw / 2, m, bw, bannerH),
      cell: Size(cw, ch),
      sprite: math.min(cw, ch) - 2,
      bannerFs: 16,
      tag: 'POKéVILLE · ${_pokemon(c.total)}',
      tagFs: 10,
      captionFs: 10,
      captionLimit: grid.right + 4,
    );
    final data = Rect.fromLTRB(grid.right + m, m, w - m, stripTop - 12);
    _compactData(data);
    _compactStrip(Rect.fromLTRB(m, stripTop, w - m, stripTop + stripH), 9);
    _hints(Rect.fromLTRB(m, hintTop, w - m, hintTop + _hintH));
  }

  void _tallBox() {
    final k = _k;
    final w = _size.width;
    final h = _size.height;
    const m = 12.0;
    k.say('POKéMON BOX', const Offset(m, m + 24), Face.title, 26, Look.line);
    k.say(
      '${_pokemon(c.total)} · ${c.pageCount} boxes',
      const Offset(m + 2, m + 44),
      Face.title,
      13,
      Look.soft,
      maxW: w - 2 * m,
    );
    const hintH = 2 * 40.0 + 6;
    final hintTop = h - m - hintH;
    const stripH = 62.0;
    final stripTop = hintTop - 12 - stripH;
    final bw = math.min(280.0, w - 2 * m);
    final banner = Rect.fromLTWH((w - bw) / 2, m + 56, bw, 40);
    final gw = w - 2 * m;
    const fp = 6.0;
    final cw = (gw - 2 * fp) / 6;
    final ch = cw * 0.86;
    final grid = Rect.fromLTWH(m, banner.bottom + 18, gw, 5 * ch + 2 * fp);
    _box(
      grid: grid,
      banner: banner,
      cell: Size(cw, ch),
      sprite: math.min(cw, ch) - 2,
      bannerFs: 20,
      tag: 'POKéVILLE   (X: menu)',
      tagFs: 11,
      captionFs: 11,
      captionLimit: w - 4,
    );
    final data = Rect.fromLTRB(m, grid.bottom + 14, w - m, stripTop - 16);
    if (data.height >= 80) _compactData(data);
    _compactStrip(Rect.fromLTRB(m, stripTop, w - m, stripTop + stripH), 10);
    _hints(Rect.fromLTRB(m, hintTop, w - m, hintTop + hintH));
  }

  void _compactStrip(Rect area, double tagFs) {
    const gap = 10.0;
    const arrow = 14.0;
    final inner = Rect.fromLTRB(
      area.left + arrow,
      area.top,
      area.right - arrow,
      area.bottom,
    );
    final boxH = area.height - tagFs * 0.4;
    final boxW = boxH * 1.1;
    final n = math.max(1, ((inner.width + gap) / (boxW + gap)).floor());
    final shown = math.min(n, c.pageCount);
    final used = shown * boxW + (shown - 1) * gap;
    _strip(
      x: inner.left + (inner.width - used) / 2,
      y: area.bottom - boxH,
      w: boxW,
      h: boxH,
      step: boxW + gap,
      n: n,
      tagFs: tagFs,
      arrowS: 7,
    );
  }

  /// The touch buttons (and pad hints) along the bottom.
  void _hints(Rect r) {
    final names = [
      c.holding ? 'Put down' : 'Pick up',
      'Check',
      'Menu',
      c.holding ? 'Let go' : 'Back',
    ];
    const keys = ['A', 'Y', 'X', 'B'];
    const gap = 6.0;
    // one row, or 2 x 2 when the row would be too cramped
    final perRow = r.width / 4 >= 100 ? 4 : 2;
    final rowsN = 4 ~/ perRow;
    final bw = (r.width - (perRow - 1) * gap) / perRow;
    final bh = (r.height - (rowsN - 1) * gap) / rowsN - 4;
    for (var i = 0; i < 4; i++) {
      final b = _k.button(
        keys[i],
        names[i],
        Offset(
          r.left + (i % perRow) * (bw + gap),
          r.top + (i ~/ perRow) * (bh + 4 + gap),
        ),
        w: bw,
        h: bh,
        fixed: true,
        fs: math.min(bh * 0.42, 15),
      );
      _hit(b, HitKind.button, i);
    }
  }

  // The data panel on small screens: stacked when narrow, the picture beside
  // the text when there's room. Lines that don't fit are left out.
  void _compactData(Rect r) {
    final k = _k;
    k.panel(r);
    _hit(r, HitKind.data);
    final pad = 10.0;
    final inner = r.deflate(pad);
    k.label('PKMN DATA', inner.topLeft, fs: 10);
    final top = inner.top + 22;
    final m = c.shown;
    final wideish = inner.width >= 280;
    final fh = wideish
        ? math.min(inner.height - 22, inner.width * 0.4)
        : math.min(inner.width * 0.72, (inner.height - 22) * 0.45);
    final frame = Rect.fromLTWH(
      inner.left,
      top,
      wideish ? fh : inner.width,
      fh,
    );
    k.checker(frame, const Color(0xFFD8ECFF), const Color(0xFFC4E1FF));
    var x = wideish ? frame.right + 10 : inner.left;
    var y = wideish ? top : frame.bottom + 6;
    final tw = inner.right - x;
    if (m == null) {
      k.say(
        'Nothing here',
        frame.center + const Offset(0, 5),
        Face.title,
        13,
        Look.faint,
        align: 1,
        maxW: frame.width - 8,
      );
      if (c.row >= 0 && inner.bottom - y > 30) {
        k.say(
          'Point at a Pokémon',
          Offset(x, y + 16),
          Face.text,
          11,
          Look.soft,
          maxW: tw,
        );
        k.say(
          'to see its data.',
          Offset(x, y + 31),
          Face.text,
          11,
          Look.soft,
          maxW: tw,
        );
      }
      return;
    }
    final ps = ((math.min(frame.width, frame.height) - 8) / 48).floor() * 48.0;
    _picture(
      m,
      frame.center,
      ps <= 0 ? frame.height - 8 : ps,
      frame.height * 0.66,
    );
    if (m.shiny) k.star(frame.topRight + const Offset(-12, 12), 8, Look.star);
    bool room(double need) => y + need <= inner.bottom + 2;
    if (room(18)) {
      y += 17;
      // narrow: the level goes on the name's line
      final lv = wideish || m.egg ? '' : 'Lv.${m.level}';
      final lw = lv.isEmpty ? 0.0 : k.width(lv, Face.text, 11) + 6;
      k.say(lv, Offset(inner.right, y), Face.text, 11, Look.ink, align: 2);
      final nw = k.say(
        m.shownName,
        Offset(x, y),
        Face.title,
        16,
        Look.ink,
        maxW: tw - 20 - lw,
      );
      if (m.gender < 2 && !m.egg) {
        k.genderMark(Offset(x + nw + 10, y - 6), m.gender == 0, s: 0.55);
      }
    }
    if (room(16)) {
      y += 16;
      k.say(
        m.egg
            ? (wideish ? "An Egg. Something's moving inside." : 'An Egg.')
            : (wideish ? _kind(m) : 'No.${_three(m.species)} ${m.name}'),
        Offset(x, y),
        Face.text,
        11,
        Look.ink,
        maxW: tw,
      );
    }
    if (!m.egg && (m.types.isNotEmpty || m.shiny) && room(20)) {
      y += 4;
      var cx = x;
      for (final t in [
        ...m.types.map((t) => t.toUpperCase()),
        if (m.shiny) '★ SHINY',
      ]) {
        final cw = k.width(t, Face.title, 9) + 11;
        if (cx + cw > inner.right) break;
        cx +=
            k.chip(
              t,
              Offset(cx, y),
              t == '★ SHINY'
                  ? Look.star
                  : Look.typeColor(t[0] + t.substring(1).toLowerCase()),
              fs: 9,
              ink: t == '★ SHINY' ? Look.ink : Look.white,
            ) +
            4;
      }
      y += 16;
    }
    final ot = _otLine(m);
    final split = k.width(ot, Face.text, 11) > tw && m.ot.isNotEmpty;
    for (final line
        in split
            ? ['OT ${m.ot}', if (m.origin.isNotEmpty) 'from ${m.origin}']
            : [ot]) {
      if (!room(15)) break;
      y += 15;
      k.say(line, Offset(x, y), Face.text, 11, Look.ink, maxW: tw);
    }
    final moves = m.moves;
    if (moves.isNotEmpty && room(24)) {
      // under the picture when the text column is beside it and full
      if (wideish &&
          y + 50 > frame.bottom &&
          inner.bottom - frame.bottom > 30) {
        x = inner.left;
        y = math.max(y, frame.bottom);
      }
      final two = inner.right - x >= 200;
      final mw = two ? (inner.right - x - 6) / 2 : inner.right - x;
      y += 5;
      for (var i = 0; i < math.min(moves.length, 4); i++) {
        final col = two ? i % 2 : 0;
        if ((two && col == 0 || !two) && !room(21)) break;
        final r = Rect.fromLTWH(x + col * (mw + 6), y, mw, 19);
        k.box(r, Look.white, Look.line, 1.2, 4);
        k.say(
          moves[i],
          r.topLeft + const Offset(5, 14),
          Face.text,
          11,
          Look.ink,
          maxW: mw - 9,
        );
        if (!two || col == 1 || i == moves.length - 1) y += 22;
      }
    }
    if (m.item.isNotEmpty && room(14)) {
      y += 12;
      k.say(
        'Holds ${m.item}',
        Offset(x, y),
        Face.text,
        10,
        Look.soft,
        maxW: inner.right - x,
      );
    }
  }

  // ---- Check: wide (the PC's layout, mock-c) -------------------------------------

  void _wideCheck() {
    final k = _k;
    k.say('POKéMON BOX', const Offset(70, 92), Face.title, 58, Look.line);
    const tabs = ['Status', 'Moves'];
    for (var i = 0; i < tabs.length; i++) {
      final r = Rect.fromLTWH(70 + i * 230.0, 120, 220, 62);
      _tabBox(r, i == c.tab);
      k.say(
        tabs[i],
        r.center + const Offset(0, 12),
        Face.title,
        28,
        Look.ink,
        align: 1,
      );
      _hit(r, HitKind.tab, i);
    }
    const panel = Rect.fromLTWH(60, 176, 860, 860);
    k.panel(panel);
    k.c.drawRect(
      Rect.fromLTWH(75 + c.tab * 230.0, 172, 210, 12),
      Paint()..color = Look.paper,
    );
    final m = c.shown;
    if (m == null) {
      k.say(
        'Point at a Pokémon in Pokéville,',
        panel.center + const Offset(0, -10),
        Face.title,
        30,
        Look.faint,
        align: 1,
      );
      k.say(
        'then press Y to check it.',
        panel.center + const Offset(0, 34),
        Face.title,
        30,
        Look.faint,
        align: 1,
      );
    } else if (c.tab == 0) {
      _wideStatus(m);
    } else {
      _wideMoves(m);
    }
    _wideDex(m);
    final foot = Rect.fromLTWH(560, 1044, 800, 36);
    k.say(
      'Left / Right  Status / Moves     Up / Down  other Pokémon     LB RB  Dex page     B  back',
      const Offset(960, 1068),
      Face.title,
      20,
      Look.soft,
      align: 1,
    );
    _hit(foot, HitKind.button, 3);
    _hit(
      Rect.fromLTWH(panel.right - 120, panel.top + 10, 50, 50),
      HitKind.checkPrev,
    );
    _hit(
      Rect.fromLTWH(panel.right - 64, panel.top + 10, 50, 50),
      HitKind.checkNext,
    );
    if (m != null && !c.holding) {
      k.arrowV(
        Offset(panel.right - 95, panel.top + 35),
        -1,
        s: 14,
        col: Look.soft,
      );
      k.arrowV(
        Offset(panel.right - 39, panel.top + 35),
        1,
        s: 14,
        col: Look.soft,
      );
    }
  }

  void _tabBox(Rect r, bool on) {
    final u = _k.u;
    _k.box(r, on ? Look.paper : Look.lilac, Look.line, 5 * u, 14 * u);
  }

  void _field(String key, String value, double y) {
    final k = _k;
    k.say(key, Offset(90, y + 34), Face.title, 28, Look.blue);
    final r = Rect.fromLTWH(260, y, 630, 50);
    k.box(r, Look.white, Look.line, 3, 6);
    k.say(
      value,
      r.topLeft + const Offset(14, 35),
      Face.text,
      28,
      Look.ink,
      maxW: 600,
    );
  }

  void _wideStatus(Mon m) {
    final k = _k;
    k.label('PROFILE', const Offset(90, 200));
    _field('NAME', m.shownName + (m.shiny ? '  ★' : ''), 248);
    _field('KIND', m.egg ? 'Egg' : _kind(m), 306);
    _field(
      'OT',
      '${m.ot.isEmpty ? '?' : m.ot} · caught in ${m.origin.isEmpty ? '?' : m.origin}',
      364,
    );
    k.label('CONDITION', const Offset(90, 470));
    const frame = Rect.fromLTWH(90, 512, 360, 360);
    k.checker(frame, const Color(0xFFFFF3D6), const Color(0xFFFFE8B8));
    _picture(m, frame.center, 288, 220);
    k.say(
      'Held item: ${m.item.isEmpty ? 'none' : m.item}',
      const Offset(96, 920),
      Face.text,
      24,
      Look.ink,
      maxW: 800,
    );
    k.say(
      c.holding ? 'Carried, from ${c.heldWhere}' : c.whereText,
      const Offset(96, 958),
      Face.text,
      24,
      Look.ink,
      maxW: 800,
    );
    if (m.fromSave.isNotEmpty) {
      k.say(
        'came from ${m.fromSave}',
        const Offset(96, 996),
        Face.text,
        22,
        Look.soft,
        maxW: 800,
      );
    }
    k.label('BASE STATS', const Offset(480, 470));
    final stats = m.stats;
    if (m.egg || stats.length < 6) {
      k.say(
        m.egg ? 'Hatch it first!' : 'Not known yet',
        const Offset(480, 560),
        Face.text,
        24,
        Look.soft,
      );
      return;
    }
    for (var i = 0; i < 6; i++) {
      final y = 530.0 + i * 46;
      k.say(Look.statNames[i], Offset(480, y + 18), Face.title, 20, Look.ink);
      _bar(Rect.fromLTWH(612, y, 204, 18), stats[i], i, 3);
      k.say(
        '${stats[i]}',
        Offset(890, y + 20),
        Face.text,
        24,
        Look.ink,
        align: 2,
      );
    }
    k.say('TOTAL', const Offset(480, 830), Face.title, 20, Look.soft);
    k.say(
      '${stats.fold(0, (a, b) => a + b)}',
      const Offset(890, 832),
      Face.text,
      24,
      Look.soft,
      align: 2,
    );
    var cx = 480.0;
    for (final t in m.types) {
      cx +=
          k.chip(t.toUpperCase(), Offset(cx, 850), Look.typeColor(t), fs: 20) +
          10;
    }
  }

  void _bar(Rect bar, int value, int i, double bw) {
    _k.box(bar, const Color(0xFFE7E9FB), Look.line, bw, bw * 2);
    final fill = bar.deflate(bw);
    _k.c.drawRect(
      Rect.fromLTWH(
        fill.left,
        fill.top,
        fill.width * (value / 200).clamp(0.02, 1.0),
        fill.height,
      ),
      Paint()..color = Look.statColors[i],
    );
  }

  List<String> _memo(Mon m) => [
    if (m.nature.isNotEmpty) '${m.nature} nature.',
    if (m.ability.isNotEmpty) 'Ability: ${m.ability}',
    if (m.ball.isNotEmpty && m.ball != 'None') 'Caught in a ${m.ball}.',
    'Caught in ${m.origin.isEmpty ? '?' : m.origin} by ${m.ot.isEmpty ? '?' : m.ot}.',
    if (m.format.isNotEmpty)
      'Kept as a ${m.format.toUpperCase()} file (Gen ${m.generation}).',
  ];

  void _wideMoves(Mon m) {
    final k = _k;
    k.label('MOVES', const Offset(90, 200));
    final moves = m.moves;
    if (moves.isEmpty) {
      k.say(
        m.egg ? "Eggs don't know moves yet" : 'No moves known',
        const Offset(96, 290),
        Face.text,
        26,
        Look.soft,
      );
    }
    for (var i = 0; i < math.min(moves.length, 4); i++) {
      final r = Rect.fromLTWH(90, 250 + i * 76.0, 800, 62);
      k.box(r.shift(const Offset(0, 4)), Look.white, Look.line, 4, 10);
      k.box(r, Look.white, Look.line, 4, 10);
      k.say(
        moves[i],
        r.topLeft + const Offset(24, 43),
        Face.title,
        32,
        Look.ink,
        maxW: 760,
      );
    }
    k.label('TRAINER MEMO', const Offset(90, 580));
    final lines = _memo(m);
    for (var i = 0; i < lines.length; i++) {
      k.say(
        lines[i],
        Offset(96, 652 + i * 46.0),
        Face.text,
        26,
        Look.ink,
        maxW: 800,
      );
    }
  }

  void _wideDex(Mon? m) {
    final k = _k;
    const panel = Rect.fromLTWH(960, 120, 900, 916);
    k.panel(panel);
    k.label('BOX DEX', const Offset(990, 146));
    k.say(
      '${c.owned.length} / ${PokevilleController.dexAll} in Pokéville',
      const Offset(1180, 172),
      Face.title,
      28,
      Look.ink,
      maxW: 660,
    );
    _dexGrid(
      banner: const Rect.fromLTWH(1260, 200, 300, 56),
      bannerFs: 28,
      area: const Rect.fromLTWH(990, 280, 840, 744),
      cols: 10,
      cell: const Size(78, 100),
      step: const Size(84, 124),
      numFs: 16,
      m: m,
    );
    k.say(
      'Lit = in Pokéville. Dark = not in the Box yet.',
      const Offset(990, 1024),
      Face.text,
      18,
      Look.soft,
    );
  }

  void _dexGrid({
    required Rect banner,
    required double bannerFs,
    required Rect area,
    required int cols,
    required Size cell,
    required Size step,
    required double numFs,
    required Mon? m,
  }) {
    final k = _k;
    final u = k.u;
    const per = PokevilleController.dexPer;
    final lo = c.dexPage * per + 1;
    final hi = math.min(lo + per - 1, PokevilleController.dexAll);
    k.box(banner, Look.white, Look.line, 4 * u, 12 * u);
    final as = banner.height * 0.25;
    k.say(
      '${_three(lo)}–${_three(hi)}',
      banner.center + Offset(0, bannerFs * 0.39),
      Face.title,
      bannerFs,
      Look.ink,
      align: 1,
    );
    k.arrow(Offset(banner.left + as * 2, banner.center.dy), -1, s: as);
    k.arrow(Offset(banner.right - as * 2, banner.center.dy), 1, s: as);
    _hit(
      Rect.fromLTRB(
        banner.left - 20 * u,
        banner.top,
        banner.center.dx,
        banner.bottom,
      ),
      HitKind.dexPrev,
    );
    _hit(
      Rect.fromLTRB(
        banner.center.dx,
        banner.top,
        banner.right + 20 * u,
        banner.bottom,
      ),
      HitKind.dexNext,
    );
    final here = m == null || m.egg ? -1 : m.species;
    for (var i = 0; i <= hi - lo; i++) {
      final sp = lo + i;
      final have = c.owned.contains(sp);
      final r = Rect.fromLTWH(
        area.left + (i % cols) * step.width,
        area.top + (i ~/ cols) * step.height,
        cell.width,
        cell.height,
      );
      k.box(
        r,
        have ? const Color(0xFFEEF8FF) : const Color(0xFFE9EAF6),
        have ? Look.line : const Color(0xFFB9BDE8),
        3 * u,
        8 * u,
      );
      final img = sprites.image(sp, false);
      final s = math.min(cell.width * 1.1, cell.height - numFs * 0.9);
      if (img != null) {
        k.sprite(
          img,
          Rect.fromCenter(
            center: Offset(r.center.dx, r.top + s / 2 - numFs * 0.1),
            width: s,
            height: s,
          ),
          tint: have ? null : const Color(0x471F2150),
        );
      }
      k.say(
        _three(sp),
        Offset(r.center.dx, r.bottom - numFs * 0.38),
        Face.text,
        numFs,
        have ? Look.ink : Look.faint,
        align: 1,
      );
      if (sp == here) {
        k.box(
          r.inflate(4 * u),
          Look.white,
          Look.gold,
          5 * u,
          10 * u,
          center: false,
        );
      }
    }
  }

  // ---- Check: compact (Retroid, phones) -------------------------------------------

  void _compactCheck(LayoutKind kind) {
    final k = _k;
    final w = _size.width;
    final h = _size.height;
    final tall = kind == LayoutKind.tall;
    final m = tall ? 12.0 : 8.0;
    final tabH = tall ? 36.0 : 28.0;
    final hintH = tall ? 44.0 : _hintH;
    const tabs = ['Status', 'Moves', 'Box Dex'];
    final tw = math.min(140.0, (w - 2 * m - 12) / 3);
    final top = tall ? m + 34 : m;
    if (tall) {
      k.say('POKéMON BOX', Offset(m, m + 22), Face.title, 22, Look.line);
    }
    for (var i = 0; i < 3; i++) {
      final r = Rect.fromLTWH(m + i * (tw + 6), top, tw, tabH + 6);
      _tabBox(r, i == c.tab);
      k.say(
        tabs[i],
        Offset(r.center.dx, top + tabH * 0.68),
        Face.title,
        tall ? 15 : 13,
        Look.ink,
        align: 1,
        maxW: tw - 8,
      );
      _hit(r, HitKind.tab, i);
    }
    final hintTop = h - m - hintH;
    final panel = Rect.fromLTRB(m, top + tabH, w - m, hintTop - 8);
    k.panel(panel);
    k.c.drawRect(
      Rect.fromLTWH(
        m + c.tab * (tw + 6) + 5 * k.u,
        top + tabH - 3,
        tw - 10 * k.u,
        6 * k.u + 3,
      ),
      Paint()..color = Look.paper,
    );
    final inner = panel.deflate(tall ? 14 : 10);
    final mon = c.shown;
    if (c.tab == 2) {
      _compactDex(inner, mon, tall);
    } else if (mon == null) {
      k.say(
        'Point at a Pokémon in Pokéville,',
        inner.center + const Offset(0, -6),
        Face.title,
        13,
        Look.faint,
        align: 1,
        maxW: inner.width,
      );
      k.say(
        'then press Y to check it.',
        inner.center + const Offset(0, 14),
        Face.title,
        13,
        Look.faint,
        align: 1,
        maxW: inner.width,
      );
    } else if (c.tab == 0) {
      _compactStatus(inner, mon, tall);
    } else {
      _compactMoves(inner, mon, tall);
    }
    // bottom: ▲ ▼ other Pokémon (or ◀ ▶ Dex pages), B back
    final r = Rect.fromLTRB(m, hintTop, w - m, hintTop + hintH);
    const gap = 6.0;
    final bw = (r.width - 2 * gap) / 3;
    final dex = c.tab == 2;
    for (var i = 0; i < 2; i++) {
      final b = Rect.fromLTWH(r.left + i * (bw + gap), r.top, bw, hintH - 4);
      k.box(b.shift(Offset(0, 4 * k.u)), Look.line, Look.line, 0, 8);
      k.box(b, Look.white, Look.line, 2, 8);
      final dir = i == 0 ? -1 : 1;
      final at = Offset(b.left + hintH * 0.5, b.center.dy);
      dex
          ? k.arrow(at, dir, s: hintH * 0.2)
          : k.arrowV(at, dir, s: hintH * 0.2);
      final what = dex
          ? (i == 0 ? 'Dex back' : 'Dex on')
          : (i == 0 ? 'Previous' : 'Next');
      k.say(
        what,
        Offset(b.left + hintH, b.center.dy + hintH * 0.15),
        Face.title,
        hintH * 0.38,
        Look.ink,
        maxW: bw - hintH - 4,
      );
      _hit(
        b,
        dex
            ? (i == 0 ? HitKind.dexPrev : HitKind.dexNext)
            : (i == 0 ? HitKind.checkPrev : HitKind.checkNext),
      );
    }
    final b = k.button(
      'B',
      'Back',
      Offset(r.left + 2 * (bw + gap), r.top),
      w: bw,
      h: hintH - 4,
    );
    _hit(b, HitKind.button, 3);
  }

  void _compactStatus(Rect r, Mon m, bool tall) {
    final k = _k;
    final fs = tall ? 13.0 : 11.0;
    final f = math.min(
      math.min(r.height * 0.45, r.width * (tall ? 0.48 : 0.34)),
      tall ? 220.0 : 170.0,
    );
    final frame = Rect.fromLTWH(r.left, r.top, f, f);
    k.checker(frame, const Color(0xFFFFF3D6), const Color(0xFFFFE8B8));
    final ps = ((f - 8) / 48).floor() * 48.0;
    _picture(m, frame.center, ps <= 0 ? f - 8 : ps, f * 0.6);
    final x = frame.right + 10;
    final tw = r.right - x;
    var y = r.top + fs + 4;
    final nw = k.say(
      m.shownName,
      Offset(x, y),
      Face.title,
      fs + 4,
      Look.ink,
      maxW: tw - 36,
    );
    if (m.shiny) {
      k.star(Offset(x + nw + 27, y - fs * 0.45), fs * 0.6, Look.star);
    }
    if (m.gender < 2 && !m.egg) {
      k.genderMark(
        Offset(x + nw + 9, y - fs * 0.45),
        m.gender == 0,
        s: fs / 22,
      );
    }
    final lines = [
      m.egg ? 'Egg' : _kind(m),
      'OT ${m.ot.isEmpty ? '?' : m.ot} · caught in ${m.origin.isEmpty ? '?' : m.origin}',
      'Held item: ${m.item.isEmpty ? 'none' : m.item}',
      c.holding ? 'Carried, from ${c.heldWhere}' : c.whereText,
      if (m.fromSave.isNotEmpty) 'came from ${m.fromSave}',
    ];
    final lh = fs + 5;
    for (final l in lines) {
      if (y + lh > frame.bottom + 2) break;
      y += lh;
      k.say(l, Offset(x, y), Face.text, fs, Look.ink, maxW: tw);
    }
    if (!m.egg && m.types.isNotEmpty && y + fs + 12 <= frame.bottom) {
      var cx = x;
      y += 5;
      for (final t in m.types) {
        cx +=
            k.chip(
              t.toUpperCase(),
              Offset(cx, y),
              Look.typeColor(t),
              fs: fs - 2,
            ) +
            4;
      }
    }
    // base stats under it all
    var sy = frame.bottom + 10;
    if (r.bottom - sy < 40) return;
    k.label('BASE STATS', Offset(r.left, sy), fs: fs - 2);
    final stats = m.stats;
    sy += (fs - 2) * 1.7 + 4;
    if (m.egg || stats.length < 6) {
      k.say(
        m.egg ? 'Hatch it first!' : 'Not known yet',
        Offset(r.left, sy + fs),
        Face.text,
        fs,
        Look.soft,
      );
      return;
    }
    k.say(
      'TOTAL ${stats.fold(0, (a, b) => a + b)}',
      Offset(r.right, sy - 6),
      Face.title,
      fs - 2,
      Look.soft,
      align: 2,
    );
    final rh = math.min((r.bottom - sy) / 6, tall ? 34.0 : 20.0);
    final nameW = k.width('SP. ATK', Face.title, fs - 1) + 10;
    final valW = k.width('255', Face.text, fs) + 6;
    for (var i = 0; i < 6; i++) {
      final y0 = sy + i * rh;
      k.say(
        Look.statNames[i],
        Offset(r.left, y0 + rh * 0.65),
        Face.title,
        fs - 1,
        Look.ink,
      );
      final bar = Rect.fromLTWH(
        r.left + nameW,
        y0 + rh * 0.2,
        r.width - nameW - valW - 4,
        rh * 0.55,
      );
      _bar(bar, stats[i], i, 1.5);
      k.say(
        '${stats[i]}',
        Offset(r.right, y0 + rh * 0.7),
        Face.text,
        fs,
        Look.ink,
        align: 2,
      );
    }
  }

  void _compactMoves(Rect r, Mon m, bool tall) {
    final k = _k;
    final fs = tall ? 14.0 : 12.0;
    k.label('MOVES', r.topLeft, fs: fs - 3);
    var y = r.top + (fs - 3) * 1.7 + 6;
    final moves = m.moves;
    if (moves.isEmpty) {
      y += fs + 4;
      k.say(
        m.egg ? "Eggs don't know moves yet" : 'No moves known',
        Offset(r.left, y),
        Face.text,
        fs,
        Look.soft,
        maxW: r.width,
      );
      y += 6;
    }
    final mh = tall ? 40.0 : 26.0;
    for (var i = 0; i < math.min(moves.length, 4); i++) {
      final b = Rect.fromLTWH(r.left, y, r.width, mh);
      k.box(b.shift(const Offset(0, 2)), Look.white, Look.line, 2, 6);
      k.box(b, Look.white, Look.line, 2, 6);
      k.say(
        moves[i],
        Offset(b.left + 10, b.center.dy + fs * 0.38),
        Face.title,
        fs + 1,
        Look.ink,
        maxW: b.width - 20,
      );
      y += mh + 6;
    }
    y += 6;
    if (r.bottom - y < 30) return;
    k.label('TRAINER MEMO', Offset(r.left, y), fs: fs - 3);
    y += (fs - 3) * 1.7 + 4;
    for (final l in _memo(m)) {
      if (y + fs + 4 > r.bottom) break;
      y += fs + 5;
      k.say(l, Offset(r.left, y), Face.text, fs, Look.ink, maxW: r.width);
    }
  }

  void _compactDex(Rect r, Mon? m, bool tall) {
    final k = _k;
    final fs = tall ? 14.0 : 12.0;
    k.say(
      '${c.owned.length} / ${PokevilleController.dexAll} in Pokéville',
      Offset(r.center.dx, r.top + fs),
      Face.title,
      fs,
      Look.ink,
      align: 1,
      maxW: r.width,
    );
    final bh = tall ? 34.0 : 26.0;
    final bw = math.min(190.0, r.width * 0.6);
    final banner = Rect.fromLTWH(r.center.dx - bw / 2, r.top + fs + 6, bw, bh);
    final cols = tall ? 6 : 10;
    final rows = PokevilleController.dexPer ~/ cols;
    final foot = tall ? 14.0 : 11.0;
    final area = Rect.fromLTRB(
      r.left,
      banner.bottom + 8,
      r.right,
      r.bottom - foot - 2,
    );
    final sw = area.width / cols;
    final sh = area.height / rows;
    final cell = Size(sw - 4, sh - 4);
    final numFs = math.max(
      7.0,
      math.min(cell.height * 0.22, tall ? 11.0 : 9.0),
    );
    final used = Size(sw * cols, sh * rows);
    _dexGrid(
      banner: banner,
      bannerFs: tall ? 17 : 14,
      area: Rect.fromLTWH(
        area.left + (area.width - used.width) / 2 + 2,
        area.top,
        used.width,
        used.height,
      ),
      cols: cols,
      cell: cell,
      step: Size(sw, sh),
      numFs: numFs,
      m: m,
    );
    k.say(
      'Lit = in Pokéville. Dark = not in the Box yet.',
      Offset(r.left, r.bottom),
      Face.text,
      foot - 2,
      Look.soft,
      maxW: r.width,
    );
  }

  // ---- the X menu ------------------------------------------------------------------

  void _menu(LayoutKind kind) {
    final k = _k;
    final wide = kind == LayoutKind.wide;
    final all = wide
        ? const Rect.fromLTWH(-2000, -200, 6000, 1600)
        : Offset.zero & _size;
    k.c.drawRect(all, Paint()..color = Look.line.withValues(alpha: 0.35));
    final panel = wide
        ? const Rect.fromLTWH(560, 150, 800, 820)
        : Rect.fromLTRB(12, 12, _size.width - 12, _size.height - 12).intersect(
            Rect.fromCenter(
              center: _size.center(Offset.zero),
              width: 520,
              height: _size.height - 24,
            ),
          );
    _hit(all, HitKind.menuOutside);
    k.panel(panel);
    _hit(panel, HitKind.menuRow, -1); // inside but not a row: nothing
    final s = wide ? 1.0 : 0.5;
    final pad = 24 * s;
    k.label(
      'POKéVILLE',
      panel.topLeft + Offset(pad, 20 * s),
      fs: 20 * math.max(s, 0.55),
    );
    k.say(
      'A open   B close',
      panel.topLeft + Offset(panel.width - 30 * s, 46 * s),
      Face.title,
      wide ? 20 : 11,
      Look.soft,
      align: 2,
    );
    final rowH = wide ? 70.0 : (kind == LayoutKind.side ? 32.0 : 44.0);
    final gap = wide ? 8.0 : 5.0;
    final footH = wide ? 60.0 : 30.0;
    final listTop = panel.top + (wide ? 76 : 40);
    final visible = math.max(
      1,
      ((panel.bottom - footH - listTop) / (rowH + gap)).floor(),
    );
    final rows = c.menuRows;
    final first = (c.menuIndex - visible ~/ 2)
        .clamp(0, math.max(0, rows.length - visible))
        .toInt();
    final tfs = wide ? 28.0 : (kind == LayoutKind.side ? 13.0 : 15.0);
    final dfs = wide ? 22.0 : 11.0;
    for (var j = 0; j < math.min(visible, rows.length); j++) {
      final i = first + j;
      final row = rows[i];
      final r = Rect.fromLTWH(
        panel.left + pad,
        listTop + j * (rowH + gap),
        panel.width - 2 * pad,
        rowH,
      );
      final on = i == c.menuIndex;
      final off = !row.enabled;
      k.box(
        r,
        on ? Look.lit : (off ? const Color(0xFFF1F2FB) : Look.white),
        on ? Look.gold : (off ? const Color(0xFFB9BDE8) : Look.line),
        4 * k.u * (wide ? 1 : 1.5),
        10 * k.u * (wide ? 1 : 1.5),
      );
      _hit(r, HitKind.menuRow, i);
      var x = r.left + 18 * s;
      if (row.box != null) {
        final sw = Rect.fromLTWH(x, r.top + rowH * 0.2, rowH * 0.8, rowH * 0.6);
        k.box(sw, Look.line, Look.line, 0, 6 * s);
        k.wallpaper(sw.deflate(2), Look.wallOf(row.box!), 5 * s);
        x = sw.right + 14 * s;
      } else {
        x +=
            k.chip(
              'PC',
              Offset(x, r.center.dy - (dfs + 16 * dfs / 22) / 2),
              const Color(0x738A8FB8),
              fs: dfs,
            ) +
            14 * s;
      }
      final ink = off ? Look.faint : Look.ink;
      final dw = k.width(row.detail, Face.text, dfs);
      k.say(
        row.title,
        Offset(x, r.center.dy + tfs * 0.36),
        Face.title,
        tfs,
        ink,
        maxW: r.right - x - dw - 30 * s,
      );
      k.say(
        row.detail,
        Offset(r.right - 18 * s, r.center.dy + dfs * 0.36),
        Face.text,
        dfs,
        off ? Look.faint : Look.soft,
        align: 2,
      );
      if (row.box == c.page) {
        k.c.drawCircle(
          Offset(r.left - 10 * s, r.center.dy),
          6 * s,
          Paint()..color = Look.red,
        );
      }
    }
    if (first > 0) {
      k.arrowV(Offset(panel.center.dx, listTop - 10 * s), -1, s: 10 * s);
    }
    if (first + visible < rows.length) {
      k.arrowV(
        Offset(panel.center.dx, panel.bottom - footH + 4 * s),
        1,
        s: 10 * s,
      );
    }
    k.say(
      'Games: moving Pokémon in and out of them happens on the PC.',
      Offset(panel.center.dx, panel.bottom - 22 * s),
      Face.text,
      wide ? 20 : 10,
      Look.soft,
      align: 1,
      maxW: panel.width - 40 * s,
    );
  }

  // ---- notices and messages ---------------------------------------------------------

  void _notice(LayoutKind kind) {
    final text = c.notice;
    if (text.isEmpty) return;
    final k = _k;
    final wide = kind == LayoutKind.wide;
    final fs = wide ? 24.0 : 12.0;
    final double maxW = wide ? 1400 : _size.width - 16;
    final w = math.min(k.width(text, Face.title, fs) + fs * 2, maxW);
    final cy = wide
        ? (c.view == PokeView.check ? 990.0 : _grid.bottom - 5)
        : _size.height -
              (kind == LayoutKind.tall ? 12 + 86 + 30 : 8 + _hintH + 24);
    final cx = wide
        ? (c.view == PokeView.check ? 960.0 : _grid.center.dx)
        : _size.width / 2;
    final r = Rect.fromCenter(
      center: Offset(cx, cy),
      width: w,
      height: fs * 2.1,
    );
    k.panel(r, fill: Look.white, radius: 10, rings: false);
    k.say(
      text,
      Offset(r.center.dx, r.center.dy + fs * 0.38),
      Face.title,
      fs,
      Look.ink,
      align: 1,
      maxW: w - fs * 1.2,
    );
  }

  void _message(LayoutKind kind) {
    final k = _k;
    final wide = kind == LayoutKind.wide;
    final size = wide ? const Size(1920, 1080) : _size;
    final s = wide ? 1.0 : 0.5;
    final r = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: math.min(1100 * s * (wide ? 1 : 1.6), size.width - 24),
      height: math.min(480 * s * (wide ? 1 : 1.3), size.height - 24),
    );
    k.panel(r);
    final (title, lines) = switch (c.state) {
      null => ('Opening Pokéville…', <String>[]),
      BoxState.missing => (
        'No Pokéville here yet',
        [
          'Pokéville comes from the PC through Cross-Save;',
          'sync first, then come back.',
        ],
      ),
      _ => (
        "Pokéville couldn't be read",
        [
          "box.json is there but it isn't a Box I can read",
          'Sync again from the PC. ${c.error ?? ''}',
        ],
      ),
    };
    k.label(
      'POKéVILLE',
      r.topLeft + Offset(24 * s, 20 * s),
      fs: wide ? 20 : 11,
    );
    final fs = wide ? 40.0 : 17.0;
    var y = r.top + 120 * s + fs;
    k.say(
      title,
      Offset(r.center.dx, y),
      Face.title,
      fs,
      Look.ink,
      align: 1,
      maxW: r.width - 40 * s,
    );
    for (final l in lines) {
      y += wide ? 48 : 22;
      k.say(
        l,
        Offset(r.center.dx, y),
        Face.text,
        wide ? 26 : 12,
        Look.soft,
        align: 1,
        maxW: r.width - 40 * s,
      );
    }
    final bh = wide ? 58.0 : 36.0;
    final b = k.button(
      'B',
      'Back',
      Offset(r.center.dx - (wide ? 90 : 55), r.bottom - bh - 24 * s),
      w: wide ? 180 : 110,
      h: bh,
    );
    _hit(b, HitKind.button, 3);
  }

  // ---- words ------------------------------------------------------------------------------

  static String _three(int n) => n.toString().padLeft(3, '0');

  static String _pokemon(int n) => n == 1 ? '1 Pokémon' : '$n Pokémon';

  static String _kind(Mon m) =>
      'No.${_three(m.species)} ${m.name.isEmpty ? '?' : m.name} · Lv.${m.level}';

  static String _otLine(Mon m) {
    var line = m.ot.isNotEmpty ? 'OT ${m.ot}' : '';
    if (m.origin.isNotEmpty) {
      line += '${line.isEmpty ? '' : ' · '}from ${m.origin}';
    }
    return line;
  }

  @override
  bool shouldRepaint(PokevillePainter old) => true;
}
