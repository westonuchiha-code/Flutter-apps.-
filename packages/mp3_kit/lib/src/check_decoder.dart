// A small decoder for what encodeMp3 writes (long blocks, no
// scalefactors, no reservoir), built on the decoder's own filter code: used
// by the tests and tool/check.dart to hear what a player will play.
import 'dart:math' as math;
import 'dart:typed_data';

import 'encoder.dart' show sfbLong44, linbitsOf, bitrates;
import 'synth.dart';
import 'tables.dart';

void _expect(bool ok, String what) {
  if (!ok) throw FormatException(what);
}

/// A small decoder for what [encodeMp3] writes (long blocks, no
/// scalefactors), using the decoder's own filter code.
class _Reader {
  _Reader(this.b, [this.pos = 0]);
  final Uint8List b;
  int pos;
  int get(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      final byte = pos >> 3 < b.length ? b[pos >> 3] : 0;
      v = (v << 1) | ((byte >> (7 - (pos & 7))) & 1);
      pos++;
    }
    return v;
  }
}

Map<int, int> _decodeMap(List<int> codes) => {
  for (var i = 0; i < codes.length; i++)
    if (codes[i] != 0) (codes[i] & 31) << 24 | (codes[i] >> 5): i,
};

int _readCode(_Reader r, Map<int, int> map) {
  var v = 0;
  for (var len = 1; len <= 19; len++) {
    v = (v << 1) | r.get(1);
    final hit = map[len << 24 | v];
    if (hit != null) return hit;
  }
  throw StateError('bad code');
}

/// Decodes our own MP3s to interleaved 16-bit PCM.
Int16List decodeOwnMp3(Uint8List mp3) {
  var p = 0;
  if (mp3[0] == 0x49 && mp3[1] == 0x44 && mp3[2] == 0x33) {
    p = 10 + (mp3[6] << 21 | mp3[7] << 14 | mp3[8] << 7 | mp3[9]);
  }
  final out = <int>[];
  List<LongDecoder>? decs;
  final maps = {for (final e in huffCodes.entries) e.key: _decodeMap(e.value)};
  final c1 = [_decodeMap(count1A), _decodeMap(count1B)];
  while (p + 4 <= mp3.length) {
    final r = _Reader(mp3, p * 8);
    _expect(r.get(11) == 0x7FF, 'sync');
    r.get(2);
    r.get(2);
    r.get(1);
    final br = bitrates[r.get(4)];
    r.get(2);
    final pad = r.get(1);
    r.get(1);
    final mode = r.get(2);
    final nch = mode == 3 ? 1 : 2;
    final ms = mode == 1 && (r.get(2) & 2) != 0;
    if (mode != 1) r.get(2);
    r.get(4);
    final size = 144 * br * 1000 ~/ 44100 + pad;
    decs ??= [for (var c = 0; c < nch; c++) LongDecoder()];
    _expect(r.get(9) == 0, 'reservoir');
    r.get(nch == 2 ? 3 : 5);
    r.get(4 * nch);
    final info = <List<int>>[];
    for (var i = 0; i < 2 * nch; i++) {
      final len = r.get(12), bv = r.get(9), gg = r.get(8);
      final comp = r.get(4);
      _expect(r.get(1) == 0, 'short blocks');
      final t = [r.get(5), r.get(5), r.get(5)];
      final r0 = r.get(4), r1 = r.get(3);
      r.get(2);
      info.add([len, bv, gg, ...t, r0, r1, r.get(1), comp]);
    }
    var bit = r.pos;
    final pcm = List.generate(
      2,
      (_) => List<Float64List>.filled(nch, Float64List(0)),
    );
    for (var gr = 0; gr < 2; gr++) {
      final lines = List.filled(nch, Float64List(0));
      for (var ch = 0; ch < nch; ch++) {
        final [len, bv, gg, t0, t1, t2, r0, r1, c1t, comp] =
            info[gr * nch + ch];
        final rd = _Reader(mp3, bit);
        const slen = [
          (0, 0), (0, 1), (0, 2), (0, 3), (3, 0), (1, 1), (1, 2), (1, 3), //
          (2, 1), (2, 2), (2, 3), (3, 1), (3, 2), (3, 3), (4, 2), (4, 3),
        ];
        final sf = List.filled(22, 0);
        for (var b = 0; b < 21; b++) {
          sf[b] = rd.get(b < 11 ? slen[comp].$1 : slen[comp].$2);
        }
        final ix = Int32List(576);
        final e0 = math.min(sfbLong44[r0 + 1], bv * 2);
        final e1 = math.min(sfbLong44[math.min(r0 + r1 + 2, 22)], bv * 2);
        for (var i = 0; i < bv * 2; i += 2) {
          final t = [t0, t1, t2][i < e0 ? 0 : (i < e1 ? 1 : 2)];
          if (t == 0) continue;
          final lin = linbitsOf[t];
          final pair = _readCode(rd, maps[t < 16 ? t : (t < 24 ? 16 : 24)]!);
          for (final (k, raw) in [(0, pair >> 4), (1, pair & 15)]) {
            var v = raw;
            if (lin > 0 && v == 15) v += rd.get(lin);
            if (v != 0 && rd.get(1) == 1) v = -v;
            ix[i + k] = v;
          }
        }
        var q = bv * 2;
        while (rd.pos < bit + len) {
          final f = _readCode(rd, c1[c1t]);
          for (var k = 0; k < 4; k++) {
            if ((f >> (3 - k)) & 1 == 1) ix[q + k] = rd.get(1) == 1 ? -1 : 1;
          }
          q += 4;
        }
        _expect(rd.pos == bit + len, 'granule length');
        bit += len;
        final gain = math.pow(2, (gg - 214 - (ms ? 2 : 0)) / 4);
        var band = 0;
        final xr = Float64List(576);
        for (var i = 0; i < 576; i++) {
          while (i >= sfbLong44[band + 1]) {
            band++;
          }
          xr[i] =
              (ix[i].sign *
                      math.pow(ix[i].abs(), 4 / 3) *
                      gain *
                      math.pow(2, -sf[band] / 2))
                  .toDouble();
        }
        lines[ch] = xr;
      }
      if (ms) {
        for (var i = 0; i < 576; i++) {
          final a = lines[0][i], b = lines[1][i];
          lines[0][i] = a + b;
          lines[1][i] = a - b;
        }
      }
      for (var ch = 0; ch < nch; ch++) {
        pcm[gr][ch] = decs[ch].granule(lines[ch]);
      }
    }
    for (var gr = 0; gr < 2; gr++) {
      for (var i = 0; i < 576; i++) {
        for (var ch = 0; ch < nch; ch++) {
          out.add(pcm[gr][ch][i].round().clamp(-32768, 32767));
        }
      }
    }
    p += size;
  }
  return Int16List.fromList(out);
}

double snr(Int16List a, Int16List b, int channels) {
  var sig = 0.0, err = 0.0;
  final n = math.min(a.length, b.length);
  for (var i = 2000 * channels; i < n - 2000 * channels; i++) {
    sig += a[i] * a[i].toDouble();
    err += math.pow(a[i] - b[i], 2);
  }
  return 10 * math.log(sig / err) / math.ln10;
}
