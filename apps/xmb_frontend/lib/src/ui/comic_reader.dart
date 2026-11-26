/// Full-screen comic / manga reader, like the PC XMB Frontend's
/// ComicReader.gd. By controller:
///   Left / Right   previous / next page, or panel in panel mode (flipped
///                  for right-to-left manga)
///   Up / Down      scroll when zoomed in
///   A              panel by panel on / off (each panel zoomed to fill)
///   X              pop out the next speech balloon; B puts it back
///   LB / RB        previous / next page, skipping panels
///   LT / RT        zoom out / in
///   Start / Y      switch reading direction for this series
///   B              close (your page is kept)
/// By touch: tap the sides to turn, the middle for the info bar; swipe to
/// turn; double-tap for panels; press and hold for a balloon; pinch to zoom.
/// The view glides between pages, panels and zoom levels.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart' show runInBackground;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../comics/book.dart';
import '../comics/bubbles.dart';
import '../comics/panels.dart';

/// Panels and balloons of a page (worked out in the background).
typedef PageMarks = ({List<PRect> panels, List<PRect> bubbles});

PageMarks _findMarks(
  (Uint8List small, int sw, int sh, Uint8List big, int bw, int bh, bool rtl) a,
) => (
  panels: findPanels(a.$1, a.$2, a.$3, rtl: a.$7),
  bubbles: findBubbles(a.$4, a.$5, a.$6, rtl: a.$7),
);

/// A grey copy of [img] at [width] wide (for the finders).
Future<(Uint8List, int, int)> greyAt(ui.Image img, int width) async {
  final h = math.max(8, (img.height * width / img.width).round());
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), h.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final small = await rec.endRecording().toImage(width, h);
  final rgba = (await small.toByteData())!.buffer.asUint8List();
  small.dispose();
  final lum = Uint8List(width * h);
  for (var i = 0; i < lum.length; i++) {
    lum[i] =
        (rgba[i * 4] * 77 + rgba[i * 4 + 1] * 150 + rgba[i * 4 + 2] * 29) >> 8;
  }
  return (lum, width, h);
}

Future<ui.Image> decodePage(PageData d, {int maxSide = 3000}) async {
  if (d.raw) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      d.bytes,
      d.width!,
      d.height!,
      ui.PixelFormat.bgra8888,
      c.complete,
    );
    return c.future;
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(d.bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final big = math.max(desc.width, desc.height);
  final s = big > maxSide ? maxSide / big : 1.0;
  final codec = await desc.instantiateCodec(
    targetWidth: (desc.width * s).round(),
    targetHeight: (desc.height * s).round(),
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  desc.dispose();
  buffer.dispose();
  return frame.image;
}

class ComicReader extends StatefulWidget {
  const ComicReader({
    super.key,
    required this.book,
    required this.startPage,
    required this.rtl,
    required this.onPlace,
    required this.onDirection,
    this.swapAB = false,
  });

  final ComicBook book;
  final int startPage;
  final bool rtl;

  /// Saves your page (0-based) as you read.
  final void Function(int page, int of) onPlace;

  /// You switched the reading direction for this series.
  final void Function(bool rtl) onDirection;
  final bool swapAB;

  @override
  State<ComicReader> createState() => _ComicReaderState();
}

class _ComicReaderState extends State<ComicReader>
    with SingleTickerProviderStateMixin {
  static const _panelPad = 0.015, _maxZoom = 4.0;

  late int _page = widget.startPage.clamp(0, widget.book.pageCount - 1);
  late bool _rtl = widget.rtl;
  final _images = <int, ui.Image>{};
  final _loading = <int, Future<ui.Image?>>{};
  final _marks = <int, PageMarks>{};
  bool _panelMode = false;
  int _panel = 0;
  double _zoom = 1;
  Offset _center = Offset.zero;
  int _bubble = -1;
  double _pop = 0;
  Rect _view = Rect.zero, _target = Rect.zero;
  Size _screen = const Size(1, 1);
  String _toast = '';
  double _toastT = 0, _infoT = 4;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final _focus = FocusNode();
  double _pinchStart = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    unawaited(_show(fromStart: true));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    for (final i in _images.values) {
      i.dispose();
    }
    super.dispose();
  }

  // ---- Pages ----

  Future<ui.Image?> _load(int i) {
    if (i < 0 || i >= widget.book.pageCount) return Future.value(null);
    final have = _images[i];
    if (have != null) return Future.value(have);
    return _loading.putIfAbsent(i, () async {
      try {
        final d = await widget.book.page(i);
        if (d == null || !mounted) return null;
        final img = await decodePage(d);
        if (!mounted) {
          img.dispose();
          return null;
        }
        _images[i] = img;
        // Keep the page and its neighbours only.
        for (final k in _images.keys.toList()) {
          if ((k - _page).abs() > 2) _images.remove(k)?.dispose();
        }
        unawaited(_analyse(i, img));
        return img;
      } finally {
        _loading.remove(i);
      }
    });
  }

  Future<void> _analyse(int i, ui.Image img) async {
    final s = await greyAt(img, panelWorkWidth);
    final b = await greyAt(img, bubbleWorkWidth);
    final m = await runInBackground(_findMarks, (
      s.$1,
      s.$2,
      s.$3,
      b.$1,
      b.$2,
      b.$3,
      _rtl,
    ));
    if (!mounted) return;
    setState(() => _marks[i] = m);
    if (i == _page && _panelMode) _aim();
  }

  Future<void> _show({bool fromStart = true}) async {
    final img = await _load(_page);
    unawaited(_load(_page + 1));
    unawaited(_load(_page - 1));
    if (!mounted || img == null) return;
    setState(() {
      _bubble = -1;
      _zoom = 1;
      _center = Offset(img.width / 2, img.height / 2);
      final panels = _marks[_page]?.panels ?? const [];
      _panel = fromStart || panels.isEmpty ? 0 : panels.length - 1;
      _aim();
      _view = _target; // a new page appears in place; moves within glide
    });
    widget.onPlace(_page, widget.book.pageCount);
  }

  ui.Image? get _img => _images[_page];

  // ---- Where to look ----

  void _aim() {
    final img = _img;
    if (img == null) return;
    final size = Size(img.width.toDouble(), img.height.toDouble());
    Rect r;
    final panels = _marks[_page]?.panels ?? const [];
    if (_panelMode && panels.isNotEmpty) {
      final p = panels[_panel.clamp(0, panels.length - 1)];
      r = Rect.fromLTWH(
        p.x * size.width,
        p.y * size.height,
        p.w * size.width,
        p.h * size.height,
      ).inflate(_panelPad * size.width);
      _center = r.center;
    } else {
      final whole = _fit(Offset.zero & size);
      r = Rect.fromCenter(
        center: _zoom <= 1 ? whole.center : _center,
        width: whole.width / _zoom,
        height: whole.height / _zoom,
      );
    }
    _target = _clamp(_fit(r), size);
    _center = _target.center;
  }

  /// [r] grown to the screen's shape.
  Rect _fit(Rect r) {
    final sa = _screen.width / _screen.height;
    var w = r.width, h = r.height;
    if (w / h > sa) {
      h = w / sa;
    } else {
      w = h * sa;
    }
    return Rect.fromCenter(center: r.center, width: w, height: h);
  }

  Rect _clamp(Rect r, Size page) {
    double along(double start, double len, double max) =>
        len >= max ? (max - len) / 2 : start.clamp(0, max - len);
    return Rect.fromLTWH(
      along(r.left, r.width, page.width),
      along(r.top, r.height, page.height),
      r.width,
      r.height,
    );
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    if (_target == Rect.zero) return;
    final k = 1 - math.exp(-dt * 10);
    final next = Rect.lerp(_view, _target, k)!;
    final popTo = _bubble >= 0 ? 1.0 : 0.0;
    final moving =
        (next.left - _view.left).abs() + (next.width - _view.width).abs() >
            0.05 ||
        (_pop - popTo).abs() > 0.001 ||
        _toastT > 0 ||
        _infoT > 0;
    if (!moving) return;
    setState(() {
      _view = next;
      _pop += (popTo - _pop) * (1 - math.exp(-dt * 14));
      _toastT = math.max(0, _toastT - dt);
      _infoT = math.max(0, _infoT - dt);
    });
  }

  void _say(String t) => setState(() {
    _toast = t;
    _toastT = 2;
  });

  // ---- Moves ----

  void _turn(int dir) {
    final next = _page + dir;
    if (next < 0 || next >= widget.book.pageCount) {
      _say(next < 0 ? 'First page' : 'Last page');
      return;
    }
    _page = next;
    unawaited(_show(fromStart: dir > 0));
  }

  /// Forward / back by panel in panel mode, else by page.
  void _step(int dir) {
    if (_bubble >= 0) {
      setState(() => _bubble = -1);
    }
    final panels = _marks[_page]?.panels ?? const [];
    if (_panelMode && panels.isNotEmpty) {
      final n = _panel + dir;
      if (n >= 0 && n < panels.length) {
        setState(() {
          _panel = n;
          _aim();
        });
        return;
      }
    }
    _turn(dir);
  }

  void _togglePanels() {
    setState(() {
      _panelMode = !_panelMode;
      _panel = 0;
      _zoom = 1;
      _aim();
    });
    final none = (_marks[_page]?.panels ?? const []).isEmpty;
    _say(
      _panelMode
          ? (none
                ? 'Panel by panel (no panels found on this page)'
                : 'Panel by panel')
          : 'Whole page',
    );
  }

  /// The balloons inside what's on screen now.
  List<PRect> _visibleBubbles() {
    final img = _img;
    final all = _marks[_page]?.bubbles ?? const [];
    if (img == null) return const [];
    // In panel mode, the balloons of this panel (not its neighbours that
    // show round it); else whatever is on screen.
    final panels = _marks[_page]?.panels ?? const [];
    final Rect v;
    if (_panelMode && panels.isNotEmpty) {
      final pn = panels[_panel.clamp(0, panels.length - 1)];
      v = Rect.fromLTWH(pn.x, pn.y, pn.w, pn.h);
    } else {
      v = Rect.fromLTWH(
        _target.left / img.width,
        _target.top / img.height,
        _target.width / img.width,
        _target.height / img.height,
      );
    }
    return [
      for (final b in all)
        if (v.contains(Offset(b.x + b.w / 2, b.y + b.h / 2))) b,
    ];
  }

  void _nextBubble() {
    final list = _visibleBubbles();
    if (list.isEmpty) {
      _say(
        _marks[_page] == null
            ? 'Still reading this page...'
            : 'No speech balloons found here',
      );
      return;
    }
    setState(() => _bubble = (_bubble + 1) % list.length);
  }

  void _zoomBy(double f) {
    setState(() {
      if (_panelMode) {
        _panelMode = false;
        _zoom = 1;
      }
      _zoom = (_zoom * f).clamp(1.0, _maxZoom);
      _aim();
    });
  }

  void _scroll(Offset d) {
    if (_zoom <= 1 && !_panelMode) return;
    setState(() {
      _center += Offset(d.dx * _target.width, d.dy * _target.height) * 0.35;
      if (_panelMode) {
        _panelMode = false;
        _zoom = _screen.width / _target.width * (_img!.width / _screen.width);
      }
      _aim();
    });
  }

  void _flipDirection() {
    setState(() => _rtl = !_rtl);
    widget.onDirection(_rtl);
    _marks.clear();
    final img = _img;
    if (img != null) unawaited(_analyse(_page, img));
    _say(_rtl ? 'Manga: right to left' : 'Comic: left to right');
  }

  void _close() {
    if (_bubble >= 0) {
      setState(() => _bubble = -1);
      return;
    }
    Navigator.of(context).maybePop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    var a =
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space;
    var b =
        k == LogicalKeyboardKey.gameButtonB ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.goBack;
    if (widget.swapAB &&
        (k == LogicalKeyboardKey.gameButtonA ||
            k == LogicalKeyboardKey.gameButtonB)) {
      final t = a;
      a = b;
      b = t;
    }
    final fwd = _rtl ? -1 : 1;
    if (a) {
      _togglePanels();
    } else if (b) {
      _close();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _step(fwd);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _step(-fwd);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _scroll(const Offset(0, -1));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _scroll(const Offset(0, 1));
    } else if (k == LogicalKeyboardKey.gameButtonX ||
        k == LogicalKeyboardKey.keyX) {
      _nextBubble();
    } else if (k == LogicalKeyboardKey.gameButtonLeft1 ||
        k == LogicalKeyboardKey.pageUp) {
      _turn(-1);
    } else if (k == LogicalKeyboardKey.gameButtonRight1 ||
        k == LogicalKeyboardKey.pageDown) {
      _turn(1);
    } else if (k == LogicalKeyboardKey.gameButtonLeft2 ||
        k == LogicalKeyboardKey.minus) {
      _zoomBy(1 / 1.4);
    } else if (k == LogicalKeyboardKey.gameButtonRight2 ||
        k == LogicalKeyboardKey.equal) {
      _zoomBy(1.4);
    } else if (k == LogicalKeyboardKey.gameButtonStart ||
        k == LogicalKeyboardKey.gameButtonY ||
        k == LogicalKeyboardKey.keyM) {
      _flipDirection();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- Touch ----

  void _tap(TapUpDetails d) {
    final x = d.localPosition.dx / _screen.width;
    final fwd = _rtl ? -1 : 1;
    if (_bubble >= 0) {
      setState(() => _bubble = -1);
    } else if (x < 0.3) {
      _step(-fwd);
    } else if (x > 0.7) {
      _step(fwd);
    } else {
      setState(() => _infoT = 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    final pageLine =
        '${widget.book.title}  ·  ${_page + 1} / ${widget.book.pageCount}'
        '${_rtl ? '  ·  Manga (right to left)' : ''}';
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, box) {
            final s = box.biggest;
            if (s != _screen) {
              _screen = s;
              _aim();
              if (_view.isEmpty) _view = _target;
            }
            // The page came in before the screen had a size: place it now.
            if (img != null && (_target.isEmpty || _view.isEmpty)) {
              _aim();
              _view = _target;
            }
            final bubbles = _bubble >= 0 ? _visibleBubbles() : const <PRect>[];
            return GestureDetector(
              onTapUp: _tap,
              onDoubleTap: _togglePanels,
              onLongPress: _nextBubble,
              onScaleStart: (_) => _pinchStart = _zoom,
              onScaleUpdate: (d) {
                if (d.pointerCount >= 2) {
                  setState(() {
                    _panelMode = false;
                    _zoom = (_pinchStart * d.scale).clamp(1.0, _maxZoom);
                    _aim();
                  });
                } else if (_zoom > 1) {
                  setState(() {
                    final k = _target.width / _screen.width;
                    _center -= d.focalPointDelta * k;
                    _aim();
                  });
                }
              },
              onScaleEnd: (d) {
                if (_zoom <= 1 && !_panelMode && d.pointerCount == 0) {
                  final vx = d.velocity.pixelsPerSecond.dx;
                  if (vx.abs() > 400) {
                    _step((vx < 0 ? 1 : -1) * (_rtl ? -1 : 1));
                  }
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: img == null
                        ? const Center(child: CircularProgressIndicator())
                        : CustomPaint(
                            size: Size.infinite,
                            painter: _PagePainter(
                              img,
                              _view,
                              bubbles.isEmpty
                                  ? null
                                  : bubbles[_bubble.clamp(
                                      0,
                                      bubbles.length - 1,
                                    )],
                              _pop,
                            ),
                          ),
                  ),
                  if (bubbles.length > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 18,
                      child: Text(
                        '${_bubble + 1} / ${bubbles.length}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  _Banner(
                    text: pageLine,
                    opacity: (_infoT / 1).clamp(0, 1),
                    top: false,
                  ),
                  _Banner(
                    text: _toast,
                    opacity: (_toastT / 0.5).clamp(0, 1),
                    top: true,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.opacity, required this.top});
  final String text;
  final double opacity;
  final bool top;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0 || text.isEmpty) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    return Positioned(
      left: 0,
      right: 0,
      top: top ? 12 : null,
      bottom: top ? null : 12,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Text(
                  text,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter(this.img, this.view, this.bubble, this.pop);
  final ui.Image img;
  final Rect view;
  final PRect? bubble;
  final double pop;

  @override
  void paint(Canvas canvas, Size size) {
    if (view.isEmpty) return;
    final s = math.min(size.width / view.width, size.height / view.height);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.save();
    canvas.translate(
      size.width / 2 - view.center.dx * s,
      size.height / 2 - view.center.dy * s,
    );
    canvas.scale(s);
    canvas.drawImage(img, Offset.zero, paint);
    canvas.restore();
    final b = bubble;
    if (b == null || pop < 0.01) return;
    // The balloon, popped out: the page dims, the balloon comes forward big.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.55 * pop),
    );
    final src = Rect.fromLTWH(
      b.x * img.width,
      b.y * img.height,
      b.w * img.width,
      b.h * img.height,
    );
    final fit = math.min(
      math.min(size.width * 0.86 / src.width, size.height * 0.7 / src.height),
      6.0,
    );
    final big = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: src.width * fit,
      height: src.height * fit,
    );
    // From where it sits on screen to the middle.
    final onScreen = Rect.fromLTWH(
      size.width / 2 + (src.left - view.center.dx) * s,
      size.height / 2 + (src.top - view.center.dy) * s,
      src.width * s,
      src.height * s,
    );
    final t = Curves.easeOutBack.transform(pop.clamp(0, 1));
    final dst = Rect.lerp(onScreen, big, t)!;
    canvas.drawRect(dst.inflate(6), Paint()..color = Colors.white);
    canvas.drawImageRect(img, src, dst, paint);
  }

  @override
  bool shouldRepaint(_PagePainter old) =>
      old.view != view ||
      old.img != img ||
      old.bubble != bubble ||
      old.pop != pop;
}
