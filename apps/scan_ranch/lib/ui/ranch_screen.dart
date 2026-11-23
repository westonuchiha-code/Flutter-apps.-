import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../model/game_state.dart';
import '../model/items.dart';
import '../render/monster_art.dart';
import '../render/ranch_background.dart';
import '../sim/ranch_sim.dart';
import 'creature_sheet.dart';

/// The field where ranch monsters roam. Tap a monster to pet it, long-press
/// for its details, pick a food and tap the ground to drop it.
class RanchScreen extends StatefulWidget {
  const RanchScreen({super.key, required this.game, required this.onScan});

  final GameState game;
  final VoidCallback onScan;

  @override
  State<RanchScreen> createState() => _RanchScreenState();
}

class _RanchScreenState extends State<RanchScreen>
    with SingleTickerProviderStateMixin {
  late final RanchSim sim = RanchSim(
    onAte: widget.game.ate,
    onPetted: widget.game.pet,
  );
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double _time = 0;
  ItemKind? _food;
  ui.Image? _background;
  Size _bgFor = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_sync);
    _sync();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    widget.game.removeListener(_sync);
    _ticker.dispose();
    _frame.dispose();
    _background?.dispose();
    super.dispose();
  }

  void _sync() {
    sim.sync(widget.game.ranch);
    if (_food != null && widget.game.count(_food!) == 0) _food = null;
    if (mounted) setState(() {});
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _time += dt;
    sim.step(dt);
    _frame.value++;
  }

  Future<void> _ensureBackground(Size size) async {
    if (size == _bgFor || size.isEmpty) return;
    _bgFor = size;
    final w = (size.width / 3).round().clamp(64, 400);
    final h = (size.height / 3).round().clamp(64, 800);
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      ranchBackground(w, h),
      w,
      h,
      ui.PixelFormat.rgba8888,
      c.complete,
    );
    final img = await c.future;
    if (!mounted) return;
    setState(() {
      _background?.dispose();
      _background = img;
    });
  }

  void _onTap(TapUpDetails d) {
    final p = d.localPosition;
    final food = _food;
    if (food != null) {
      if (p.dy < sim.groundTop) return;
      if (widget.game.useItem(food)) {
        sim.dropFood(food, p);
        HapticFeedback.selectionClick();
      }
      return;
    }
    final actor = sim.hitTest(p);
    if (actor != null) {
      sim.pet(actor);
      HapticFeedback.lightImpact();
    }
  }

  void _onLongPress(LongPressStartDetails d) {
    final actor = sim.hitTest(d.localPosition);
    if (actor != null) showCreatureSheet(context, widget.game, actor.creature);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final ranch = game.ranch;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, c) {
              final size = c.biggest;
              // Keep monsters above the food tray.
              sim.resize(Size(size.width, size.height - 110));
              _ensureBackground(size);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTap,
                onLongPressStart: _onLongPress,
                child: CustomPaint(
                  size: size,
                  painter: RanchPainter(
                    sim: sim,
                    background: _background,
                    time: () => _time,
                    repaint: _frame,
                  ),
                ),
              );
            },
          ),
        ),
        // Header.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _Pill(
                    icon: Icons.grass,
                    text: 'RANCH ${ranch.length}/$ranchCapacity',
                  ),
                  const Spacer(),
                  _Pill(
                    icon: Icons.inventory_2_outlined,
                    text: 'BOX ${game.box.length}',
                  ),
                ],
              ),
            ),
          ),
        ),
        if (ranch.isEmpty)
          Center(
            child: Card(
              color: const Color(0xE6111318),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Your ranch is empty.',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Scan any barcode to find a monster.'),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: widget.onScan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Food tray.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _FoodTray(
            game: game,
            selected: _food,
            onSelect: (k) => setState(() => _food = _food == k ? null : k),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xCC0B0C10),
      border: Border.all(color: const Color(0xFF2E3A2A)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF8CFF5A)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _FoodTray extends StatelessWidget {
  const _FoodTray({
    required this.game,
    required this.selected,
    required this.onSelect,
  });

  final GameState game;
  final ItemKind? selected;
  final ValueChanged<ItemKind> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      color: const Color(0xD90B0C10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selected == null
                ? 'Tap a monster to pet it · hold for details · pick food to feed'
                : 'Tap the ground to drop ${selected!.name}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9AA39A)),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final kind in itemKinds)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: Color(kind.color),
                        radius: 7,
                      ),
                      label: Text(
                        kind.unlimited
                            ? kind.name
                            : '${kind.name} ×${game.count(kind)}',
                      ),
                      selected: selected == kind,
                      onSelected: kind.unlimited || game.count(kind) > 0
                          ? (_) => onSelect(kind)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the field, food, monsters (with the CRT look) and effects.
class RanchPainter extends CustomPainter {
  RanchPainter({
    required this.sim,
    required this.background,
    required this.time,
    super.repaint,
  });

  final RanchSim sim;
  final ui.Image? background;
  final double Function() time;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = background;
    if (bg != null) {
      canvas.drawImageRect(
        bg,
        Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.none,
      );
    } else {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF1A2418),
      );
    }

    for (final f in sim.food) {
      _food(canvas, f);
    }

    final t = time();
    final art = MonsterArt.instance;
    final sorted = [...sim.actors]
      ..sort((a, b) => a.pos.dy.compareTo(b.pos.dy));
    for (final a in sorted) {
      final c = a.creature;
      final g = c.genome;
      final h = sim.baseSize(c) * sim.depthScale(a.pos.dy) * 1.6;
      // Shadow.
      canvas.drawOval(
        Rect.fromCenter(center: a.pos, width: h * 0.55, height: h * 0.1),
        Paint()..color = const Color(0x66000000),
      );
      final img = art.imageFor(g.silhouette, paletteFor(g, c.individual));
      if (img == null) continue;
      final inner = art.spriteRectIn(img);
      final scale = h / inner.height;
      // Motion: walking bob + lean, idle breathing, eating dip.
      final walking = a.moving;
      final bob = walking
          ? (math.sin(a.walkPhase * 2)).abs() * h * 0.035
          : math.sin(t * 2 + a.id.hashCode) * h * 0.008;
      final lean = walking ? math.sin(a.walkPhase) * 0.04 : 0.0;
      final dip = a.state == ActorState.eating ? 0.08 + a.chew * 0.06 : 0.0;
      canvas
        ..save()
        ..translate(a.pos.dx, a.pos.dy - bob - a.hop)
        ..rotate((lean + dip) * a.facing)
        ..scale(a.facing * scale, scale);
      // Feet at the origin, centred.
      canvas.drawImage(
        img,
        Offset(-inner.center.dx, -inner.bottom),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }

    for (final p in sim.particles) {
      _particle(canvas, p);
    }
  }

  void _food(Canvas canvas, FoodDrop f) {
    final drop = math.max(0.0, 1 - f.age * 4);
    final pos = f.pos.translate(0, -drop * 40);
    final r = 7.0 * (0.5 + 0.5 * f.bitesLeft / f.kind.bites);
    canvas.drawOval(
      Rect.fromCenter(center: f.pos, width: r * 2.4, height: r * 0.7),
      Paint()..color = const Color(0x55000000),
    );
    final paint = Paint()..color = Color(f.kind.color);
    final outline = Paint()
      ..color = const Color(0xFF0B0C10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromCircle(center: pos.translate(0, -r), radius: r);
    switch (f.kind.id) {
      case 'meat':
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(r * 0.4));
        canvas
          ..drawRRect(rr, paint)
          ..drawRRect(rr, outline)
          ..drawLine(
            rect.centerRight,
            rect.centerRight.translate(r * 0.7, -r * 0.4),
            Paint()
              ..color = const Color(0xFFF2EAD8)
              ..strokeWidth = 3,
          );
      case 'cake':
        final path = Path()
          ..moveTo(rect.left, rect.bottom)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.center.dx, rect.top)
          ..close();
        canvas
          ..drawPath(path, paint)
          ..drawPath(path, outline);
      default:
        canvas
          ..drawCircle(rect.center, r, paint)
          ..drawCircle(rect.center, r, outline)
          ..drawCircle(
            rect.center.translate(-r * 0.35, -r * 0.35),
            r * 0.25,
            Paint()..color = const Color(0x88FFFFFF),
          );
    }
  }

  void _particle(Canvas canvas, Particle p) {
    final alpha = (p.life / p.maxLife).clamp(0.0, 1.0);
    switch (p.kind) {
      case ParticleKind.heart:
        final s = 7.0;
        final path = Path()
          ..moveTo(p.pos.dx, p.pos.dy + s)
          ..cubicTo(
            p.pos.dx - s * 1.6,
            p.pos.dy - s * 0.2,
            p.pos.dx - s * 0.6,
            p.pos.dy - s * 1.4,
            p.pos.dx,
            p.pos.dy - s * 0.4,
          )
          ..cubicTo(
            p.pos.dx + s * 0.6,
            p.pos.dy - s * 1.4,
            p.pos.dx + s * 1.6,
            p.pos.dy - s * 0.2,
            p.pos.dx,
            p.pos.dy + s,
          );
        canvas.drawPath(
          path,
          Paint()..color = Color.fromRGBO(255, 60, 90, alpha),
        );
      case ParticleKind.crumb:
        canvas.drawRect(
          Rect.fromCenter(center: p.pos, width: 3, height: 3),
          Paint()..color = Color.fromRGBO(220, 180, 120, alpha),
        );
      case ParticleKind.sparkle:
        canvas.drawCircle(
          p.pos,
          2.5,
          Paint()..color = Color.fromRGBO(140, 255, 90, alpha),
        );
      case ParticleKind.note || ParticleKind.exclaim:
        final tp = TextPainter(
          text: TextSpan(
            text: p.kind == ParticleKind.note ? '♪' : '!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color.fromRGBO(255, 230, 80, alpha),
              shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, p.pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(RanchPainter old) => true;
}
