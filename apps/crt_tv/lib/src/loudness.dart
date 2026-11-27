import 'dart:math';
import 'dart:typed_data';

/// How loud a video is, in decibels below full scale (so always <= 0).
class Loudness {
  const Loudness(this.level, this.peak);

  /// Typical loudness of the parts that aren't near-silent.
  final double level;

  /// The loudest single moment.
  final double peak;

  List<double> toJson() => [level, peak];

  static Loudness? fromJson(Object? json) {
    if (json is! List || json.length != 2) return null;
    final level = json[0];
    final peak = json[1];
    if (level is! num || peak is! num) return null;
    return Loudness(level.toDouble(), peak.toDouble());
  }
}

/// Measures 16-bit mono sound. Works in 0.4 second blocks and leaves out the
/// quiet ones (silence, gaps between lines), the way broadcast loudness
/// meters do, so a talky film and a wall-to-wall cartoon compare fairly.
/// Returns null for silence.
Loudness? analyseLoudness(Int16List samples, int sampleRate) {
  final blockSize = (sampleRate * 0.4).round();
  final blocks = <double>[];
  var peak = 0;
  for (var start = 0; start + blockSize <= samples.length; start += blockSize) {
    var sum = 0.0;
    for (var i = start; i < start + blockSize; i++) {
      final s = samples[i];
      sum += s * s;
      final magnitude = s < 0 ? -s : s;
      if (magnitude > peak) peak = magnitude;
    }
    blocks.add(sum / blockSize / (32768.0 * 32768.0));
  }

  double mean(Iterable<double> values) {
    var total = 0.0;
    var count = 0;
    for (final v in values) {
      total += v;
      count++;
    }
    return count == 0 ? 0 : total / count;
  }

  // Anything under -60 dB is silence; then drop what's 10 dB under the rest.
  final audible = blocks.where((b) => b > 1e-6).toList();
  if (audible.isEmpty || peak == 0) return null;
  final floor = mean(audible) / 10;
  final level = mean(audible.where((b) => b >= floor));
  return Loudness(10 * log(level) / ln10, 20 * log(peak / 32768) / ln10);
}

/// The level every video is brought to.
const double kTargetLevel = -23;

/// How many decibels to turn a video up (+) or down (-) to match the rest.
/// A video is never turned up so far that its loudest moment would distort,
/// and never moved by a silly amount if the measurement was odd.
double levelingGain(Loudness loudness) {
  const headroom = 1.0;
  final wanted = kTargetLevel - loudness.level;
  final safe = min(wanted, -headroom - loudness.peak);
  return safe.clamp(-18.0, 12.0).toDouble();
}
