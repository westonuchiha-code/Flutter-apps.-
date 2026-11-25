import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mp3_kit/mp3_kit.dart';
import 'package:mp3_kit/src/check_decoder.dart';
import 'package:mp3_kit/src/tables.dart';
import 'package:test/test.dart';

void main() {
  test('Huffman tables are complete prefix codes', () {
    for (final e in huffCodes.entries) {
      var kraft = 0.0;
      for (final c in e.value) {
        if (c != 0) kraft += math.pow(2, -(c & 31));
      }
      expect(kraft, closeTo(1, 1e-9), reason: 'table ${e.key}');
    }
    // Table 1 by the book: 1, 001, 01, 000.
    expect(huffCodes[1]!.sublist(0, 2), [1 << 5 | 1, 1 << 5 | 3]);
    expect(huffCodes[1]![16], 1 << 5 | 2);
    expect(huffCodes[1]![17], 0 << 5 | 3);
  });

  test('decoder filters reconstruct (analysis matches synthesis)', () {
    const n = 44100;
    final pcm = Int16List(n * 2);
    final rnd = math.Random(1);
    for (var i = 0; i < n; i++) {
      final v = (8000 * math.sin(i * 0.031) + 3000 * (rnd.nextDouble() - 0.5))
          .round();
      pcm[i * 2] = v;
      pcm[i * 2 + 1] = (6000 * math.sin(i * 0.17)).round();
    }
    final mp3 = encodeMp3(pcm, kbps: 320);
    expect(mp3.length, closeTo(n / 44100 * 320000 / 8, 3000));
    final back = decodeOwnMp3(mp3);
    print("stereo snr ${snr(pcm, back, 2)}");
    expect(snr(pcm, back, 2), greaterThan(25));
  });

  test('music-like signal at 192 and 320 kbps, mono, tags', () {
    const n = 44100;
    final pcm = Int16List(n);
    for (var i = 0; i < n; i++) {
      final t = i / 44100;
      var v = 0.0;
      for (var h = 1; h < 12; h++) {
        v += math.sin(2 * math.pi * 110 * h * t) / h;
      }
      pcm[i] = (v * 6000 * math.exp(-((i % 11025) / 8000))).round();
    }
    for (final kbps in [192, 320]) {
      final mp3 = encodeMp3(
        pcm,
        channels: 1,
        kbps: kbps,
        tags: const Mp3Tags(title: 'Test', artist: 'mp3_kit'),
      );
      expect(String.fromCharCodes(mp3.sublist(0, 3)), 'ID3');
      final back = decodeOwnMp3(mp3);
      print("mono $kbps snr ${snr(pcm, back, 1)}");
      expect(snr(pcm, back, 1), greaterThan(18), reason: '$kbps');
    }
  });
}
