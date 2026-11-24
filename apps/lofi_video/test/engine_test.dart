import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lofi_video/src/export.dart';
import 'package:lofi_video/src/media.dart';
import 'package:lofi_video/src/mix.dart';
import 'package:lofi_video/src/project.dart';
import 'package:lofi_video/src/render.dart';
import 'package:lofi_video/src/title.dart';
import 'package:video_kit/video_kit.dart';

import 'support.dart';

bool get hasFfmpeg => Process.runSync('which', ['ffprobe']).exitCode == 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Map<String, Media> media;
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('lofi_test');
    media = decodeAll({
      'clip': (clipExtension, await makeClip(dir)),
      'sprite': ('json', makeSprite()),
      'music': ('wav', makeMusic()),
    });
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  Project sample() => Project(
    scenes: [
      Scene(
        kind: SceneKind.title,
        text: 'HELLO',
        textColor: 0xFFFFEC27,
        background: 0xFF1D2B53,
        duration: 1,
      ),
      Scene(
        kind: SceneKind.clip,
        asset: {'id': 'clip'},
        duration: 1.5,
        clipStart: 0.25,
      ),
      Scene(
        kind: SceneKind.sprite,
        asset: {'id': 'sprite'},
        duration: 1,
        background: 0xFF000000,
      ),
      Scene(kind: SceneKind.bars, duration: 1, effectId: 'vhs'),
      Scene(kind: SceneKind.clip, asset: {'id': 'missing'}, duration: 0.5),
    ],
    music: {'id': 'music'},
  );

  test('project JSON round trip and timing', () {
    final p = sample();
    final q = Project.fromJson(jsonDecode(jsonEncode(p.toJson())));
    expect(q.scenes.length, 5);
    expect(q.duration, 5);
    expect(q.scenes[1].clipStart, 0.25);
    expect(q.scenes[3].effectId, 'vhs');
    expect(q.sceneAt(0.5), (0, 0.5));
    expect(q.sceneAt(1.2).$1, 1);
    expect(q.sceneAt(99).$1, 4);
  });

  test('media decoding', () {
    expect(media['clip'], isA<ClipMedia>());
    final s = media['sprite'] as AnimMedia;
    expect(s.frames.length, 2);
    expect(s.at(0).pixels.first, 0xFFFF004D);
    expect(s.at(0.15).pixels[130], 0xFF00E436);
    final m = media['music'] as SoundMedia;
    expect(m.seconds, closeTo(4, 0.01));
  });

  test('fitting keeps 4:3 and sharp pixels', () {
    final src = VideoFrame(2, 1, Uint32List.fromList([0xFFFF0000, 0xFF0000FF]));
    final f = fitInto(src, 320, 240);
    expect(f.at(10, 120), 0xFFFF0000);
    expect(f.at(310, 120), 0xFF0000FF);
    expect(f.at(10, 10), 0xFF000000); // bars above
    final c = fitInto(src, 320, 240, fit: Fit.cover);
    expect(c.at(0, 0), 0xFFFF0000);
  });

  test('renderer draws each scene', () async {
    final p = sample();
    final titles = {p.scenes[0].id: await renderTitle(p.scenes[0])};
    final r = Renderer(p, media, titles);
    final title = r.frameAt(0.5);
    expect(title.pixels.toSet(), {0xFFFFEC27, 0xFF1D2B53}); // two colours only
    final clip = r.frameAt(1.5);
    expect(clip.width, canvasWidth);
    final sprite = r.frameAt(2.5);
    expect(
      sprite.pixels.contains(0xFFFF004D) || sprite.pixels.contains(0xFF00E436),
      isTrue,
    );
    final vhs = r.frameAt(3.5);
    expect(vhs.width, greaterThan(0));
    expect(r.frameAt(4.8).pixels.first, 0xFF202020); // missing source
  });

  test('mix: music plus clip sound, no clipping, faded end', () {
    final pcm = mixAudio(sample(), media);
    expect(pcm.length, 5 * mixRate * 2);
    var peak = 0;
    for (final v in pcm) {
      if (v.abs() > peak) peak = v.abs();
    }
    expect(peak, lessThanOrEqualTo(32767));
    expect(peak, greaterThan(9000)); // the clip adds to the music
    expect(pcm[pcm.length - 2].abs(), lessThan(200));
  });

  test('export makes a playable video with sound', () async {
    final p = sample();
    final titles = {p.scenes[0].id: await renderTitle(p.scenes[0])};
    final job = ExportJob(
      project: p,
      media: media,
      titles: titles,
      width: 320,
      height: 240,
      fps: 15,
    );
    final seen = <double>[];
    job.progress.stream.listen(seen.add);
    final file = await job.run('${dir.path}/out');
    expect(file, isNotNull);
    expect(seen.last, 1.0);
    if (!hasFfmpeg) return;
    final probe = Process.runSync('ffprobe', [
      '-v',
      'error',
      '-show_streams',
      '-show_format',
      '-of',
      'json',
      file!.path,
    ]);
    expect(probe.exitCode, 0, reason: '${probe.stderr}');
    final j = jsonDecode(probe.stdout as String) as Map;
    final streams = (j['streams'] as List).cast<Map>();
    expect(
      streams.map((s) => s['codec_type']),
      containsAll(['video', 'audio']),
    );
    expect(
      double.parse((j['format'] as Map)['duration'] as String),
      closeTo(5, 0.15),
    );
    // The title's background colour shows in the first frame.
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
    final rgb = dec.stdout as List<int>;
    final o = (10 * 320 + 10) * 3;
    expect(rgb[o], closeTo(0x1D, 12));
    expect(rgb[o + 2], closeTo(0x53, 12));
  });
}
