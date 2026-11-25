import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// One entry in a column.
class XItem {
  XItem({
    required this.title,
    this.subtitle,
    this.icon = Icons.circle_outlined,
    this.art,
    this.onPress,
    this.children,
    this.options,
    this.dim = false,
    this.boxed = false,
  });

  /// Drawn in a framed box (games, like the PC menu).
  final bool boxed;

  final String title;
  final String? subtitle;
  final IconData icon;

  /// A picture file shown instead of the icon (game art).
  final String? art;

  /// A: does this.
  final VoidCallback? onPress;

  /// A: opens a folder with these (built when opened).
  final List<XItem> Function()? children;

  /// Y: the options panel.
  final List<XOption> Function()? options;

  /// Drawn fainter (hidden games).
  final bool dim;
}

class XOption {
  const XOption(this.label, this.run, {this.danger = false});
  final String label;

  /// Runs when chosen; the panel closes first.
  final VoidCallback run;
  final bool danger;
}

class XCategory {
  const XCategory(this.id, this.name, this.icon, this.items);
  final String id, name;
  final IconData icon;
  final List<XItem> Function() items;
}

/// A panel on the right: a title, some lines of text and choices.
class XPanel {
  XPanel({required this.title, this.lines = const [], List<XOption>? options})
    : options = options ?? [XOption('OK', () {})];
  final String title;
  final List<String> lines;
  final List<XOption> options;
  int index = 0;
}

class _Folder {
  _Folder(this.item, this.items);
  final XItem item;
  List<XItem> items;
  int index = 0;
}

/// Buttons the menu understands (whatever device they came from).
enum XButton { up, down, left, right, a, b, x, y, lb, rb, start }

/// The cross-media bar: categories across, items down, folders and a right
/// panel. Controller (d-pad, A/B/Y, LB/RB), keyboard and touch.
class XmbView extends StatefulWidget {
  const XmbView({
    super.key,
    required this.categories,
    this.initialCategory = 0,
    this.swapAB = false,
    this.status,
    this.revision = 0,
  });

  final List<XCategory> categories;
  final int initialCategory;

  /// Nintendo-style layouts: the right face button confirms.
  final bool swapAB;

  /// Text under the clock (e.g. "RetroArch · PPSSPP").
  final String? status;

  /// Bump to rebuild the visible items (the menu's data changed).
  final int revision;

  @override
  State<XmbView> createState() => XmbViewState();
}

class XmbViewState extends State<XmbView> with SingleTickerProviderStateMixin {
  late int _cat = widget.initialCategory;
  final _index = <int, int>{};
  final _folders = <_Folder>[];
  XPanel? _panel;
  late List<XItem> _items = widget.categories[_cat].items();
  final _focus = FocusNode();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  late double _catPos = _cat.toDouble();
  double _itemPos = 0;
  String? _toast;
  double _toastLeft = 0;

  // Touch drags.
  double _dragX = 0, _dragY = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(XmbView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) refresh();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.016
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _time += dt;
    final k = 1 - math.exp(-dt * 14);
    _catPos += (_cat - _catPos) * k;
    _itemPos += (_selected - _itemPos) * k;
    if (_toastLeft > 0) {
      _toastLeft -= dt;
      if (_toastLeft <= 0) _toast = null;
    }
    setState(() {});
  }

  int get _selected =>
      _folders.isNotEmpty ? _folders.last.index : (_index[_cat] ?? 0);
  set _selected(int v) {
    if (_folders.isNotEmpty) {
      _folders.last.index = v;
    } else {
      _index[_cat] = v;
    }
  }

  List<XItem> get _visible =>
      _folders.isNotEmpty ? _folders.last.items : _items;

  /// Rebuilds the items on screen (after the data changed).
  void refresh() {
    _items = widget.categories[_cat].items();
    for (final f in _folders) {
      final make = f.item.children;
      if (make != null) f.items = make();
    }
    final n = _visible.length;
    if (_selected >= n) _selected = math.max(0, n - 1);
    setState(() {});
  }

  /// A short message at the bottom.
  void toast(String text) => setState(() {
    _toast = text;
    _toastLeft = 3.5;
  });

  void showPanel(XPanel p) => setState(() => _panel = p);

  /// Closes every folder (e.g. after the ROMs folder was chosen).
  void closeFolders() => setState(() {
    _folders.clear();
    _items = widget.categories[_cat].items();
    _itemPos = _selected.toDouble();
  });

  void press(XButton b) {
    if (widget.swapAB) {
      if (b == XButton.a) {
        b = XButton.b;
      } else if (b == XButton.b) {
        b = XButton.a;
      }
    }
    final panel = _panel;
    if (panel != null) {
      switch (b) {
        case XButton.up:
          panel.index = (panel.index - 1).clamp(0, panel.options.length - 1);
        case XButton.down:
          panel.index = (panel.index + 1).clamp(0, panel.options.length - 1);
        case XButton.a:
          final o = panel.options[panel.index];
          _panel = null;
          o.run();
        case XButton.b || XButton.y:
          _panel = null;
        default:
      }
      setState(() {});
      return;
    }
    final items = _visible;
    switch (b) {
      case XButton.up:
        if (_selected > 0) _selected--;
      case XButton.down:
        if (_selected < items.length - 1) _selected++;
      case XButton.left || XButton.right:
        if (_folders.isNotEmpty) {
          if (b == XButton.left) _back();
          break;
        }
        final c = (_cat + (b == XButton.left ? -1 : 1)).clamp(
          0,
          widget.categories.length - 1,
        );
        if (c != _cat) {
          _cat = c;
          _items = widget.categories[_cat].items();
          _itemPos = _selected.toDouble();
        }
      case XButton.a:
        if (items.isNotEmpty) _activate(items[_selected]);
      case XButton.b:
        _back();
      case XButton.y:
        if (items.isNotEmpty) _optionsFor(items[_selected]);
      case XButton.lb || XButton.rb:
        _jump(b == XButton.rb ? 1 : -1);
      default:
    }
    setState(() {});
  }

  void _activate(XItem item) {
    final make = item.children;
    if (make != null) {
      _folders.add(_Folder(item, make()));
      _itemPos = 0;
    } else {
      item.onPress?.call();
    }
  }

  void _optionsFor(XItem item) {
    final make = item.options;
    if (make == null) return;
    final opts = make();
    if (opts.isEmpty) return;
    _panel = XPanel(title: 'Options', options: opts);
  }

  void _back() {
    if (_folders.isNotEmpty) {
      _folders.removeLast();
      _itemPos = _selected.toDouble();
    }
  }

  /// LB / RB: to the next first letter (long lists), else by 10.
  void _jump(int dir) {
    final items = _visible;
    if (items.isEmpty) return;
    String key(int i) {
      final t = items[i].title.trim();
      return t.isEmpty ? '' : t[0].toUpperCase();
    }

    final here = key(_selected);
    var i = _selected;
    if (dir > 0) {
      while (i < items.length - 1 && key(i) == here) {
        i++;
      }
    } else {
      // To the start of this letter, or of the previous one.
      if (i > 0 && key(i - 1) == here) {
        while (i > 0 && key(i - 1) == here) {
          i--;
        }
      } else if (i > 0) {
        i--;
        final prev = key(i);
        while (i > 0 && key(i - 1) == prev) {
          i--;
        }
      }
    }
    _selected = i;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final b = switch (k) {
      LogicalKeyboardKey.arrowUp => XButton.up,
      LogicalKeyboardKey.arrowDown => XButton.down,
      LogicalKeyboardKey.arrowLeft => XButton.left,
      LogicalKeyboardKey.arrowRight => XButton.right,
      LogicalKeyboardKey.gameButtonA ||
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.select ||
      LogicalKeyboardKey.space => XButton.a,
      LogicalKeyboardKey.gameButtonB ||
      LogicalKeyboardKey.escape ||
      LogicalKeyboardKey.backspace ||
      LogicalKeyboardKey.goBack => XButton.b,
      LogicalKeyboardKey.gameButtonX || LogicalKeyboardKey.keyX => XButton.x,
      LogicalKeyboardKey.gameButtonY ||
      LogicalKeyboardKey.keyY ||
      LogicalKeyboardKey.contextMenu => XButton.y,
      LogicalKeyboardKey.gameButtonLeft1 ||
      LogicalKeyboardKey.pageUp => XButton.lb,
      LogicalKeyboardKey.gameButtonRight1 ||
      LogicalKeyboardKey.pageDown => XButton.rb,
      LogicalKeyboardKey.gameButtonStart => XButton.start,
      _ => null,
    };
    if (b == null) return KeyEventResult.ignored;
    // Keyboard Enter/Escape are never swapped; only the pad's A/B are.
    if (widget.swapAB &&
        (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.backspace)) {
      press(b == XButton.a ? XButton.b : XButton.a);
    } else {
      press(b);
    }
    return KeyEventResult.handled;
  }

  // ---- Layout ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) press(widget.swapAB ? XButton.a : XButton.b);
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, box) {
            final g = _Geo(box.biggest);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition, g),
              onLongPressStart: (d) {
                _tap(d.localPosition, g, select: true);
                press(widget.swapAB ? XButton.y : XButton.y);
              },
              onVerticalDragStart: (_) => _dragY = 0,
              onVerticalDragUpdate: (d) {
                _dragY += d.delta.dy;
                while (_dragY.abs() > g.itemH * 0.8) {
                  final up = _dragY < 0;
                  _dragY += up ? g.itemH * 0.8 : -g.itemH * 0.8;
                  _pressRaw(up ? XButton.down : XButton.up);
                }
              },
              onHorizontalDragStart: (_) => _dragX = 0,
              onHorizontalDragUpdate: (d) {
                _dragX += d.delta.dx;
                while (_dragX.abs() > g.spacing * 0.6) {
                  final left = _dragX < 0;
                  _dragX += left ? g.spacing * 0.6 : -g.spacing * 0.6;
                  _pressRaw(left ? XButton.right : XButton.left);
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: XmbBackground(_time)),
                  ),
                  ..._categoryRow(g),
                  ..._column(g),
                  _clock(g),
                  if (_panel != null) _panelView(g, _panel!),
                  _hints(g),
                  if (_toast != null) _toastView(g),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Presses without the A/B swap (touch gestures mean what they show).
  void _pressRaw(XButton b) {
    if (widget.swapAB && (b == XButton.a || b == XButton.b)) {
      press(b == XButton.a ? XButton.b : XButton.a);
    } else {
      press(b);
    }
  }

  void _tap(Offset p, _Geo g, {bool select = false}) {
    if (_panel != null) return; // the panel handles its own taps
    // Category icons.
    if (_folders.isEmpty && (p.dy - g.rowY).abs() < g.icon * 0.9) {
      for (var i = 0; i < widget.categories.length; i++) {
        final x = g.colX + (i - _catPos) * g.spacing;
        if ((p.dx - x).abs() < g.spacing / 2) {
          if (i != _cat) {
            setState(() {
              _cat = i;
              _items = widget.categories[_cat].items();
              _itemPos = _selected.toDouble();
            });
          }
          return;
        }
      }
    }
    if (_folders.isNotEmpty && p.dx < g.colX - g.icon) {
      _pressRaw(XButton.b);
      return;
    }
    // Items: the nearest one.
    final items = _visible;
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < items.length; i++) {
      final y = g.itemY(i - _itemPos);
      final d = (p.dy - y).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best < 0 || bestD > g.itemH) return;
    if (best == _selected && !select) {
      _pressRaw(XButton.a);
    } else {
      setState(() => _selected = best);
    }
  }

  List<Widget> _categoryRow(_Geo g) {
    final out = <Widget>[];
    if (_folders.isNotEmpty) {
      // The category (dim) at the left, and the folder's name.
      final c = widget.categories[_cat];
      out.add(
        Positioned(
          left: g.colX - g.spacing * 0.95 - g.icon,
          top: g.rowY - g.icon,
          width: g.icon * 2,
          height: g.icon * 2,
          child: Opacity(
            opacity: 0.45,
            child: Icon(c.icon, color: Colors.white, size: g.icon * 0.9),
          ),
        ),
      );
      out.add(
        Positioned(
          left: g.listX,
          top: g.rowY - g.font * 1.1,
          right: 16,
          child: Text(
            _folders.last.item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _text(g.font * 1.45),
          ),
        ),
      );
      return out;
    }
    for (var i = 0; i < widget.categories.length; i++) {
      final c = widget.categories[i];
      final d = i - _catPos;
      final x = g.colX + d * g.spacing;
      if (x < -g.spacing || x > g.size.width + g.spacing) continue;
      final sel = (1 - d.abs()).clamp(0.0, 1.0);
      final size = g.icon * (0.85 + 0.35 * sel);
      out.add(
        Positioned(
          left: x - g.icon * 1.5,
          top: g.rowY - size / 2,
          width: g.icon * 3,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (sel > 0.3)
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.13 * sel),
                        blurRadius: g.icon * 0.9,
                      ),
                  ],
                ),
                child: Icon(
                  c.icon,
                  color: Colors.white.withValues(alpha: 0.7 + 0.3 * sel),
                  size: size,
                ),
              ),
              SizedBox(height: g.icon * 0.25),
              Opacity(
                opacity: sel,
                child: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: _text(g.font * 1.05),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return out;
  }

  List<Widget> _column(_Geo g) {
    final items = _visible;
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final d = i - _itemPos;
      final y = g.itemY(d);
      if (y < -g.itemH * 2 || y > g.size.height + g.itemH) continue;
      final it = items[i];
      final sel = (1 - d.abs()).clamp(0.0, 1.0);
      final above = d < -0.5;
      final box = g.itemH * (0.7 + 0.55 * sel);
      final boxW = box * 1.6;
      final alpha = (above ? 0.55 : 0.85 + 0.15 * sel) * (it.dim ? 0.5 : 1);
      out.add(
        Positioned(
          left: g.listX - boxW - g.font,
          top: y - box / 2,
          right: 12,
          height: box,
          child: Opacity(
            opacity: alpha.clamp(0.0, 1.0),
            child: Row(
              children: [
                SizedBox(width: boxW, height: box, child: _thumb(it, box)),
                SizedBox(width: g.font),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(g.font * (1.05 + 0.45 * sel)),
                      ),
                      if (it.subtitle != null && sel > 0.05)
                        Opacity(
                          opacity: sel,
                          child: Text(
                            it.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _text(
                              g.font * 0.78,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      out.add(
        Positioned(
          left: g.listX,
          top: g.itemY(0) - g.font,
          right: 16,
          child: Text(
            'Nothing here yet',
            style: _text(g.font, color: Colors.white54),
          ),
        ),
      );
    }
    return out;
  }

  Widget _thumb(XItem it, double box) {
    final art = it.art;
    if (art != null) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white38, width: 1),
        ),
        child: Image.file(
          File(art),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _iconBox(it, box),
        ),
      );
    }
    return _iconBox(it, box);
  }

  Widget _iconBox(XItem it, double box) {
    final icon = Icon(
      it.icon,
      color: Colors.white,
      size: box * (it.boxed ? 0.45 : 0.62),
      shadows: const [Shadow(color: Colors.black26, blurRadius: 6)],
    );
    if (!it.boxed) return icon;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }

  Widget _clock(_Geo g) {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final t =
        '${now.month}/${now.day}  $h:${now.minute.toString().padLeft(2, '0')} '
        '${now.hour < 12 ? 'AM' : 'PM'}';
    return Positioned(
      right: g.margin,
      top: g.margin * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(t, style: _text(g.font * 1.15)),
          if (widget.status != null)
            Text(
              widget.status!,
              style: _text(g.font * 0.7, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  Widget _hints(_Geo g) {
    final panel = _panel != null;
    final ok = widget.swapAB ? 'B' : 'A', back = widget.swapAB ? 'A' : 'B';
    final chips = <Widget>[
      _hint(g, ok, panel ? 'OK' : 'Select', const Color(0xFF3BB54A), () {
        _pressRaw(XButton.a);
      }),
      if (panel || _folders.isNotEmpty)
        _hint(g, back, 'Back', const Color(0xFFE5483C), () {
          _pressRaw(XButton.b);
        }),
      if (!panel) _hint(g, 'LB/RB', 'Jump', null, () => press(XButton.rb)),
      if (!panel)
        _hint(g, 'Y', 'Options', const Color(0xFFF2B51C), () {
          press(XButton.y);
        }),
    ];
    return Positioned(
      right: g.margin,
      bottom: g.margin * 0.6,
      child: Wrap(spacing: g.font * 1.1, children: chips),
    );
  }

  Widget _hint(_Geo g, String b, String label, Color? c, VoidCallback onTap) {
    final s = g.font * 1.25;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: s,
            constraints: BoxConstraints(minWidth: s),
            padding: EdgeInsets.symmetric(horizontal: c == null ? s * 0.3 : 0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c ?? Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(s / 2),
            ),
            child: Text(
              b,
              style: TextStyle(
                color: c == null ? const Color(0xFF1A2A4A) : Colors.white,
                fontSize: g.font * (c == null ? 0.62 : 0.78),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: g.font * 0.4),
          Text(label, style: _text(g.font * 0.95)),
        ],
      ),
    );
  }

  Widget _panelView(_Geo g, XPanel p) {
    final w = math.min(
      g.size.width * 0.9,
      math.max(g.size.width * 0.34, 320.0),
    );
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: w,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          color: const Color(0xF0101A33),
          padding: EdgeInsets.fromLTRB(
            g.margin * 0.8,
            g.margin * 2.2,
            g.margin * 0.5,
            g.margin * 2.4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.title, style: _text(g.font * 1.3)),
              SizedBox(height: g.font * 0.6),
              for (final l in p.lines)
                Padding(
                  padding: EdgeInsets.only(bottom: g.font * 0.25),
                  child: Text(
                    l,
                    style: _text(g.font * 0.85, color: Colors.white70),
                  ),
                ),
              SizedBox(height: g.font * 0.6),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < p.options.length; i++)
                      GestureDetector(
                        onTap: () {
                          setState(() => p.index = i);
                          final o = p.options[i];
                          setState(() => _panel = null);
                          o.run();
                        },
                        child: Container(
                          margin: EdgeInsets.only(bottom: g.font * 0.2),
                          padding: EdgeInsets.symmetric(
                            vertical: g.font * 0.35,
                            horizontal: g.font * 0.6,
                          ),
                          decoration: BoxDecoration(
                            color: i == p.index
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: i == p.index
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            p.options[i].label,
                            style: _text(
                              g.font * 0.95,
                              color: p.options[i].danger
                                  ? const Color(0xFFFF8A80)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toastView(_Geo g) => Positioned(
    left: g.margin,
    bottom: g.margin * 0.6,
    right: g.size.width * 0.4,
    child: Container(
      padding: EdgeInsets.all(g.font * 0.6),
      color: const Color(0xD0101A33),
      child: Text(_toast!, style: _text(g.font * 0.85)),
    ),
  );
}

TextStyle _text(double size, {Color color = Colors.white}) => TextStyle(
  color: color,
  fontSize: size,
  height: 1.2,
  shadows: const [Shadow(color: Color(0x66000000), blurRadius: 4)],
);

/// Where things go for a screen size (phone portrait to TV).
class _Geo {
  _Geo(this.size) {
    final m = math.min(size.width, size.height);
    final portrait = size.height > size.width;
    font = (m / 100 * 2.6).clamp(13.0, 30.0);
    icon = (m / 100 * 9).clamp(36.0, 96.0);
    spacing = math.max(icon * 2.1, size.width * (portrait ? 0.24 : 0.115));
    colX = size.width * (portrait ? 0.2 : 0.29);
    rowY = size.height * (portrait ? 0.2 : 0.27);
    itemH = math.max(font * 3.2, size.height * (portrait ? 0.075 : 0.092));
    margin = (m / 100 * 6).clamp(16.0, 70.0);
    // Room on the left for the selected item's box.
    listX = math.max(colX - icon * 0.1, itemH * 1.25 * 1.6 + font * 1.6);
  }

  final Size size;
  late final double font, icon, spacing, colX, rowY, itemH, margin, listX;

  /// The y of an item [d] places from the selected one.
  double itemY(double d) {
    final sel = rowY + icon * 1.05 + itemH * 0.9;
    final big = itemH * 0.55;
    final above = rowY - icon * 1.25;
    if (d >= 1) return sel + big + d * itemH;
    if (d >= 0) return sel + d * (itemH + big);
    if (d >= -1) return sel + (above - sel) * -d;
    return above + (d + 1) * itemH;
  }
}

/// The PS3-style background: a deep blue gradient with slow glowing waves.
class XmbBackground extends CustomPainter {
  XmbBackground(this.time, {this.hue = 0xFF2F6FD6});
  final double time;
  final int hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E2A63), Color(0xFF1F55B5), Color(0xFF3A7FE0)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
    final w = size.width, h = size.height;
    for (var k = 0; k < 4; k++) {
      final path = Path();
      final amp = h * (0.05 + k * 0.012);
      final mid = h * (0.56 + k * 0.035);
      final speed = 0.12 + k * 0.05;
      final freq = 1.1 + k * 0.35;
      for (var i = 0; i <= 48; i++) {
        final x = w * i / 48;
        final t = x / w * math.pi * 2 * freq + time * speed * math.pi * 2;
        final y = mid + math.sin(t) * amp + math.sin(t * 0.5 + k) * amp * 0.6;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.012
          ..color = Colors.white.withValues(alpha: 0.05)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.015),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = Colors.white.withValues(alpha: 0.28 - k * 0.04),
      );
    }
  }

  @override
  bool shouldRepaint(XmbBackground old) => old.time != time;
}
