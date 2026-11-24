import 'dart:math' as math;
import 'dart:typed_data';

/// The blocks a patch can be (classic quilt blocks).
enum Block {
  plain('Plain'),
  hstDown('Half-square triangle'),
  hstUp('Half-square triangle'),
  fourPatch('Four-patch'),
  stripesH('Stripes'),
  stripesV('Stripes');

  const Block(this.label);
  final String label;
}

/// One patch: its block and the palette colours of its pieces.
class Patch {
  const Patch(this.block, this.colors);
  final Block block;
  final List<int> colors;
}

class QuiltSettings {
  const QuiltSettings({
    this.columns = 24,
    required this.palette,
    this.detail = 0.6,
    this.patchSize = 24,
    this.seam = 1,
    this.seamColor = 0xFFF2EEE4,
    this.stitches = true,
    this.texture = true,
  });

  final int columns;
  final List<int> palette;

  /// 0: mostly plain patches; 1: the busiest block that fits best.
  final double detail;

  /// Pixels per patch in the picture.
  final int patchSize;

  /// Seam width in pixels (0 = none).
  final int seam;
  final int seamColor;

  /// Dashed quilting stitches inside each patch.
  final bool stitches;

  /// Slight weave texture on the fabric.
  final bool texture;
}

class Quilt {
  const Quilt(this.columns, this.rows, this.patches);
  final int columns, rows;
  final List<Patch> patches;

  Patch at(int c, int r) => patches[r * columns + c];

  /// How many patches use each kind of block.
  Map<String, int> get counts {
    final out = <String, int>{};
    for (final p in patches) {
      out[p.block.label] = (out[p.block.label] ?? 0) + 1;
    }
    return out;
  }
}

int _r(int c) => (c >> 16) & 255;
int _g(int c) => (c >> 8) & 255;
int _b(int c) => c & 255;

/// Perceptual-ish colour distance (weighted RGB).
int _dist(int a, int b) {
  final dr = _r(a) - _r(b), dg = _g(a) - _g(b), db = _b(a) - _b(b);
  return 2 * dr * dr + 4 * dg * dg + 3 * db * db;
}

int nearest(int c, List<int> palette) {
  var best = palette.first, bd = 1 << 62;
  for (final p in palette) {
    final d = _dist(c, p);
    if (d < bd) {
      bd = d;
      best = p;
    }
  }
  return best;
}

const _n = 8; // each patch is judged on an 8×8 sample

/// Which piece of [block] the sample point (x, y) (0..7) belongs to.
int pieceOf(Block block, int x, int y) => switch (block) {
  Block.plain => 0,
  Block.hstDown => x >= y ? 0 : 1, // split from top-left to bottom-right
  Block.hstUp => x + y < _n - 1 ? 0 : 1,
  Block.fourPatch => (y >= _n ~/ 2 ? 2 : 0) + (x >= _n ~/ 2 ? 1 : 0),
  Block.stripesH => y * 4 ~/ _n,
  Block.stripesV => x * 4 ~/ _n,
};

int pieces(Block b) => switch (b) {
  Block.plain => 1,
  Block.hstDown || Block.hstUp => 2,
  Block.fourPatch || Block.stripesH || Block.stripesV => 4,
};

/// Picks a block and palette colours for every patch of the photo.
Quilt makeQuilt(int width, int height, Uint32List px, QuiltSettings s) {
  final cols = s.columns;
  final rows = math.max(1, (cols * height / width).round());
  final out = <Patch>[];
  final sample = Uint32List(_n * _n);
  // Busier blocks must earn their place: a cost per extra piece.
  final penalty = (1 - s.detail) * 3500 + 150;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      // Average the photo into an 8×8 sample of this patch.
      for (var sy = 0; sy < _n; sy++) {
        final y0 = ((r + sy / _n) * height / rows).floor();
        final y1 = math.max(
          y0 + 1,
          ((r + (sy + 1) / _n) * height / rows).floor(),
        );
        for (var sx = 0; sx < _n; sx++) {
          final x0 = ((c + sx / _n) * width / cols).floor();
          final x1 = math.max(
            x0 + 1,
            ((c + (sx + 1) / _n) * width / cols).floor(),
          );
          var rr = 0, gg = 0, bb = 0, k = 0;
          for (var y = y0; y < y1 && y < height; y++) {
            for (var x = x0; x < x1 && x < width; x++) {
              final v = px[y * width + x];
              rr += _r(v);
              gg += _g(v);
              bb += _b(v);
              k++;
            }
          }
          k = math.max(1, k);
          sample[sy * _n + sx] =
              0xFF000000 | ((rr ~/ k) << 16) | ((gg ~/ k) << 8) | (bb ~/ k);
        }
      }
      Patch? best;
      var bestCost = double.infinity;
      for (final block in Block.values) {
        final n = pieces(block);
        final sums = List.filled(n * 4, 0);
        for (var y = 0; y < _n; y++) {
          for (var x = 0; x < _n; x++) {
            final p = pieceOf(block, x, y), v = sample[y * _n + x];
            sums[p * 4] += _r(v);
            sums[p * 4 + 1] += _g(v);
            sums[p * 4 + 2] += _b(v);
            sums[p * 4 + 3]++;
          }
        }
        final colors = [
          for (var i = 0; i < n; i++)
            nearest(
              0xFF000000 |
                  ((sums[i * 4] ~/ sums[i * 4 + 3]) << 16) |
                  ((sums[i * 4 + 1] ~/ sums[i * 4 + 3]) << 8) |
                  (sums[i * 4 + 2] ~/ sums[i * 4 + 3]),
              s.palette,
            ),
        ];
        // A block whose pieces came out all one colour is really plain.
        if (n > 1 && colors.toSet().length == 1) {
          continue;
        }
        var err = 0.0;
        for (var y = 0; y < _n; y++) {
          for (var x = 0; x < _n; x++) {
            err += _dist(sample[y * _n + x], colors[pieceOf(block, x, y)]);
          }
        }
        final cost = err / (_n * _n) + penalty * (n - 1);
        if (cost < bestCost) {
          bestCost = cost;
          best = Patch(block, colors);
        }
      }
      out.add(best!);
    }
  }
  return Quilt(cols, rows, out);
}

int _shade(int c, double k) {
  int ch(int v) => (v * k).round().clamp(0, 255);
  return 0xFF000000 | (ch(_r(c)) << 16) | (ch(_g(c)) << 8) | ch(_b(c));
}

/// Draws the quilt: patches, seams, stitches and fabric weave.
({int width, int height, Uint32List pixels}) renderQuilt(
  Quilt q,
  QuiltSettings s,
) {
  final p = s.patchSize, seam = s.seam;
  final w = q.columns * p + seam, h = q.rows * p + seam;
  final out = Uint32List(w * h)..fillRange(0, w * h, s.seamColor | 0xFF000000);
  final inner = p - seam;
  for (var r = 0; r < q.rows; r++) {
    for (var c = 0; c < q.columns; c++) {
      final patch = q.at(c, r);
      final ox = c * p + seam, oy = r * p + seam;
      for (var y = 0; y < inner; y++) {
        for (var x = 0; x < inner; x++) {
          // Exact diagonals at full size for the triangles.
          final piece = switch (patch.block) {
            Block.hstDown => x >= y ? 0 : 1,
            Block.hstUp => x + y < inner - 1 ? 0 : 1,
            _ => pieceOf(patch.block, x * _n ~/ inner, y * _n ~/ inner),
          };
          var col = patch.colors[piece];
          if (s.texture && ((x + y) % 3 == 0 || (x - y) % 5 == 0)) {
            col = _shade(col, 0.93);
          }
          // Running stitch, 2 px in from the edge.
          final edge = math.min(
            math.min(x, y),
            math.min(inner - 1 - x, inner - 1 - y),
          );
          if (s.stitches && inner >= 12 && edge == 2 && ((x + y) ~/ 2).isEven) {
            col = _shade(col, 0.6);
          }
          out[(oy + y) * w + ox + x] = col;
        }
      }
    }
  }
  return (width: w, height: h, pixels: out);
}
