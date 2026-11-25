import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'synth.dart';
import 'tables.dart';

/// Scalefactor band edges (long blocks, 44.1 kHz).
const sfbLong44 = <int>[
  0, 4, 8, 12, 16, 20, 24, 30, 36, 44, 52, 62, 74, 90, 110, 134, 162, 196, //
  238, 288, 342, 418, 576,
];

/// Bitrates (kbps) by header index, MPEG-1 Layer III.
const bitrates = [
  0,
  32,
  40,
  48,
  56,
  64,
  80,
  96,
  112,
  128,
  160,
  192,
  224,
  256,
  320,
];

/// Largest value each big-value table codes (x and y), and linbits.
const tableMax = <int, int>{
  1: 1, 2: 2, 3: 2, 5: 3, 6: 3, 7: 5, 8: 5, 9: 5, 10: 7, 11: 7, 12: 7, //
  13: 15, 15: 15,
};
const linbitsOf = <int>[
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  1, 2, 3, 4, 6, 8, 10, 13, 4, 5, 6, 7, 8, 9, 11, 13,
];

List<int> _codesFor(int table) =>
    huffCodes[table < 16 ? table : (table < 24 ? 16 : 24)]!;

/// The decoder's filters, probed once: subband synthesis responses and the
/// 36-point IMDCT as two 18×18 matrices (this granule, the last one's
/// overlap). The encoder applies their transposes, so what it writes is
/// exactly what the decoder undoes.
class _Bank {
  _Bank._(this.filters, this.a, this.e, this.mdctGain);

  /// filters[k][n], n = 0..511.
  final List<Float64List> filters;

  /// Column-major 18×18: out = a·X(this) + e·X(last).
  final Float64List a, e;
  final double mdctGain;

  static final instance = _build();

  static _Bank _build() {
    final filters = <Float64List>[];
    for (var k = 0; k < 32; k++) {
      final gr = Float64List(576);
      gr[18 * k] = 1;
      filters.add(Float64List.sublistView(SynthBank().run(gr), 0, 512));
    }
    final a = Float64List(18 * 18), e = Float64List(18 * 18);
    for (var n = 0; n < 18; n++) {
      final g = Float64List(18)..[n] = 1;
      final ov = Float64List(9);
      imdct36(g, 0, ov, 0);
      for (var i = 0; i < 18; i++) {
        a[n * 18 + i] = g[i];
      }
      final z = Float64List(18);
      imdct36(z, 0, ov, 0);
      for (var i = 0; i < 18; i++) {
        e[n * 18 + i] = z[i];
      }
    }
    // A^T A + E^T E = gain · I (time-domain alias cancellation).
    var gain = 0.0;
    for (var i = 0; i < 18; i++) {
      gain += a[i] * a[i] + e[i] * e[i];
    }
    return _Bank._(filters, a, e, gain);
  }
}

/// One channel's lines, granule by granule.
class _Channel {
  _Channel(this.pcm, this.channels, this.offset);
  final Int16List pcm;
  final int channels, offset;
  final _bank = _Bank.instance;
  late final int _length = pcm.length ~/ channels;
  Float64List? _next;
  int _granule = 0;

  double _x(int t) =>
      t < 0 || t >= _length ? 0 : pcm[t * channels + offset].toDouble();

  /// Subband samples of granule [j] (decoder's layout, signs changed).
  Float64List _subbands(int j) {
    final s = Float64List(576);
    final x = Float64List(1088);
    final base = 576 * j;
    for (var i = 0; i < x.length; i++) {
      x[i] = _x(base + i);
    }
    const scale = 1 / 137438953472; // 2^-37: the synthesis' gain
    for (var slot = 0; slot < 18; slot++) {
      final o = 32 * slot;
      for (var k = 0; k < 32; k++) {
        final f = _bank.filters[k];
        var acc = 0.0;
        for (var n = 1; n < 512; n++) {
          acc += x[o + n] * f[n];
        }
        s[18 * k + slot] = acc * scale;
      }
    }
    changeSign(s);
    return s;
  }

  /// The next granule's 576 lines (as the decoder will read them).
  Float64List next() {
    final cur = _next ?? _subbands(_granule);
    final nxt = _subbands(_granule + 1);
    _next = nxt;
    _granule++;
    final xr = Float64List(576);
    final a = _bank.a, e = _bank.e, k = 1 / _bank.mdctGain;
    for (var b = 0; b < 32; b++) {
      final o = 18 * b;
      for (var n = 0; n < 18; n++) {
        var acc = 0.0;
        for (var i = 0; i < 18; i++) {
          acc += a[n * 18 + i] * cur[o + i] + e[n * 18 + i] * nxt[o + i];
        }
        xr[o + n] = acc * k;
      }
    }
    // Undo the decoder's alias reduction (its transpose).
    for (var b = 0; b < 31; b++) {
      final o = b * 18;
      for (var i = 0; i < 8; i++) {
        final u = xr[o + 18 + i], d = xr[o + 17 - i];
        xr[o + 18 + i] = u * aaCs[i] + d * aaCa[i];
        xr[o + 17 - i] = -u * aaCa[i] + d * aaCs[i];
      }
    }
    return xr;
  }
}

class BitWriter {
  final _bytes = BytesBuilder(copy: false);
  int _acc = 0, _n = 0, written = 0;

  void put(int value, int bits) {
    for (var i = bits - 1; i >= 0; i--) {
      _acc = (_acc << 1) | ((value >> i) & 1);
      if (++_n == 8) {
        _bytes.addByte(_acc);
        _acc = 0;
        _n = 0;
      }
    }
    written += bits;
  }

  Uint8List take() {
    while (_n != 0) {
      put(0, 1);
    }
    return _bytes.takeBytes();
  }
}

/// A granule-channel ready to write.
class _Coded {
  int bigValues = 0, globalGain = 210, count1Table = 0, bits = 0;
  int region0 = 0, region1 = 0;
  final tables = [0, 0, 0];
  final ix = Int32List(576);
  int count1End = 0;

  /// Scalefactors (sfb 0..20; 3 dB finer steps each) and how they're sent.
  final sf = Int32List(22);
  int compress = 0;
  int get part2Bits => 11 * _slen[compress].$1 + 10 * _slen[compress].$2;
}

/// scalefac_compress → (bits for sfb 0-10, bits for sfb 11-20).
const _slen = [
  (0, 0), (0, 1), (0, 2), (0, 3), (3, 0), (1, 1), (1, 2), (1, 3), //
  (2, 1), (2, 2), (2, 3), (3, 1), (3, 2), (3, 3), (4, 2), (4, 3),
];

/// Sets [c.sf] so quantization noise follows the music's spectrum (noise
/// hides under loud sound): quiet bands get finer steps, never below what
/// can't be heard.
/// How much of the spectrum noise follows (0: flat, 1: all of it).
double shapeAmount = 0.3;

void _shape(Float64List xr, _Coded c) {
  final e = Float64List(21);
  for (var b = 0; b < 21; b++) {
    var sum = 0.0;
    for (var i = sfbLong44[b]; i < sfbLong44[b + 1]; i++) {
      sum += xr[i] * xr[i];
    }
    e[b] = sum / (sfbLong44[b + 1] - sfbLong44[b]);
  }
  // Masking spreads to neighbouring bands.
  final m = Float64List(21);
  var top = 1e-30;
  for (var b = 0; b < 21; b++) {
    var v = e[b];
    if (b > 0) v = math.max(v, e[b - 1] * 0.12);
    if (b < 20) v = math.max(v, e[b + 1] * 0.03);
    m[b] = v;
    top = math.max(top, v);
  }
  // Bands 60 dB under the loudest one aren't worth extra bits.
  for (var b = 0; b < 21; b++) {
    m[b] = math.max(m[b], top * 1e-6);
  }
  for (var b = 0; b < 21; b++) {
    // 3 dB per step; noise follows part of the spectrum's slope.
    final u = (shapeAmount * math.log(top / m[b]) / math.ln2).round();
    c.sf[b] = u.clamp(0, b < 11 ? 15 : 7);
  }
  // Cheapest way to send them.
  var m1 = 0, m2 = 0;
  for (var b = 0; b < 21; b++) {
    if (b < 11) {
      m1 = math.max(m1, c.sf[b]);
    } else {
      m2 = math.max(m2, c.sf[b]);
    }
  }
  var best = 15;
  for (var k = 0; k < 16; k++) {
    final (s1, s2) = _slen[k];
    if (m1 < (1 << s1) &&
        m2 < (1 << s2) &&
        11 * s1 + 10 * s2 < 11 * _slen[best].$1 + 10 * _slen[best].$2) {
      best = k;
    }
  }
  c.compress = best;
}

int _pairBits(int table, int x, int y) {
  final lin = linbitsOf[table];
  final codes = _codesFor(table);
  final cx = math.min(x, 15), cy = math.min(y, 15);
  var b = codes[cx * 16 + cy] & 31;
  if (x != 0) b++;
  if (y != 0) b++;
  if (lin > 0) {
    if (x >= 15) b += lin;
    if (y >= 15) b += lin;
  }
  return b;
}

/// Cheapest table for pairs [from, to) (indices into ix, step 2) and its bits.
(int, int) _bestTable(Int32List ix, int from, int to) {
  if (from >= to) return (0, 0);
  var mx = 0;
  for (var i = from; i < to; i++) {
    if (ix[i] > mx) mx = ix[i];
  }
  if (mx == 0) return (0, 0);
  final candidates = <int>[];
  if (mx <= 15) {
    tableMax.forEach((t, m) {
      if (mx <= m) candidates.add(t);
    });
  } else {
    for (final base in [16, 24]) {
      for (var t = base; t < base + 8; t++) {
        if (mx - 15 < (1 << linbitsOf[t])) {
          candidates.add(t);
          break;
        }
      }
    }
  }
  var best = -1, bestBits = 1 << 30;
  for (final t in candidates) {
    var b = 0;
    for (var i = from; i < to; i += 2) {
      b += _pairBits(t, ix[i], ix[i + 1]);
    }
    if (b < bestBits) {
      bestBits = b;
      best = t;
    }
  }
  return (best, bestBits);
}

/// Region split, table choice and bit count for [c.ix] (absolute values).
void _choose(_Coded c, {bool search = false}) {
  final ix = c.ix;
  var i = 576;
  while (i > 1 && ix[i - 1] == 0 && ix[i - 2] == 0) {
    i -= 2;
  }
  final zero = i;
  while (i > 3 &&
      ix[i - 1] <= 1 &&
      ix[i - 2] <= 1 &&
      ix[i - 3] <= 1 &&
      ix[i - 4] <= 1) {
    i -= 4;
  }
  // count1 quads [i, zero): zero - i is a whole number of quads.
  final c1End = zero;
  final bvEnd = i;
  c.bigValues = bvEnd ~/ 2;
  c.count1End = c1End;
  var c1a = 0, c1b = 0;
  for (var q = bvEnd; q < c1End; q += 4) {
    final idx = ix[q] * 8 + ix[q + 1] * 4 + ix[q + 2] * 2 + ix[q + 3];
    final ones = ix[q] + ix[q + 1] + ix[q + 2] + ix[q + 3];
    c1a += (count1A[idx] & 31) + ones;
    c1b += (count1B[idx] & 31) + ones;
  }
  c.count1Table = c1b < c1a ? 1 : 0;
  final c1bits = math.min(c1a, c1b);

  int edge(int sfb) => math.min(sfbLong44[math.min(sfb, 22)], bvEnd);
  var bestBits = 1 << 30;
  void tryRegions(int r0, int r1) {
    final e0 = edge(r0 + 1), e1 = edge(r0 + r1 + 2);
    final (t0, b0) = _bestTable(ix, 0, e0);
    final (t1, b1) = _bestTable(ix, e0, e1);
    final (t2, b2) = _bestTable(ix, e1, bvEnd);
    final total = b0 + b1 + b2;
    if (total < bestBits) {
      bestBits = total;
      c
        ..region0 = r0
        ..region1 = r1;
      c.tables
        ..[0] = t0
        ..[1] = t1
        ..[2] = t2;
    }
  }

  if (search) {
    for (var r0 = 0; r0 < 16; r0++) {
      if (sfbLong44[r0 + 1] >= bvEnd && r0 > 0) break;
      for (var r1 = 0; r1 < 8; r1++) {
        if (r0 + r1 + 2 > 22) break;
        tryRegions(r0, r1);
        if (sfbLong44[r0 + r1 + 2] >= bvEnd) break;
      }
    }
  } else {
    // Thirds of the big values, on band edges.
    var r0 = 0;
    while (r0 < 15 && sfbLong44[r0 + 1] < bvEnd / 3) {
      r0++;
    }
    var r1 = 0;
    while (r1 < 7 &&
        r0 + r1 + 2 < 22 &&
        sfbLong44[r0 + r1 + 2] < bvEnd * 2 / 3) {
      r1++;
    }
    tryRegions(r0, r1);
  }
  c.bits = bestBits + c1bits + c.part2Bits;
}

/// Quantizes [xr] with [gain] (and the scalefactors) into [c.ix]; false
/// if a value is too big to code.
bool _quantize(Float64List xr, int gain, _Coded c) {
  for (var b = 0; b < 22; b++) {
    final step = math.pow(2, -(gain - 214) * 3 / 16 + c.sf[b] * 3 / 8);
    for (var i = sfbLong44[b]; i < sfbLong44[b + 1]; i++) {
      final v = math.pow(xr[i].abs(), 0.75) * step;
      if (v > 8206) return false;
      c.ix[i] = (v + 0.4054).floor();
    }
  }
  c.globalGain = gain;
  return true;
}

/// Codes a granule's channels with one global gain (equal noise in each),
/// the finest that fits [budget] bits in all (and 4095 in each).
List<_Coded> _code(List<Float64List> xrs, int budget) {
  final cs = [for (var k = 0; k < xrs.length; k++) _Coded()];
  for (var k = 0; k < xrs.length; k++) {
    _shape(xrs[k], cs[k]);
  }
  bool fits(int gain, {bool search = false}) {
    var total = 0;
    for (var k = 0; k < xrs.length; k++) {
      if (!_quantize(xrs[k], gain, cs[k])) return false;
      _choose(cs[k], search: search);
      if (cs[k].bits > 4095) return false;
      total += cs[k].bits;
    }
    return total <= budget;
  }

  var lo = 0, hi = 255;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (fits(mid)) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  var g = lo;
  while (!fits(g, search: true) && g < 255) {
    g++;
  }
  if (g == 255 && !fits(g, search: true)) {
    // Silence the scalefactors and try once more (never happens in music).
    for (final c in cs) {
      c
        ..sf.fillRange(0, 22, 0)
        ..compress = 0;
    }
    fits(255, search: true);
  }
  return cs;
}

void _writeMain(BitWriter w, _Coded c, Float64List xr) {
  final ix = c.ix;
  int sign(int i) => xr[i] < 0 ? 1 : 0;
  final (s1, s2) = _slen[c.compress];
  for (var b = 0; b < 21; b++) {
    w.put(c.sf[b], b < 11 ? s1 : s2);
  }
  final bvEnd = c.bigValues * 2;
  final e0 = math.min(sfbLong44[c.region0 + 1], bvEnd);
  final e1 = math.min(
    sfbLong44[math.min(c.region0 + c.region1 + 2, 22)],
    bvEnd,
  );
  for (var i = 0; i < bvEnd; i += 2) {
    final t = c.tables[i < e0 ? 0 : (i < e1 ? 1 : 2)];
    if (t == 0) continue;
    final codes = _codesFor(t);
    final lin = linbitsOf[t];
    final x = ix[i], y = ix[i + 1];
    final code = codes[math.min(x, 15) * 16 + math.min(y, 15)];
    w.put(code >> 5, code & 31);
    if (lin > 0 && x >= 15) w.put(x - 15, lin);
    if (x != 0) w.put(sign(i), 1);
    if (lin > 0 && y >= 15) w.put(y - 15, lin);
    if (y != 0) w.put(sign(i + 1), 1);
  }
  final table = c.count1Table == 1 ? count1B : count1A;
  for (var q = bvEnd; q < c.count1End; q += 4) {
    final code = table[ix[q] * 8 + ix[q + 1] * 4 + ix[q + 2] * 2 + ix[q + 3]];
    w.put(code >> 5, code & 31);
    for (var k = 0; k < 4; k++) {
      if (ix[q + k] != 0) w.put(sign(q + k), 1);
    }
  }
}

/// Text tags written as an ID3v2.3 header.
class Mp3Tags {
  const Mp3Tags({this.title, this.artist, this.album, this.track, this.year});
  final String? title, artist, album, track, year;

  Uint8List toBytes() {
    final frames = BytesBuilder();
    void frame(String id, String? text) {
      if (text == null || text.isEmpty) return;
      final body = [0, ...latin1.encode(_latin(text))];
      frames
        ..add(ascii.encode(id))
        ..add([
          (body.length >> 24) & 255,
          (body.length >> 16) & 255,
          (body.length >> 8) & 255,
          body.length & 255,
          0,
          0,
        ])
        ..add(body);
    }

    frame('TIT2', title);
    frame('TPE1', artist);
    frame('TALB', album);
    frame('TRCK', track);
    frame('TYER', year);
    final f = frames.takeBytes();
    final n = f.length;
    return Uint8List.fromList([
      ...ascii.encode('ID3'),
      3,
      0,
      0,
      (n >> 21) & 127,
      (n >> 14) & 127,
      (n >> 7) & 127,
      n & 127,
      ...f,
    ]);
  }

  static String _latin(String s) =>
      String.fromCharCodes(s.runes.map((r) => r < 256 ? r : 0x3F));
}

/// Encodes 16-bit PCM at 44.1 kHz (interleaved when stereo) to a CBR MP3
/// (MPEG-1 Layer III, long blocks, no bit reservoir).
Uint8List encodeMp3(
  Int16List pcm, {
  int channels = 2,
  int kbps = 320,
  Mp3Tags? tags,
  void Function(double done)? progress,
}) {
  final brIndex = bitrates.indexOf(kbps);
  if (brIndex <= 0) throw ArgumentError('bitrate $kbps not supported');
  if (channels != 1 && channels != 2) throw ArgumentError('1 or 2 channels');
  final frames = (pcm.length ~/ channels / 1152).ceil();
  final chans = [for (var c = 0; c < channels; c++) _Channel(pcm, channels, c)];
  final w = BitWriter();
  if (tags != null) {
    for (final b in tags.toBytes()) {
      w.put(b, 8);
    }
  }
  final sideBytes = channels == 2 ? 32 : 17;
  var rest = 0;
  for (var f = 0; f < frames; f++) {
    // 144 · bitrate / 44100 bytes, the remainder paid with padding bytes.
    final num = 144 * kbps * 1000;
    var size = num ~/ 44100;
    rest += num % 44100;
    var padding = 0;
    if (rest >= 44100) {
      rest -= 44100;
      padding = 1;
      size++;
    }
    final mainBits = (size - 4 - sideBytes) * 8;
    final budget = mainBits ~/ 2;
    final coded = <List<(_Coded, Float64List)>>[];
    var ms = false;
    final lines = [
      for (var gr = 0; gr < 2; gr++)
        [
          for (final ch in chans)
            () {
              final xr = ch.next();
              // Nothing above ~19.5 kHz.
              for (var i = 510; i < 576; i++) {
                xr[i] = 0;
              }
              return xr;
            }(),
        ],
    ];
    if (channels == 2) {
      // Mid/side when the sides are small (most music).
      var mid = 0.0, side = 0.0;
      for (final gr in lines) {
        for (var i = 0; i < 576; i++) {
          mid += math.pow(gr[0][i] + gr[1][i], 2);
          side += math.pow(gr[0][i] - gr[1][i], 2);
        }
      }
      ms = side < mid * 0.5;
      if (ms) {
        for (final gr in lines) {
          for (var i = 0; i < 576; i++) {
            final l = gr[0][i], r = gr[1][i];
            gr[0][i] = (l + r) * math.sqrt1_2;
            gr[1][i] = (l - r) * math.sqrt1_2;
          }
        }
      }
    }
    for (final gr in lines) {
      final cs = _code(gr, budget);
      coded.add([for (var k = 0; k < channels; k++) (cs[k], gr[k])]);
    }
    final start = w.written;
    // Header.
    w
      ..put(0x7FF, 11)
      ..put(3, 2) // MPEG-1
      ..put(1, 2) // Layer III
      ..put(1, 1) // no CRC
      ..put(brIndex, 4)
      ..put(0, 2) // 44.1 kHz
      ..put(padding, 1)
      ..put(0, 1)
      ..put(channels == 2 ? (ms ? 1 : 0) : 3, 2)
      ..put(ms ? 2 : 0, 2)
      ..put(0, 1)
      ..put(1, 1) // original
      ..put(0, 2);
    // Side info.
    w
      ..put(0, 9) // main_data_begin: no reservoir
      ..put(0, channels == 2 ? 3 : 5);
    for (var c = 0; c < channels; c++) {
      w.put(0, 4); // scfsi
    }
    for (var gr = 0; gr < 2; gr++) {
      for (var c = 0; c < channels; c++) {
        final k = coded[gr][c].$1;
        w
          ..put(k.bits, 12)
          ..put(k.bigValues, 9)
          ..put(k.globalGain, 8)
          ..put(k.compress, 4)
          ..put(0, 1) // long blocks
          ..put(k.tables[0], 5)
          ..put(k.tables[1], 5)
          ..put(k.tables[2], 5)
          ..put(k.region0, 4)
          ..put(k.region1, 3)
          ..put(0, 1)
          ..put(0, 1)
          ..put(k.count1Table, 1);
      }
    }
    for (var gr = 0; gr < 2; gr++) {
      for (var c = 0; c < channels; c++) {
        final (k, xr) = coded[gr][c];
        final before = w.written;
        _writeMain(w, k, xr);
        if (w.written - before != k.bits) {
          throw StateError('bit count ${w.written - before} != ${k.bits}');
        }
      }
    }
    while (w.written - start < size * 8) {
      w.put(0, 1);
    }
    progress?.call((f + 1) / frames);
  }
  return w.take();
}
