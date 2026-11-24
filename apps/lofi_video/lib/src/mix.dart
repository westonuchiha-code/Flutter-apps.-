import 'dart:math' as math;
import 'dart:typed_data';

import 'media.dart';
import 'project.dart';

/// The whole soundtrack: the music plus each clip's own sound (where it is
/// on), as interleaved stereo 16-bit at [mixRate]. Short fades stop clicks
/// at cuts; a soft limiter stops clipping.
Int16List mixAudio(Project p, Map<String, Media> media) {
  final total = (p.duration * mixRate).round();
  final l = Float32List(total), r = Float32List(total);
  final music = media[p.music?['id']];
  if (music is SoundMedia) {
    final offset = (p.musicStart * mixRate).round();
    final n = math.min(total, music.left.length - offset);
    for (var i = 0; i < n; i++) {
      l[i] += music.left[i + offset] * p.musicVolume;
      r[i] += music.right[i + offset] * p.musicVolume;
    }
  }
  final starts = p.starts;
  final fadeLen = mixRate ~/ 100;
  for (var i = 0; i < p.scenes.length; i++) {
    final s = p.scenes[i];
    final m = s.assetId == null ? null : media[s.assetId];
    if (s.kind != SceneKind.clip ||
        !s.clipSound ||
        m is! ClipMedia ||
        !m.clip.hasSound) {
      continue;
    }
    final sound = m.clip.sound;
    final rate = m.clip.sampleRate;
    final start = (starts[i] * mixRate).round();
    final len = math.min((s.duration * mixRate).round(), total - start);
    for (var k = 0; k < len; k++) {
      final pos = (s.clipStart + k / mixRate) * rate;
      final a = pos.floor();
      if (a + 1 >= sound.length) {
        break;
      }
      final t = pos - a;
      var v = (sound[a] * (1 - t) + sound[a + 1] * t) / 32768 * p.clipVolume;
      if (k < fadeLen) {
        v *= k / fadeLen;
      }
      if (len - k < fadeLen) {
        v *= (len - k) / fadeLen;
      }
      l[start + k] += v;
      r[start + k] += v;
    }
  }
  // Fade the end out over half a second.
  final end = math.min(total, mixRate ~/ 2);
  for (var k = 0; k < end; k++) {
    final g = k / end;
    l[total - 1 - k] *= g;
    r[total - 1 - k] *= g;
  }
  final out = Int16List(total * 2);
  for (var i = 0; i < total; i++) {
    out[i * 2] = _toPcm(l[i]);
    out[i * 2 + 1] = _toPcm(r[i]);
  }
  return out;
}

/// Soft knee above 0.9 so loud mixes squash instead of clipping.
int _toPcm(double x) {
  final a = x.abs();
  final y = a < 0.9 ? a : 0.9 + 0.0999 * _tanh((a - 0.9) / 0.1);
  return ((x < 0 ? -y : y) * 32767).round();
}

double _tanh(double x) {
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
