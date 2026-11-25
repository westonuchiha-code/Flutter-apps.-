/// A song's map for the music video director: tempo, where bar 1 starts,
/// and what each bar is (section, energy, whether someone sings or the DJ
/// cuts). Comes from the album renderer (`.songmap.json`, exact) or is
/// worked out from any WAV's loudness (tempo given or tapped).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// One bar of the song.
class BarInfo {
  const BarInfo(
    this.section, {
    this.energy = 0.5,
    this.vocal = false,
    this.dj = false,
  });

  /// intro, verse, hook, break or outro.
  final String section;

  /// 0..1: how hard the bar hits (cuts get quicker as it rises).
  final double energy;

  /// Someone sings this bar (the leads mouth it).
  final bool vocal;

  /// The DJ cuts this bar.
  final bool dj;

  Map<String, Object?> toJson() => {
    's': section,
    'e': double.parse(energy.toStringAsFixed(2)),
    if (vocal) 'v': true,
    if (dj) 'dj': true,
  };

  factory BarInfo.fromJson(Map j) => BarInfo(
    '${j['s'] ?? 'verse'}',
    energy: ((j['e'] as num?) ?? 0.5).toDouble(),
    vocal: j['v'] == true,
    dj: j['dj'] == true,
  );
}

class SongMap {
  const SongMap({required this.bpm, this.offset = 0, required this.bars});

  final double bpm;

  /// Seconds into the audio where bar 1 starts.
  final double offset;
  final List<BarInfo> bars;

  static const kind = 'song_map';

  double get barSeconds => 240 / bpm;
  double timeOf(num bar) => offset + bar * barSeconds;
  double get seconds => timeOf(bars.length);

  Map<String, Object?> toJson() => {
    'kind': kind,
    'bpm': bpm,
    if (offset != 0) 'offset': offset,
    'bars': [for (final b in bars) b.toJson()],
  };

  factory SongMap.fromJson(Map j) => SongMap(
    bpm: ((j['bpm'] as num?) ?? 90).toDouble(),
    offset: ((j['offset'] as num?) ?? 0).toDouble(),
    bars: [
      for (final b in (j['bars'] as List?) ?? const [])
        if (b is Map) BarInfo.fromJson(b),
    ],
  );

  /// A map from audio alone ([pcm] 44.1 kHz stereo): loudness per bar
  /// becomes energy; loud stretches are hooks, quiet ones breaks, the rest
  /// verses, in groups of four bars. The first and last bars are the intro
  /// and outro.
  factory SongMap.fromAudio(Int16List pcm, double bpm, {double offset = 0}) {
    final barFrames = (240 / bpm * 44100).round();
    final total = pcm.length ~/ 2;
    final n = math.max(1, ((total - offset * 44100) / barFrames).floor());
    final rms = <double>[];
    for (var b = 0; b < n; b++) {
      final s = (offset * 44100).round() + b * barFrames;
      var sum = 0.0;
      var count = 0;
      for (var i = s; i < s + barFrames && i < total; i += 4) {
        final v = (pcm[i * 2] + pcm[i * 2 + 1]) / 65536;
        sum += v * v;
        count++;
      }
      rms.add(count == 0 ? 0 : math.sqrt(sum / count));
    }
    final lo = rms.reduce(math.min), hi = rms.reduce(math.max);
    final energy = [
      for (final r in rms) hi - lo < 1e-6 ? 0.5 : (r - lo) / (hi - lo),
    ];
    final bars = <BarInfo>[];
    for (var g = 0; g < n; g += 4) {
      final group = energy.sublist(g, math.min(n, g + 4));
      final e = group.reduce((a, b) => a + b) / group.length;
      for (var b = g; b < g + group.length; b++) {
        final section = b < 2
            ? 'intro'
            : b >= n - 2
            ? 'outro'
            : e > 0.7
            ? 'hook'
            : e < 0.3
            ? 'break'
            : 'verse';
        bars.add(BarInfo(section, energy: energy[b]));
      }
    }
    return SongMap(bpm: bpm, offset: offset, bars: bars);
  }

  /// Just bars [from]..[to] (times shift so [from] is 0).
  SongMap slice(int from, int to) => SongMap(
    bpm: bpm,
    offset: 0,
    bars: bars.sublist(from.clamp(0, bars.length), to.clamp(0, bars.length)),
  );
}

/// Tempo from taps (seconds between them), rounded to a tenth of a BPM.
double? tempoFromTaps(List<double> times) {
  if (times.length < 4) return null;
  final gaps = [for (var i = 1; i < times.length; i++) times[i] - times[i - 1]]
    ..sort();
  final mid = gaps[gaps.length ~/ 2];
  if (mid <= 0) return null;
  var bpm = 60 / mid;
  while (bpm < 60) {
    bpm *= 2;
  }
  while (bpm > 180) {
    bpm /= 2;
  }
  return (bpm * 10).round() / 10;
}
