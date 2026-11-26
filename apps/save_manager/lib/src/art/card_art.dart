/// The little memory card drawing (its console's colours, or the card's
/// own colour, finish and sticker) and the row of 15 blocks under a card
/// (ported from the PC's MemoryCardLook.memory_card / blocks).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

import 'art_images.dart';
import 'look.dart';

class CardArt extends StatelessWidget {
  const CardArt(
    this.card, {
    super.key,
    this.width = 72,
    this.selected = false,
    this.system,
  });

  /// null = the plain card of [system].
  final MemoryCard? card;
  final double width;

  /// A yellow rim, like the chosen card's row on the PC.
  final bool selected;

  /// The console when there's no [card] (e.g. "copy to a new PS2 card").
  final String? system;

  /// Height per width of the drawing.
  static const aspect = 1.3;

  @override
  Widget build(BuildContext context) {
    final sys = card?.system ?? system ?? 'PS2';
    return Semantics(
      image: true,
      label: '$sys memory card',
      child: SizedBox(
        width: width,
        height: width * aspect,
        child: CustomPaint(painter: CardPainter(card, sys, selected)),
      ),
    );
  }
}

class CardPainter extends CustomPainter {
  CardPainter(this.card, this.system, this.selected)
    : super(repaint: ArtImages.loaded);

  final MemoryCard? card;
  final String system;
  final bool selected;

  static const _outline = [
    Offset(8, 3), Offset(92, 3), Offset(97, 8), Offset(97, 112), //
    Offset(82, 127), Offset(18, 127), Offset(3, 112), Offset(3, 8),
  ];

  static double _value(Color c) => math.max(c.r, math.max(c.g, c.b));
  static Color _lighter(Color c, double k) => Color.lerp(c, Colors.white, k)!;
  static Color _darker(Color c, double k) => Color.lerp(c, Colors.black, k)!;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    Offset at(double x, double y) => Offset(x * k, y * k);
    final shape = Path()..addPolygon([for (final p in _outline) p * k], true);
    var shell = Look.system(system, 'shell');
    var edge = Look.system(system, 'edge');
    var finish = '';
    final c = card;
    if (c != null && c.color != 0) {
      shell = Color(c.color | 0xFF000000);
      finish = c.finish;
      edge = _value(shell) > 0.35
          ? _darker(shell, 0.45)
          : _lighter(shell, 0.35);
    }
    if (selected) {
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9 * k
          ..strokeJoin = StrokeJoin.round
          ..color = Look.yellow,
      );
    }
    if (finish == 'clear') {
      // See-through plastic: the circuit board shows.
      canvas.drawPath(
        shape,
        Paint()..color = _lighter(shell, 0.15).withValues(alpha: 0.55),
      );
      _board(canvas, k);
      canvas.drawRect(
        Rect.fromLTWH(9 * k, 9 * k, 82 * k, 100 * k),
        Paint()..color = shell.withValues(alpha: 0.2),
      );
      canvas.drawLine(
        at(12, 6),
        at(88, 6),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = 2 * k,
      );
      edge = _darker(shell, 0.2);
    } else {
      canvas.drawPath(shape, Paint()..color = shell);
      if (finish.isNotEmpty) {
        canvas.save();
        canvas.clipPath(shape);
        _pattern(canvas, finish, k, shell);
        canvas.restore();
      }
    }
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * k
        ..strokeJoin = StrokeJoin.round
        ..color = edge,
    );
    final grooves =
        (_value(shell) < 0.4 ? _lighter(shell, 0.14) : _darker(shell, 0.2))
            .withValues(alpha: finish == 'clear' ? 0.8 : 1);
    for (final y in const [88.0, 97.0, 106.0]) {
      canvas.drawLine(
        at(24, y),
        at(76, y),
        Paint()
          ..color = grooves
          ..strokeWidth = 4 * k
          ..strokeCap = StrokeCap.round,
      );
    }
    final label = Rect.fromLTWH(14 * k, 16 * k, 72 * k, 58 * k);
    final sticker = c?.stickerImage;
    final tex = sticker == null ? null : ArtImages.peek(sticker);
    if (tex != null) {
      // Like a real sticker: it fills the label, cropped to fit.
      final tw = tex.width.toDouble(), th = tex.height.toDouble();
      final want = label.width / label.height;
      final src = tw / th > want
          ? Rect.fromLTWH((tw - th * want) / 2, 0, th * want, th)
          : Rect.fromLTWH(0, (th - tw / want) / 2, tw, tw / want);
      canvas.drawImageRect(
        tex,
        src,
        label,
        Paint()..filterQuality = ui.FilterQuality.medium,
      );
      canvas.drawRect(
        label,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, 1.5 * k)
          ..color = Colors.white.withValues(alpha: 0.35),
      );
      return;
    }
    final short = system == 'NEO GEO'
        ? 'NEO'
        : (system == 'SATURN' ? 'SAT' : system);
    if (finish == 'clear') {
      // Like the real crystal cards: no label, the name on the plastic.
      _word(
        canvas,
        short,
        at(51.5, 54.5),
        22 * k,
        Colors.black.withValues(alpha: 0.5),
      );
      _word(canvas, short, at(50, 53), 22 * k, Colors.white);
      return;
    }
    canvas.drawRect(label, Paint()..color = Look.system(system, 'label'));
    _word(canvas, short, at(50, 45), 22 * k, Look.system(system, 'ink'));
  }

  /// Bold words centred on [mid].
  void _word(Canvas canvas, String s, Offset mid, double fs, Color col) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: fs,
          fontFamily: Look.fontFamily,
          fontWeight: FontWeight.w900,
          color: col,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    var scale = 1.0;
    final room = 66 / 22 * fs; // the label's width
    if (tp.width > room) scale = room / tp.width;
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.scale(scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    tp.dispose();
  }

  /// The green board with its gold lines, seen through a crystal shell.
  void _board(Canvas canvas, double k) {
    canvas.drawRect(
      Rect.fromLTWH(9 * k, 9 * k, 82 * k, 100 * k),
      Paint()..color = const Color(0xFF1F8F45),
    );
    final gold = Paint()
      ..color = const Color(0xFFD9C27A)
      ..strokeWidth = math.max(1, 1.2 * k);
    for (final y in const [24.0, 40.0, 58.0, 76.0, 94.0]) {
      canvas.drawLine(Offset(14 * k, y * k), Offset(60 * k, y * k), gold);
      canvas.drawLine(Offset(60 * k, y * k), Offset(70 * k, (y + 8) * k), gold);
    }
    for (var i = 0; i < 12; i++) {
      canvas.drawCircle(
        Offset((20 + (i % 6) * 12) * k, (32 + (i ~/ 6) * 40) * k),
        1.6 * k,
        gold,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(62 * k, 48 * k, 20 * k, 26 * k),
      Paint()..color = const Color(0xFF1B1B1F),
    );
  }

  /// The patterned shells: spots and blobs at fixed places, so a card looks
  /// the same every time.
  void _pattern(Canvas canvas, String finish, double k, Color base) {
    final area = Rect.fromLTWH(6 * k, 7 * k, 88 * k, 103 * k);
    final rng = math.Random(Bytes.hash(finish));
    Offset spot() =>
        area.topLeft +
        Offset(rng.nextDouble() * area.width, rng.nextDouble() * area.height);
    Paint fill(Color c) => Paint()..color = c;
    switch (finish) {
      case 'carbon':
        final s = 4 * k;
        final p = fill(_lighter(base, 0.18));
        for (var gy = 0; gy < (area.height / s).floor(); gy++) {
          for (var gx = 0; gx < (area.width / s).floor(); gx++) {
            if ((gx + gy).isEven) {
              canvas.drawRect(
                Rect.fromLTWH(area.left + gx * s, area.top + gy * s, s, s),
                p,
              );
            }
          }
        }
      case 'leopard':
        for (var i = 0; i < 22; i++) {
          final p = spot();
          final r = (3 + rng.nextDouble() * 3) * k;
          canvas.drawCircle(p, r, fill(const Color(0xFF3A2412)));
          canvas.drawCircle(p, r * 0.55, fill(_darker(base, 0.25)));
        }
      case 'camo':
        const cols = [Color(0xFF2F3B22), Color(0xFF7A6A43), Color(0xFF8A9A5B)];
        for (var i = 0; i < 26; i++) {
          final p = spot();
          final c = fill(cols[i % 3]);
          canvas.drawCircle(p, (5 + rng.nextDouble() * 6) * k, c);
          canvas.drawCircle(
            p + Offset(4 * k, 3 * k),
            (3 + rng.nextDouble() * 4) * k,
            c,
          );
        }
      case 'zebra':
        final stripe = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5 * k
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF16161A);
        for (var i = 0; i < 9; i++) {
          final y = area.top + (i * 12 + 4) * k;
          canvas.drawPath(
            Path()..addPolygon([
              for (var x = 0; x < 9; x++)
                Offset(
                  area.left + x * area.width / 8,
                  y + math.sin(x * 1.3 + i) * 3.5 * k,
                ),
            ], false),
            stripe,
          );
        }
      case 'strawberry':
        for (var i = 0; i < 14; i++) {
          final p = spot();
          canvas.drawCircle(p, 4.5 * k, fill(const Color(0xFFE0303F)));
          canvas.drawCircle(
            p + Offset(0, -4 * k),
            2.2 * k,
            fill(const Color(0xFF3F9B3A)),
          );
          final seed = fill(const Color(0xFFFFE9A0));
          canvas.drawCircle(p + Offset(-1.5 * k, 1 * k), 0.7 * k, seed);
          canvas.drawCircle(p + Offset(1.5 * k, 0), 0.7 * k, seed);
        }
    }
  }

  @override
  bool shouldRepaint(CardPainter old) =>
      old.card != card || old.system != system || old.selected != selected;
}

/// The row of [MemoryCard.blocksShown] blocks: yellow = [save]'s, cyan =
/// used, dark = free.
class BlockBar extends StatelessWidget {
  const BlockBar(
    this.card, {
    super.key,
    this.save,
    this.height = 14,
    this.width,
  });

  final MemoryCard card;
  final CardSave? save;
  final double height;

  /// null = as wide as it's allowed.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final lit = card.litBlocks(save);
    return Semantics(
      label: card.freeText(),
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: CustomPaint(painter: _BlocksPainter(lit.$1, lit.$2)),
      ),
    );
  }
}

class _BlocksPainter extends CustomPainter {
  _BlocksPainter(this.mine, this.used);

  final int mine, used;

  @override
  void paint(Canvas canvas, Size size) {
    const n = MemoryCard.blocksShown;
    // The PC's 3 px gaps on a 188 px bar, kept in proportion.
    final gap = math.max(1.0, size.width / 188 * 3);
    final step = (size.width + gap) / n;
    for (var i = 0; i < n; i++) {
      final col = i < mine
          ? Look.yellow
          : (i < used ? Look.cyan : Look.blockOff);
      canvas.drawRect(
        Rect.fromLTWH(step * i, 0, step - gap, size.height),
        Paint()..color = col,
      );
    }
  }

  @override
  bool shouldRepaint(_BlocksPainter old) =>
      old.mine != mine || old.used != used;
}
