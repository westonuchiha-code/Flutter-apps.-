import 'dart:convert';
import 'dart:typed_data';

/// Square tiles cut from a picture. Tile 0 is always the empty tile.
class TileSet {
  TileSet(this.size, this.tiles);

  final int size;
  final List<Uint32List> tiles;

  int get length => tiles.length;

  /// Cuts [pixels] (w×h) into tiles; identical tiles are kept once unless
  /// [keepDuplicates]. Fully transparent tiles map to tile 0.
  factory TileSet.cut(
    Uint32List pixels,
    int w,
    int h,
    int size, {
    bool keepDuplicates = false,
  }) {
    final tiles = <Uint32List>[Uint32List(size * size)];
    final seen = <String, int>{_key(tiles.first): 0};
    for (var ty = 0; ty + size <= h; ty += size) {
      for (var tx = 0; tx + size <= w; tx += size) {
        final t = Uint32List(size * size);
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            t[y * size + x] = pixels[(ty + y) * w + tx + x];
          }
        }
        final k = _key(t);
        if (!keepDuplicates && seen.containsKey(k)) {
          continue;
        }
        seen[k] = tiles.length;
        tiles.add(t);
      }
    }
    return TileSet(size, tiles);
  }

  static String _key(Uint32List t) =>
      base64Encode(t.buffer.asUint8List(t.offsetInBytes, t.lengthInBytes));

  Map<String, Object?> toJson() => {
    'size': size,
    'tiles': [for (final t in tiles) _key(t)],
  };

  factory TileSet.fromJson(Object? j) {
    if (j is! Map) {
      throw const FormatException('Not a tile set');
    }
    final size = (j['size'] as num).toInt();
    if (size < 1 || size > 128) {
      throw const FormatException('Bad tile size');
    }
    final tiles = <Uint32List>[];
    for (final t in (j['tiles'] as List?) ?? const []) {
      final bytes = t is String ? base64Decode(t) : Uint8List(0);
      final tile = Uint32List(size * size);
      if (bytes.length == size * size * 4) {
        tile.setAll(0, Uint8List.fromList(bytes).buffer.asUint32List());
      }
      tiles.add(tile);
    }
    if (tiles.isEmpty) {
      tiles.add(Uint32List(size * size));
    }
    return TileSet(size, tiles);
  }
}

/// A grid of tile numbers (0 = empty) over a [TileSet].
class TileMap {
  TileMap(this.cols, this.rows, this.tileSet, [Uint16List? cells])
    : cells = cells ?? Uint16List(cols * rows);

  static const kind = 'tile_map';

  final int cols, rows;
  TileSet tileSet;
  final Uint16List cells;

  int get(int c, int r) =>
      c >= 0 && r >= 0 && c < cols && r < rows ? cells[r * cols + c] : 0;

  void set(int c, int r, int tile) {
    if (c >= 0 && r >= 0 && c < cols && r < rows) {
      cells[r * cols + c] = tile.clamp(0, tileSet.length - 1);
    }
  }

  /// Fills the connected area of the same tile.
  void fill(int c, int r, int tile) {
    final target = get(c, r);
    if (target == tile || c < 0 || r < 0 || c >= cols || r >= rows) {
      return;
    }
    final stack = [r * cols + c];
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      if (cells[p] != target) {
        continue;
      }
      cells[p] = tile;
      final pc = p % cols, pr = p ~/ cols;
      if (pc > 0) {
        stack.add(p - 1);
      }
      if (pc < cols - 1) {
        stack.add(p + 1);
      }
      if (pr > 0) {
        stack.add(p - cols);
      }
      if (pr < rows - 1) {
        stack.add(p + cols);
      }
    }
  }

  /// The whole map as pixels.
  Uint32List render() {
    final s = tileSet.size, w = cols * s;
    final out = Uint32List(w * rows * s);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final t = cells[r * cols + c];
        if (t == 0 || t >= tileSet.length) {
          continue;
        }
        final tile = tileSet.tiles[t];
        for (var y = 0; y < s; y++) {
          out.setRange(
            (r * s + y) * w + c * s,
            (r * s + y) * w + c * s + s,
            tile,
            y * s,
          );
        }
      }
    }
    return out;
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'cols': cols,
    'rows': rows,
    'cells': base64Encode(
      cells.buffer.asUint8List(cells.offsetInBytes, cells.lengthInBytes),
    ),
    'tileSet': tileSet.toJson(),
  };

  factory TileMap.fromJson(Object? j) {
    if (j is! Map || j['kind'] != kind) {
      throw const FormatException('Not a tile map');
    }
    final cols = (j['cols'] as num).toInt(), rows = (j['rows'] as num).toInt();
    if (cols < 1 || rows < 1 || cols > 512 || rows > 512) {
      throw const FormatException('Bad map size');
    }
    final set = TileSet.fromJson(j['tileSet']);
    final raw = j['cells'] is String
        ? base64Decode(j['cells'] as String)
        : Uint8List(0);
    final cells = Uint16List(cols * rows);
    if (raw.length == cols * rows * 2) {
      cells.setAll(0, Uint8List.fromList(raw).buffer.asUint16List());
    }
    return TileMap(cols, rows, set, cells);
  }
}
