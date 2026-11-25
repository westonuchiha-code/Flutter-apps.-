// The MP3 decoder's subband synthesis, ported from dr_mp3 (the decoder
// flutter_soloud plays MP3s with; its scalar path, one channel). The
// encoder probes it to build an analysis filter that matches it exactly,
// and the tests decode with it.
import 'dart:typed_data';

const _win = <double>[
  -1,
  26,
  -31,
  208,
  218,
  401,
  -519,
  2063,
  2000,
  4788,
  -5517,
  7134,
  5959,
  35640,
  -39336,
  74992, //
  -1,
  24,
  -35,
  202,
  222,
  347,
  -581,
  2080,
  1952,
  4425,
  -5879,
  7640,
  5288,
  33791,
  -41176,
  74856,
  -1,
  21,
  -38,
  196,
  225,
  294,
  -645,
  2087,
  1893,
  4063,
  -6237,
  8092,
  4561,
  31947,
  -43006,
  74630,
  -1,
  19,
  -41,
  190,
  227,
  244,
  -711,
  2085,
  1822,
  3705,
  -6589,
  8492,
  3776,
  30112,
  -44821,
  74313,
  -1,
  17,
  -45,
  183,
  228,
  197,
  -779,
  2075,
  1739,
  3351,
  -6935,
  8840,
  2935,
  28289,
  -46617,
  73908,
  -1,
  16,
  -49,
  176,
  228,
  153,
  -848,
  2057,
  1644,
  3004,
  -7271,
  9139,
  2037,
  26482,
  -48390,
  73415,
  -2,
  14,
  -53,
  169,
  227,
  111,
  -919,
  2032,
  1535,
  2663,
  -7597,
  9389,
  1082,
  24694,
  -50137,
  72835,
  -2,
  13,
  -58,
  161,
  224,
  72,
  -991,
  2001,
  1414,
  2330,
  -7910,
  9592,
  70,
  22929,
  -51853,
  72169,
  -2,
  11,
  -63,
  154,
  221,
  36,
  -1064,
  1962,
  1280,
  2006,
  -8209,
  9750,
  -998,
  21189,
  -53534,
  71420,
  -2,
  10,
  -68,
  147,
  215,
  2,
  -1137,
  1919,
  1131,
  1692,
  -8491,
  9863,
  -2122,
  19478,
  -55178,
  70590,
  -3,
  9,
  -73,
  139,
  208,
  -29,
  -1210,
  1870,
  970,
  1388,
  -8755,
  9935,
  -3300,
  17799,
  -56778,
  69679,
  -3,
  8,
  -79,
  132,
  200,
  -57,
  -1283,
  1817,
  794,
  1095,
  -8998,
  9966,
  -4533,
  16155,
  -58333,
  68692,
  -4,
  7,
  -85,
  125,
  189,
  -83,
  -1356,
  1759,
  605,
  814,
  -9219,
  9959,
  -5818,
  14548,
  -59838,
  67629,
  -4,
  7,
  -91,
  117,
  177,
  -106,
  -1428,
  1698,
  402,
  545,
  -9416,
  9916,
  -7154,
  12980,
  -61289,
  66494,
  -5,
  6,
  -97,
  111,
  163,
  -127,
  -1498,
  1634,
  185,
  288,
  -9585,
  9838,
  -8540,
  11455,
  -62684,
  65290,
];

const _sec = <double>[
  10.19000816, 0.50060302, 0.50241929, 3.40760851, 0.50547093, 0.52249861, //
  2.05778098, 0.51544732, 0.56694406, 1.48416460, 0.53104258, 0.64682180,
  1.16943991, 0.55310392, 0.78815460, 0.97256821, 0.58293498, 1.06067765,
  0.83934963, 0.62250412, 1.72244716, 0.74453628, 0.67480832, 5.10114861,
];

void _dct2(Float64List g, int n) {
  final t = List.generate(4, (_) => Float64List(8));
  for (var k = 0; k < n; k++) {
    final y = k;
    for (var i = 0; i < 8; i++) {
      final x0 = g[y + i * 18], x1 = g[y + (15 - i) * 18];
      final x2 = g[y + (16 + i) * 18], x3 = g[y + (31 - i) * 18];
      final t0 = x0 + x3, t1 = x1 + x2;
      final t2 = (x1 - x2) * _sec[3 * i], t3 = (x0 - x3) * _sec[3 * i + 1];
      t[0][i] = t0 + t1;
      t[1][i] = (t0 - t1) * _sec[3 * i + 2];
      t[2][i] = t3 + t2;
      t[3][i] = (t3 - t2) * _sec[3 * i + 2];
    }
    for (var i = 0; i < 4; i++) {
      final x = t[i];
      var x0 = x[0], x1 = x[1], x2 = x[2], x3 = x[3];
      var x4 = x[4], x5 = x[5], x6 = x[6], x7 = x[7];
      var xt = x0 - x7;
      x0 += x7;
      x7 = x1 - x6;
      x1 += x6;
      x6 = x2 - x5;
      x2 += x5;
      x5 = x3 - x4;
      x3 += x4;
      x4 = x0 - x3;
      x0 += x3;
      x3 = x1 - x2;
      x1 += x2;
      x[0] = x0 + x1;
      x[4] = (x0 - x1) * 0.70710677;
      x5 = x5 + x6;
      x6 = (x6 + x7) * 0.70710677;
      x7 = x7 + xt;
      x3 = (x3 + x4) * 0.70710677;
      x5 -= x7 * 0.198912367;
      x7 += x5 * 0.382683432;
      x5 -= x7 * 0.198912367;
      x0 = xt - x6;
      xt += x6;
      x[1] = (xt + x7) * 0.50979561;
      x[2] = (x4 + x3) * 0.54119611;
      x[3] = (x0 - x5) * 0.60134488;
      x[5] = (x0 + x5) * 0.89997619;
      x[6] = (x4 - x3) * 1.30656302;
      x[7] = (xt - x7) * 2.56291556;
    }
    var o = y;
    for (var i = 0; i < 7; i++, o += 4 * 18) {
      g[o] = t[0][i];
      g[o + 18] = t[2][i] + t[3][i] + t[3][i + 1];
      g[o + 36] = t[1][i] + t[1][i + 1];
      g[o + 54] = t[2][i + 1] + t[3][i] + t[3][i + 1];
    }
    g[o] = t[0][7];
    g[o + 18] = t[2][7] + t[3][7];
    g[o + 36] = t[1][7];
    g[o + 54] = t[3][7];
  }
}

void _pair(Float64List pcm, int p, Float64List l, int z) {
  var a = (l[z + 14 * 64] - l[z]) * 29;
  a += (l[z + 64] + l[z + 13 * 64]) * 213;
  a += (l[z + 12 * 64] - l[z + 2 * 64]) * 459;
  a += (l[z + 3 * 64] + l[z + 11 * 64]) * 2037;
  a += (l[z + 10 * 64] - l[z + 4 * 64]) * 5153;
  a += (l[z + 5 * 64] + l[z + 9 * 64]) * 6574;
  a += (l[z + 8 * 64] - l[z + 6 * 64]) * 37489;
  a += l[z + 7 * 64] * 75038;
  pcm[p] = a;
  z += 2;
  a = l[z + 14 * 64] * 104;
  a += l[z + 12 * 64] * 1567;
  a += l[z + 10 * 64] * 9727;
  a += l[z + 8 * 64] * 64019;
  a += l[z + 6 * 64] * -9975;
  a += l[z + 4 * 64] * -45;
  a += l[z + 2 * 64] * 146;
  a += l[z] * -5;
  pcm[p + 16] = a;
}

void _synth(
  Float64List g,
  int xl,
  Float64List pcm,
  int p,
  Float64List l,
  int lb,
) {
  final zl = lb + 15 * 64;
  l[zl + 4 * 15] = g[xl + 18 * 16];
  l[zl + 4 * 15 + 2] = g[xl];
  l[zl + 4 * 31] = g[xl + 1 + 18 * 16];
  l[zl + 4 * 31 + 2] = g[xl + 1];
  _pair(pcm, p, l, lb + 4 * 15);
  _pair(pcm, p + 32, l, lb + 4 * 15 + 64);
  var w = 0;
  final a = Float64List(4), b = Float64List(4);
  for (var i = 14; i >= 0; i--) {
    l[zl + 4 * i] = g[xl + 18 * (31 - i)];
    l[zl + 4 * i + 2] = g[xl + 1 + 18 * (31 - i)];
    l[zl + 4 * (i + 16)] = g[xl + 1 + 18 * (1 + i)];
    l[zl + 4 * (i - 16) + 2] = g[xl + 18 * (1 + i)];
    for (var k = 0; k < 8; k++) {
      final w0 = _win[w++], w1 = _win[w++];
      final vz = zl + 4 * i - k * 64, vy = zl + 4 * i - (15 - k) * 64;
      for (var j = 0; j < 4; j += 2) {
        final z = l[vz + j], y = l[vy + j];
        if (k == 0) {
          b[j] = z * w1 + y * w0;
          a[j] = z * w0 - y * w1;
        } else if (k.isOdd) {
          b[j] += z * w1 + y * w0;
          a[j] += y * w1 - z * w0;
        } else {
          b[j] += z * w1 + y * w0;
          a[j] += z * w0 - y * w1;
        }
      }
    }
    pcm[p + 15 - i] = a[0];
    pcm[p + 17 + i] = b[0];
    pcm[p + 47 - i] = a[2];
    pcm[p + 49 + i] = b[2];
  }
}

/// One channel of subband synthesis, as the decoder does it.
class SynthBank {
  final _qmf = Float64List(15 * 64);
  final _lins = Float64List(33 * 64);

  /// [granule]: 32 subbands × 18 slots (`granule[18 * sb + slot]`), changed
  /// in place. Returns 576 samples (16-bit scale).
  Float64List run(Float64List granule) {
    _dct2(granule, 18);
    _lins.setRange(0, 15 * 64, _qmf);
    final pcm = Float64List(576);
    for (var i = 0; i < 18; i += 2) {
      _synth(granule, i, pcm, 32 * i, _lins, i * 64);
    }
    _qmf.setRange(0, 15 * 64, _lins, 18 * 64);
    return pcm;
  }
}

// ---- Layer III long blocks (dr_mp3's antialias, imdct36, change_sign) ----

const aaCs = <double>[
  0.85749293, 0.88174200, 0.94962865, 0.98331459, //
  0.99551782, 0.99916056, 0.99989920, 0.99999316,
];
const aaCa = <double>[
  0.51449576, 0.47173197, 0.31337745, 0.18191320, //
  0.09457419, 0.04096558, 0.01419856, 0.00369997,
];

/// The decoder's alias reduction over a granule (31 band boundaries).
void antialias(Float64List g) {
  for (var b = 0; b < 31; b++) {
    final o = b * 18;
    for (var i = 0; i < 8; i++) {
      final u = g[o + 18 + i], d = g[o + 17 - i];
      g[o + 18 + i] = u * aaCs[i] - d * aaCa[i];
      g[o + 17 - i] = u * aaCa[i] + d * aaCs[i];
    }
  }
}

void _dct3x9(Float64List y) {
  var s0 = y[0], s2 = y[2], s4 = y[4], s6 = y[6], s8 = y[8];
  var t0 = s0 + s6 * 0.5;
  s0 -= s6;
  var t4 = (s4 + s2) * 0.93969262;
  var t2 = (s8 + s2) * 0.76604444;
  s6 = (s4 - s8) * 0.17364818;
  s4 += s8 - s2;
  s2 = s0 - s4 * 0.5;
  y[4] = s4 + s0;
  s8 = t0 - t2 + s6;
  s0 = t0 - t4 + t2;
  s4 = t0 + t4 - s6;
  var s1 = y[1], s3 = y[3], s5 = y[5], s7 = y[7];
  s3 *= 0.86602540;
  t0 = (s5 + s1) * 0.98480775;
  t4 = (s5 - s7) * 0.34202014;
  t2 = (s1 + s7) * 0.64278761;
  s1 = (s1 - s5 - s7) * 0.86602540;
  s5 = t0 - s3 - t2;
  s7 = t4 - s3 - t0;
  s3 = t4 + s3 - t2;
  y[0] = s4 - s7;
  y[1] = s2 + s1;
  y[2] = s0 - s3;
  y[3] = s8 + s5;
  y[5] = s8 - s5;
  y[6] = s0 + s3;
  y[7] = s2 - s1;
  y[8] = s4 + s7;
}

const _twid9 = <double>[
  0.73727734, 0.79335334, 0.84339145, 0.88701083, 0.92387953, 0.95371695, //
  0.97629601, 0.99144486, 0.99904822, 0.67559021, 0.60876143, 0.53729961,
  0.46174861, 0.38268343, 0.30070580, 0.21643961, 0.13052619, 0.04361938,
];
const _window = <double>[
  0.99904822, 0.99144486, 0.97629601, 0.95371695, 0.92387953, 0.88701083, //
  0.84339145, 0.79335334, 0.73727734, 0.04361938, 0.13052619, 0.21643961,
  0.30070580, 0.38268343, 0.46174861, 0.53729961, 0.60876143, 0.67559021,
];

/// One band's 36-point IMDCT (normal long window): 18 values at [g]+[o] in,
/// 18 samples out (with the 9-value [overlap] at [ov] from the last granule).
void imdct36(Float64List g, int o, Float64List overlap, int ov) {
  final co = Float64List(9), si = Float64List(9);
  co[0] = -g[o];
  si[0] = g[o + 17];
  for (var i = 0; i < 4; i++) {
    si[8 - 2 * i] = g[o + 4 * i + 1] - g[o + 4 * i + 2];
    co[1 + 2 * i] = g[o + 4 * i + 1] + g[o + 4 * i + 2];
    si[7 - 2 * i] = g[o + 4 * i + 4] - g[o + 4 * i + 3];
    co[2 + 2 * i] = -(g[o + 4 * i + 3] + g[o + 4 * i + 4]);
  }
  _dct3x9(co);
  _dct3x9(si);
  si[1] = -si[1];
  si[3] = -si[3];
  si[5] = -si[5];
  si[7] = -si[7];
  for (var i = 0; i < 9; i++) {
    final ovl = overlap[ov + i];
    final sum = co[i] * _twid9[9 + i] + si[i] * _twid9[i];
    overlap[ov + i] = co[i] * _twid9[i] - si[i] * _twid9[9 + i];
    g[o + i] = ovl * _window[i] - sum * _window[9 + i];
    g[o + 17 - i] = ovl * _window[9 + i] + sum * _window[i];
  }
}

/// Odd samples of odd bands change sign.
void changeSign(Float64List g) {
  for (var b = 1; b < 32; b += 2) {
    for (var i = 1; i < 18; i += 2) {
      g[b * 18 + i] = -g[b * 18 + i];
    }
  }
}

/// A decoder channel for long blocks: dequantized lines in, PCM out.
class LongDecoder {
  final _overlap = Float64List(32 * 9);
  final _synth = SynthBank();

  Float64List granule(Float64List xr) {
    final g = Float64List.fromList(xr);
    antialias(g);
    for (var b = 0; b < 32; b++) {
      imdct36(g, b * 18, _overlap, b * 9);
    }
    changeSign(g);
    return _synth.run(g);
  }
}
