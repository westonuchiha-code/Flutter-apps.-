/// Small pieces every page uses: sizes for wide and compact screens,
/// text styles, boxes, sheet rows, badges, the hints bar, the padlock and
/// tick, and a scroller that keeps the highlighted thing on screen.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

import '../art/art.dart';
import '../texts.dart';

/// The PC's colours that [Look] doesn't have.
abstract final class Tone {
  static const soft2 = Color(0xFFC5C9FF);
  static const edge2 = Color(0xFF4F55C4);
  static const panelSoft = Color(0xA60A0C48);
  static const panelOn = Color(0xFF070838);
  static const holds = Color(0xFF8F97FF);
  static const onYellow = Color(0xFF15130A);
  static const optionEdge = Color(0xFF3B42B4);
  static const optionFill = Color(0xFF14176A);
  static const dangerEdge = Color(0xFFA03058);
  static const holeFill = Color(0x2E15175E);
  static const holeEdge = Color(0x24C9CEFF);
  static const markFill = Color(0x22FFE23A);
  static const rule = Color(0x88343A9E);
  static const buttons = {
    'A': Color(0xFF22A447),
    'B': Color(0xFFD93A3A),
    'X': Color(0xFF2D67E0),
    'Y': Color(0xFFE5B51D),
  };
}

/// How big things are: wide screens use the PC's 1920×1080 layout,
/// stretched to fit ([sx], [sy]) with words and icons scaled by [u];
/// compact screens (a phone, the Retroid's ~450×390 dp) have their own.
class Dims {
  /// Sizes for a page of [size].
  Dims(this.size)
    : compact = size.width < compactWidth || size.height < compactHeight;

  /// Below this width (or [compactHeight]) the compact layout is used.
  static const compactWidth = 1000.0, compactHeight = 600.0;

  /// The page.
  final Size size;

  /// Phone / handheld layout.
  final bool compact;

  /// Across / down per PC pixel.
  double get sx => size.width / 1920;
  double get sy => size.height / 1080;

  /// Words and icons per PC pixel.
  double get u => math.min(sx, sy);

  /// A PC rectangle on this page.
  Rect pc(double x, double y, double w, double h) =>
      Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy);

  /// [child] in the PC rectangle (x, y, w, h).
  Widget at(double x, double y, double w, double h, Widget child) =>
      Positioned.fromRect(rect: pc(x, y, w, h), child: child);

  /// Wider than tall (the Retroid, a phone on its side).
  bool get landscape => size.width > size.height;
}

/// Plain words.
TextStyle body(double size, [Color color = Colors.white]) =>
    TextStyle(fontSize: size, color: color, height: 1.2);

/// Bold words.
TextStyle bold(double size, [Color color = Colors.white]) => TextStyle(
  fontSize: size,
  color: color,
  fontWeight: FontWeight.w700,
  height: 1.2,
);

/// The heavy face (the PC's Arial Black).
TextStyle heavy(double size, [Color color = Colors.white]) => TextStyle(
  fontSize: size,
  color: color,
  fontFamily: Look.fontFamily,
  fontWeight: FontWeight.w900,
  height: 1.2,
);

/// One line of words, "..." when too long.
Widget line(String text, TextStyle style, {TextAlign? align}) => Text(
  text,
  style: style,
  maxLines: 1,
  softWrap: false,
  overflow: TextOverflow.ellipsis,
  textAlign: align,
);

/// A filled box with an edge (the PC's look.box).
class Box extends StatelessWidget {
  const Box({
    super.key,
    this.child,
    this.fill = Look.panel,
    this.edge = Look.edge,
    this.width = 3,
    this.padding,
  });

  final Widget? child;
  final Color fill, edge;
  final double width;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: fill,
      border: Border.all(color: edge, width: width),
    ),
    child: child,
  );
}

/// The PC's soft white glow behind something chosen.
class Glow extends StatelessWidget {
  const Glow({super.key, this.alpha = 1, this.grow = 0, this.child});

  final double alpha;

  /// How far it reaches past the child, each side.
  final double grow;
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _GlowPainter(alpha, grow), child: child);
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.alpha, this.grow);

  final double alpha, grow;

  @override
  void paint(Canvas canvas, Size size) =>
      Look.glow(canvas, (Offset.zero & size).inflate(grow), alpha: alpha);

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.alpha != alpha || old.grow != grow;
}

/// A label on the left, its value on the right (the PC's look.row).
class InfoRow extends StatelessWidget {
  const InfoRow(
    this.label,
    this.value, {
    super.key,
    this.size = 20,
    this.color = Colors.white,
    this.rule = false,
  });

  final String label, value;
  final double size;
  final Color color;

  /// A faint line under it.
  final bool rule;

  @override
  Widget build(BuildContext context) => Container(
    decoration: rule
        ? const BoxDecoration(
            border: Border(bottom: BorderSide(color: Tone.rule)),
          )
        : null,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: line(label, body(size, Look.label))),
        SizedBox(width: size * 0.7),
        Flexible(
          flex: 2,
          child: line(value, body(size, color), align: TextAlign.right),
        ),
      ],
    ),
  );
}

/// A panel with a cyan heading and rows (THIS SAVE, THE GAME...).
class Sheet extends StatelessWidget {
  const Sheet({
    super.key,
    required this.heading,
    required this.rows,
    this.size = 21,
    this.gap = 46,
    this.pad = 24,
    this.extra,
    this.expand = true,
  });

  final String heading;
  final List<Row2> rows;
  final double size, gap, pad;

  /// Under the rows.
  final Widget? extra;

  /// Fill the height it's given (wide pages); off = as tall as its rows.
  final bool expand;

  @override
  Widget build(BuildContext context) => Box(
    padding: EdgeInsets.fromLTRB(pad, pad * 0.6, pad, pad * 0.6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        line(heading, bold(size * 0.9, Look.cyan)),
        SizedBox(height: gap * 0.2),
        for (final (k, v) in rows)
          SizedBox(
            height: gap,
            child: InfoRow(
              k,
              v,
              size: size,
              color: k == 'Copy protected' && v == 'Yes'
                  ? Look.yellow
                  : Colors.white,
            ),
          ),
        ?extra,
      ],
    ),
  );
}

/// The console pill, and TEST / FAVORITE / COPY-PROTECTED (look.badges).
class Badges extends StatelessWidget {
  const Badges(this.save, {super.key, this.size = 18, this.centred = false});

  final CardSave save;
  final double size;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final tags = <(String, Color, Color)>[
      (save.system, Look.system(save.system, 'badge'), Colors.white),
      if (save.card?.isTest() ?? false)
        ('TEST', Look.cyan, const Color(0xFF062A30)),
      if (save.favorite)
        ('FAVORITE', FavoriteSparkle.gold, const Color(0xFF3A2700)),
      if (save.copyProtected)
        ('COPY-PROTECTED', Look.warn, const Color(0xFF241A00)),
    ];
    return Wrap(
      alignment: centred ? WrapAlignment.center : WrapAlignment.start,
      spacing: size * 0.55,
      runSpacing: size * 0.3,
      children: [
        for (final (text, fill, ink) in tags)
          Container(
            height: size * 1.67,
            padding: EdgeInsets.symmetric(horizontal: size * 0.78),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(size),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(text, style: bold(size, ink).copyWith(height: 1)),
            ),
          ),
      ],
    );
  }
}

/// The button hints along the bottom: A / B / X / Y in their colours,
/// others in a box.
class HintsBar extends StatelessWidget {
  const HintsBar(this.hints, {super.key, this.size = 24});

  final List<Hint> hints;

  /// The words' size (the PC: 24 at 1080 lines).
  final double size;

  @override
  Widget build(BuildContext context) {
    if (hints.isEmpty) return const SizedBox.shrink();
    final key = size * 0.83;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, h) in hints.indexed) ...[
            if (i > 0) SizedBox(width: size * 1.9),
            if (Tone.buttons.containsKey(h.button))
              Container(
                width: size * 1.5,
                height: size * 1.5,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Tone.buttons[h.button],
                  shape: BoxShape.circle,
                ),
                child: Text(h.button, style: bold(key).copyWith(height: 1)),
              )
            else
              Container(
                height: size * 1.42,
                padding: EdgeInsets.symmetric(horizontal: size * 0.42),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Look.chip,
                  border: Border.all(color: Look.edge, width: 2),
                ),
                child: Text(h.button, style: bold(key).copyWith(height: 1)),
              ),
            SizedBox(width: size * 0.42),
            Text(h.label, style: body(size)),
          ],
        ],
      ),
    );
  }
}

/// The padlock on a copy-protected save.
class Padlock extends StatelessWidget {
  const Padlock({super.key, this.size = 24, this.alpha = 1});

  final double size, alpha;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size),
    painter: _LockPainter(Look.warn.withValues(alpha: alpha)),
  );
}

class _LockPainter extends CustomPainter {
  _LockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 24;
    final fill = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(0, 9 * k, 24 * k, 15 * k), fill);
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * k;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(12 * k, 7 * k), radius: 5.5 * k),
      math.pi,
      math.pi,
      false,
      arc,
    );
    canvas.drawLine(Offset(6.5 * k, 7 * k), Offset(6.5 * k, 10 * k), arc);
    canvas.drawLine(Offset(17.5 * k, 7 * k), Offset(17.5 * k, 10 * k), arc);
  }

  @override
  bool shouldRepaint(_LockPainter old) => old.color != color;
}

/// A tick: green on the copy screen, ink on a yellow disc for a marked
/// save in the grid.
class Tick extends StatelessWidget {
  const Tick({super.key, this.size = 36, this.disc = false});

  final double size;

  /// On a yellow disc (the grid's marked saves).
  final bool disc;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _TickPainter(disc));
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.disc);

  final bool disc;

  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 36;
    final c = Offset(18 * k, 18 * k);
    if (disc) canvas.drawCircle(c, 18 * k, Paint()..color = Look.yellow);
    final path = Path()
      ..moveTo(c.dx - 9 * k, c.dy)
      ..lineTo(c.dx - 2 * k, c.dy + 7 * k)
      ..lineTo(c.dx + 10 * k, c.dy - 7 * k);
    canvas.drawPath(
      path,
      Paint()
        ..color = disc ? Look.ink : Look.good
        ..style = PaintingStyle.stroke
        ..strokeWidth = (disc ? 5 : 7) * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.disc != disc;
}

/// A yellow option / picker row when [on], else a dark one.
class ChoiceBox extends StatelessWidget {
  const ChoiceBox({
    super.key,
    required this.on,
    required this.child,
    this.danger = false,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.dark = Tone.optionFill,
    this.edge = Tone.optionEdge,
  });

  final bool on, danger;
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final EdgeInsetsGeometry padding;
  final Color dark, edge;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    onLongPress: onLongPress,
    child: Box(
      fill: on ? Look.yellow : dark,
      edge: on ? Colors.white : (danger ? Tone.dangerEdge : edge),
      width: 2,
      padding: padding,
      child: child,
    ),
  );
}

/// A scroller that keeps item [selected] in sight (the d-pad moves it; the
/// finger scrolls freely). [itemExtent] = one row's height; [perRow] items
/// share a row.
class KeepInSight extends StatefulWidget {
  const KeepInSight({
    super.key,
    required this.selected,
    required this.itemExtent,
    required this.builder,
    this.perRow = 1,
  });

  /// The item to keep in sight (-1 = none).
  final int selected;
  final double itemExtent;
  final int perRow;

  /// Builds the scrolling child with the controller to give it.
  final Widget Function(BuildContext context, ScrollController scroll) builder;

  @override
  State<KeepInSight> createState() => _KeepInSightState();
}

class _KeepInSightState extends State<KeepInSight> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(false));
  }

  @override
  void didUpdateWidget(KeepInSight old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected ||
        old.perRow != widget.perRow ||
        old.itemExtent != widget.itemExtent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow(true));
    }
  }

  void _follow(bool animate) {
    if (!mounted || !_scroll.hasClients || widget.selected < 0) return;
    final pos = _scroll.position;
    final row = widget.selected ~/ math.max(widget.perRow, 1);
    final top = row * widget.itemExtent;
    final bottom = top + widget.itemExtent;
    var to = pos.pixels;
    if (top < pos.pixels) {
      to = top;
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      to = bottom - pos.viewportDimension;
    }
    to = to.clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((to - pos.pixels).abs() < 0.5) return;
    if (animate) {
      _scroll.animateTo(
        to,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(to);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _scroll);
}

/// The toast-like line for a notice.
class NoticeBox extends StatelessWidget {
  const NoticeBox(this.text, {super.key, this.size = 24, this.maxWidth = 1500});

  final String text;
  final double size, maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Box(
      fill: Tone.panelOn,
      edge: Look.yellow,
      padding: EdgeInsets.symmetric(
        horizontal: size * 1.2,
        vertical: size * 0.45,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: body(size, Look.yellow),
      ),
    ),
  );
}

/// Scrolls its scroller to show [child] whenever [active] turns on.
class EnsureVisible extends StatefulWidget {
  const EnsureVisible({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<EnsureVisible> createState() => _EnsureVisibleState();
}

class _EnsureVisibleState extends State<EnsureVisible> {
  @override
  void initState() {
    super.initState();
    if (widget.active) _show();
  }

  @override
  void didUpdateWidget(EnsureVisible old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _show();
  }

  void _show() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 160),
    );
  });

  @override
  Widget build(BuildContext context) => widget.child;
}
