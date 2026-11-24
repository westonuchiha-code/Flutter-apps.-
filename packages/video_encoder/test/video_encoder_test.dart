import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_encoder/video_encoder.dart';

bool get hasFfmpeg => Process.runSync('which', ['ffprobe']).exitCode == 0;

void main() {
  test('I420 levels', () {
    final px = Uint32List.fromList([
      0xFFFFFFFF,
      0xFFFFFFFF,
      0xFF000000,
      0xFF000000,
    ]);
    final yuv = argbToI420(px, 2, 2);
    expect(yuv.sublist(0, 4), [235, 235, 16, 16]);
    expect(yuv[4], 128);
    expect(yuv[5], 128);
    final red = argbToI420(
      Uint32List.fromList(List.filled(4, 0xFFFF0000)),
      2,
      2,
    );
    expect(red[0], 82);
    expect(red[4], closeTo(90, 1));
    expect(red[5], closeTo(240, 1));
  });

  test('nearest upscale keeps pixels sharp and centred', () {
    final src = Uint32List.fromList([0xFFFF0000, 0xFF00FF00]);
    final out = upscaleNearest(src, 2, 1, 8, 6);
    // Scale 4 (8/2): 8×4 picture, one black row above and below.
    expect(out[0], 0xFF000000);
    expect(out[8 * 1 + 0], 0xFFFF0000);
    expect(out[8 * 1 + 3], 0xFFFF0000);
    expect(out[8 * 1 + 4], 0xFF00FF00);
    expect(out[8 * 5], 0xFF000000);
  });

  test('audio frames per video frame never drift', () {
    const s = VideoSpec(width: 64, height: 48, fps: 30, sampleRate: 44100);
    var total = 0;
    for (var i = 0; i < 300; i++) {
      total += s.audioFramesFor(i);
    }
    expect(total, 441000);
  });

  test('AVI plays in ffmpeg with the right streams and length', () async {
    final dir = Directory.systemTemp.createTempSync('avi_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    const spec = VideoSpec(width: 160, height: 120, fps: 25, sampleRate: 22050);
    final w = await openVideoWriter('${dir.path}/clip', spec);
    expect(w, isA<AviWriter>());
    for (var i = 0; i < 50; i++) {
      final px = Uint32List(160 * 120);
      for (var p = 0; p < px.length; p++) {
        px[p] = p % 160 < 80 ? 0xFFFF0000 : 0xFF0000FF;
      }
      await w.addFrame(px);
      final n = spec.audioFramesFor(i);
      final pcm = Int16List(n * 2);
      for (var k = 0; k < n; k++) {
        final v = (math.sin(k * 0.1) * 8000).round();
        pcm[k * 2] = v;
        pcm[k * 2 + 1] = v;
      }
      await w.addAudio(pcm);
    }
    final file = await w.finish();
    expect(file.path, endsWith('.avi'));
    if (!hasFfmpeg) return;
    final probe = Process.runSync('ffprobe', [
      '-v',
      'error',
      '-show_streams',
      '-show_format',
      '-of',
      'json',
      file.path,
    ]);
    expect(probe.exitCode, 0, reason: probe.stderr as String);
    final j = jsonDecode(probe.stdout as String) as Map;
    final streams = j['streams'] as List;
    final video = streams.firstWhere((s) => s['codec_type'] == 'video') as Map;
    final audio = streams.firstWhere((s) => s['codec_type'] == 'audio') as Map;
    expect(video['codec_name'], 'mjpeg');
    expect(video['width'], 160);
    expect(audio['codec_name'], 'pcm_s16le');
    expect(audio['sample_rate'], '22050');
    expect(
      double.parse((j['format'] as Map)['duration'] as String),
      closeTo(2.0, 0.05),
    );
    // Decodes without errors, and the picture is right (left red).
    final dec = Process.runSync('ffmpeg', [
      '-v',
      'error',
      '-i',
      file.path,
      '-frames:v',
      '1',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'rgb24',
      '-',
    ], stdoutEncoding: null);
    expect(dec.exitCode, 0, reason: '${dec.stderr}');
    final rgb = dec.stdout as List<int>;
    final o = (60 * 160 + 20) * 3;
    expect(rgb[o], greaterThan(200));
    expect(rgb[o + 2], lessThan(60));
  });
}
