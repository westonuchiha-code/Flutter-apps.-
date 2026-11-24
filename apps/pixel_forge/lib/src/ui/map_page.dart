import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/gestures.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:pixel_kit/pixel_kit.dart' as px;

import '../editor.dart';
import '../map_editor.dart';

Future<ui.Image> _decode(Uint32List p, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    p.buffer.asUint8List(p.offsetInBytes, p.lengthInBytes),
    w,
    h,
    ui.PixelFormat.bgra8888,
    c.complete,
  );
  return c.future;
}

Uint8List mapPng(px.TileMap m, {int scale = 1}) {
  final s = m.tileSet.size;
  return img.encodePng(
    px.toImage(m.render(), m.cols * s, m.rows * s, scale: scale),
  );
}

/// Tile map mode.
class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.map,
    required this.sprite,
    this.asset,
  });

  final MapEditor map;

  /// The sprite the tiles are cut from (for "re-cut tiles").
  final Editor sprite;
  final AssetInfo? asset;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  MapEditor get m => widget.map;
  late AssetInfo? _asset = widget.asset;
  List<ui.Image> _tiles = [];
  int _tilesFor = -1;

  @override
  void initState() {
    super.initState();
    m.addListener(_refreshTiles);
    _refreshTiles();
  }

  @override
  void dispose() {
    m.removeListener(_refreshTiles);
    for (final t in _tiles) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshTiles() async {
    final set = m.map.tileSet;
    if (identical(set.tiles, _tilesForSet) && _tilesFor == set.length) return;
    _tilesForSet = set.tiles;
    _tilesFor = set.length;
    final images = [
      for (final t in set.tiles) await _decode(t, set.size, set.size),
    ];
    if (!mounted) return;
    setState(() {
      for (final t in _tiles) {
        t.dispose();
      }
      _tiles = images;
    });
  }

  Object? _tilesForSet;

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _menu(String a) async {
    final shell = Shell.of(context);
    final locker = shell.locker;
    switch (a) {
      case 'save':
        if (!locker.ready && !await locker.connect()) return;
        final bytes = utf8.encode(jsonEncode(m.map.toJson()));
        final s = m.map.tileSet.size;
        final longest = math.max(m.map.cols, m.map.rows) * s;
        final thumb = mapPng(m.map, scale: (160 / longest).floor().clamp(1, 8));
        final extra = {
          'kind': px.TileMap.kind,
          'cols': m.map.cols,
          'rows': m.map.rows,
          'tileSize': s,
          'tiles': m.map.tileSet.length,
        };
        if (_asset != null) {
          final next = await locker.replace(
            _asset!,
            bytes,
            thumbnail: thumb,
            extra: extra,
          );
          await locker.update(next.copyWith(name: m.name));
        } else {
          _asset = await locker.save(
            type: AssetType.map,
            name: m.name,
            bytes: bytes,
            extension: 'json',
            thumbnail: thumb,
            tags: const ['pixel forge', 'tile map'],
            extra: extra,
          );
        }
        m.markSaved();
        _snack('Saved "${m.name}" to Maps');
      case 'png':
        await shell.exporter.exportFile(
          '${m.name}.png',
          mapPng(m.map, scale: 2),
          mimeType: 'image/png',
        );
      case 'retile':
        final s = widget.sprite.sprite;
        m.retile(s.flatten(widget.sprite.frame), s.width, s.height);
        _snack(
          '${m.map.tileSet.length - 1} tiles from "${widget.sprite.name}"',
        );
      case 'size':
        var cols = m.map.cols.toDouble(), rows = m.map.rows.toDouble();
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, set) => AlertDialog(
              title: Text('Map size ${cols.round()} × ${rows.round()} tiles'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: cols,
                    min: 4,
                    max: 128,
                    onChanged: (v) => set(() => cols = v.roundToDouble()),
                  ),
                  Slider(
                    value: rows,
                    min: 4,
                    max: 128,
                    onChanged: (v) => set(() => rows = v.roundToDouble()),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
        if (ok == true) m.resize(cols.round(), rows.round());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text('${m.name}${m.dirty ? ' •' : ''}'),
          actions: [
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: m.canUndo ? m.undo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo),
              onPressed: m.canRedo ? m.redo : null,
            ),
            PopupMenuButton<String>(
              tooltip: 'Map',
              onSelected: _menu,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'save',
                  child: Text('Save to Asset Locker (Maps)'),
                ),
                PopupMenuItem(value: 'png', child: Text('Export as PNG…')),
                PopupMenuItem(
                  value: 'retile',
                  child: Text('Re-cut tiles from the sprite'),
                ),
                PopupMenuItem(value: 'size', child: Text('Map size…')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _MapView(m: m)),
              const Divider(height: 1),
              Row(
                children: [
                  for (final (t, icon, label) in [
                    (MapTool.paint, Icons.brush, 'Paint'),
                    (MapTool.erase, Icons.auto_fix_normal, 'Erase'),
                    (MapTool.fill, Icons.format_color_fill, 'Fill'),
                    (MapTool.pick, Icons.colorize, 'Pick a tile from the map'),
                  ])
                    IconButton(
                      tooltip: label,
                      isSelected: m.tool == t,
                      style: IconButton.styleFrom(
                        backgroundColor: m.tool == t
                            ? scheme.primaryContainer
                            : null,
                      ),
                      icon: Icon(icon),
                      onPressed: () => m.setTool(t),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${m.map.tileSet.length - 1} tiles · ${m.map.cols}×${m.map.rows}',
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
              SizedBox(
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _tiles.length,
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => m.selectTile(i),
                    child: Container(
                      width: 52,
                      height: 52,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        border: Border.all(
                          color: i == m.tile
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: i == m.tile ? 3 : 1,
                        ),
                      ),
                      child: i == 0
                          ? const Tooltip(
                              message: 'Empty',
                              child: Icon(Icons.block),
                            )
                          : RawImage(
                              image: _tiles[i],
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.none,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The map canvas: one finger paints, two fingers pan and zoom.
class _MapView extends StatefulWidget {
  const _MapView({required this.m});
  final MapEditor m;

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  double _scale = 0;
  Offset _offset = Offset.zero;
  ui.Image? _image;
  int _version = -1;
  final _pointers = <int, Offset>{};
  bool _drawing = false;
  double _startDist = 0, _startScale = 1;
  Offset _startFocal = Offset.zero, _startOffset = Offset.zero;

  MapEditor get m => widget.m;
  int get _pxW => m.map.cols * m.map.tileSet.size;
  int get _pxH => m.map.rows * m.map.tileSet.size;

  @override
  void initState() {
    super.initState();
    m.addListener(_render);
    _render();
  }

  @override
  void dispose() {
    m.removeListener(_render);
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    if (_version == m.version && _image != null) return;
    final v = m.version;
    final image = await _decode(m.map.render(), _pxW, _pxH);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _version = v;
    });
  }

  (int, int) _cell(Offset p) {
    final q = (p - _offset) / _scale;
    final s = m.map.tileSet.size;
    return ((q.dx / s).floor(), (q.dy / s).floor());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        if (_scale == 0) {
          _scale = math.min(box.maxWidth / _pxW, box.maxHeight / _pxH) * 0.95;
          _offset = Offset(
            (box.maxWidth - _pxW * _scale) / 2,
            (box.maxHeight - _pxH * _scale) / 2,
          );
        }
        return Listener(
          onPointerDown: (e) {
            _pointers[e.pointer] = e.localPosition;
            if (_pointers.length == 1) {
              final (c, r) = _cell(e.localPosition);
              _drawing = true;
              m.strokeStart(c, r);
            } else if (_pointers.length == 2) {
              if (_drawing) m.strokeCancel();
              _drawing = false;
              final pts = _pointers.values.toList();
              _startDist = (pts[0] - pts[1]).distance;
              _startFocal = (pts[0] + pts[1]) / 2;
              _startScale = _scale;
              _startOffset = _offset;
            }
          },
          onPointerMove: (e) {
            _pointers[e.pointer] = e.localPosition;
            if (_pointers.length >= 2) {
              final pts = _pointers.values.toList();
              final s =
                  (_startScale *
                          (pts[0] - pts[1]).distance /
                          math.max(1, _startDist))
                      .clamp(0.2, 40.0);
              final focal = (pts[0] + pts[1]) / 2;
              final world = (_startFocal - _startOffset) / _startScale;
              setState(() {
                _scale = s;
                _offset = focal - world * s;
              });
            } else if (_drawing) {
              final (c, r) = _cell(e.localPosition);
              m.strokeMove(c, r);
            }
          },
          onPointerUp: (e) {
            _pointers.remove(e.pointer);
            if (_drawing && _pointers.isEmpty) {
              _drawing = false;
              m.strokeEnd();
            }
          },
          onPointerCancel: (e) => _pointers.remove(e.pointer),
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              final f = e.scrollDelta.dy > 0 ? 0.8 : 1.25;
              final world = (e.localPosition - _offset) / _scale;
              setState(() {
                _scale = (_scale * f).clamp(0.2, 40.0);
                _offset = e.localPosition - world * _scale;
              });
            }
          },
          child: ClipRect(
            child: CustomPaint(
              size: Size.infinite,
              painter: _MapPainter(
                image: _image,
                scale: _scale,
                offset: _offset,
                cols: m.map.cols,
                rows: m.map.rows,
                tile: m.map.tileSet.size,
                grid: scheme.outline.withValues(alpha: 0.35),
                background: scheme.surfaceContainerLowest,
                version: _version,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.image,
    required this.scale,
    required this.offset,
    required this.cols,
    required this.rows,
    required this.tile,
    required this.grid,
    required this.background,
    required this.version,
  });

  final ui.Image? image;
  final double scale;
  final Offset offset;
  final int cols, rows, tile;
  final Color grid, background;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final area = offset & Size(cols * tile * scale, rows * tile * scale);
    canvas.drawRect(area, Paint()..color = const Color(0xFFCCCCCC));
    final i = image;
    if (i != null) {
      canvas.drawImageRect(
        i,
        Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble()),
        area,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    final step = tile * scale;
    if (step >= 6) {
      final p = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (var c = 0; c <= cols; c++) {
        canvas.drawLine(
          Offset(area.left + c * step, area.top),
          Offset(area.left + c * step, area.bottom),
          p,
        );
      }
      for (var r = 0; r <= rows; r++) {
        canvas.drawLine(
          Offset(area.left, area.top + r * step),
          Offset(area.right, area.top + r * step),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.image != image ||
      old.scale != scale ||
      old.offset != offset ||
      old.version != version;
}
