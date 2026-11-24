import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pixel_kit/pixel_kit.dart';

enum MapTool { paint, erase, fill, pick }

/// Paints a [TileMap] with tiles cut from a sprite.
class MapEditor extends ChangeNotifier {
  MapEditor(this.map, {this.name = 'Map'});

  /// A new map whose tiles come from [pixels] (w×h).
  factory MapEditor.fromPicture(
    Uint32List pixels,
    int w,
    int h,
    int tileSize, {
    int cols = 20,
    int rows = 15,
  }) => MapEditor(TileMap(cols, rows, TileSet.cut(pixels, w, h, tileSize)));

  TileMap map;
  String name;
  MapTool tool = MapTool.paint;
  int tile = 1;
  int version = 0;
  bool dirty = false;
  final _undo = <Uint16List>[];
  final _redo = <Uint16List>[];
  Uint16List? _before;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _changed() {
    version++;
    dirty = true;
    notifyListeners();
  }

  void setTool(MapTool t) {
    tool = t;
    notifyListeners();
  }

  void selectTile(int t) {
    tile = t.clamp(0, map.tileSet.length - 1);
    if (tool == MapTool.erase || tool == MapTool.pick) tool = MapTool.paint;
    notifyListeners();
  }

  void strokeStart(int c, int r) {
    if (tool == MapTool.pick) {
      selectTile(map.get(c, r));
      return;
    }
    _before = Uint16List.fromList(map.cells);
    strokeMove(c, r);
  }

  void strokeMove(int c, int r) {
    if (_before == null) return;
    switch (tool) {
      case MapTool.paint:
        map.set(c, r, tile);
      case MapTool.erase:
        map.set(c, r, 0);
      case MapTool.fill:
        map.fill(c, r, tile);
      case MapTool.pick:
        return;
    }
    _changed();
  }

  void strokeEnd() {
    final b = _before;
    _before = null;
    if (b != null && !listEquals(b, map.cells)) {
      _undo.add(b);
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
    }
  }

  void strokeCancel() {
    final b = _before;
    if (b != null) {
      map.cells.setAll(0, b);
      _changed();
    }
    _before = null;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(Uint16List.fromList(map.cells));
    map.cells.setAll(0, _undo.removeLast());
    _changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(Uint16List.fromList(map.cells));
    map.cells.setAll(0, _redo.removeLast());
    _changed();
  }

  /// New tiles from an edited sprite; cells pointing past the end are
  /// cleared.
  void retile(Uint32List pixels, int w, int h) {
    final set = TileSet.cut(pixels, w, h, map.tileSet.size);
    for (var i = 0; i < map.cells.length; i++) {
      if (map.cells[i] >= set.length) map.cells[i] = 0;
    }
    map.tileSet = set;
    tile = tile.clamp(0, set.length - 1);
    _changed();
  }

  /// A map of a new size (keeps the top-left part).
  void resize(int cols, int rows) {
    final next = TileMap(cols, rows, map.tileSet);
    for (var r = 0; r < rows && r < map.rows; r++) {
      for (var c = 0; c < cols && c < map.cols; c++) {
        next.cells[r * cols + c] = map.get(c, r);
      }
    }
    map = next;
    _undo.clear();
    _redo.clear();
    _changed();
  }

  void markSaved() {
    dirty = false;
    notifyListeners();
  }
}
