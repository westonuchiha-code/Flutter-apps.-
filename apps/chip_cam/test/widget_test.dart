import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:chip_cam/main.dart';
import 'package:chip_cam/src/controller.dart';
import 'package:chip_cam/src/processor.dart';
import 'package:chip_cam/src/source.dart';
import 'package:chip_cam/src/ui/home.dart';
import 'package:chip_cam/src/video_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:video_kit/video_kit.dart';

/// Only the test card; frames are pushed by hand.
class FakeSource extends FrameSource {
  void Function(VideoFrame f)? onFrame;
  int stops = 0;

  @override
  Future<List<SourceOption>> list() async => const [
    SourceOption('Test card', 'test'),
  ];

  @override
  Future<void> start(
    SourceOption o,
    void Function(VideoFrame f) onFrame,
    void Function(String e) onError,
  ) async => this.onFrame = onFrame;

  @override
  Future<void> stop() async => stops++;

  Future<void> push(double t) async {
    onFrame!(testCard(t));
    // Let the processor and image decode finish.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  recorderTests();
  test('every effect goes through the controller to a picture', () async {
    final src = FakeSource();
    final c = ChipCamController(processor: DirectProcessor(), source: src);
    await c.init();
    for (var i = 0; i < c.effects.length; i++) {
      c.selectEffect(i);
      await src.push(i * 0.1);
      await src.push(i * 0.1 + 0.05);
      expect(c.output, isNotNull, reason: c.effect.name);
      expect(c.snapshotPng(), isNotNull);
    }
    c.dispose();
  });

  test('clips record at 10 fps, stop at the limit and make a GIF', () async {
    final src = FakeSource();
    final c = ChipCamController(processor: DirectProcessor(), source: src);
    await c.init();
    c.selectEffect(c.effects.indexWhere((e) => e.id == 'gbcam'));
    c.startClip();
    for (var i = 0; i < 12 && c.recording; i++) {
      await src.push(i * 0.1);
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
    expect(c.clip.length, greaterThan(3));
    c.stopClip();
    final gif = clipToGif(c.clip, scale: 2);
    final anim = img.decodeGif(gif)!;
    expect(anim.numFrames, c.clip.length);
    expect(anim.width, c.clip.first.width * 2);
    c.dispose();
  });

  test('a full-colour clip still makes a GIF', () {
    final frames = [for (var i = 0; i < 3; i++) testCard(i * 0.3)];
    final anim = img.decodeGif(clipToGif(frames))!;
    expect(anim.numFrames, 3);
  });

  testWidgets('home page shows effects and switches', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('chip_cam_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final src = FakeSource();
    final c = ChipCamController(processor: DirectProcessor(), source: src);
    await tester.runAsync(() async {
      await c.init();
      await src.push(0);
    });
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(controller: c),
      ),
    );
    await tester.pump();
    expect(find.text(c.effect.name), findsWidgets);
    final second = c.effects[1].name;
    await tester.tap(find.widgetWithText(ChoiceChip, second));
    await tester.pump();
    expect(c.effectIndex, 1);
    await tester.tap(find.byTooltip('Show on a CRT'));
    await tester.pump();
    expect(c.crt, isTrue);
    await tester.runAsync(() => src.push(1));
    await tester.pump();
    expect(tester.takeException(), isNull);
    c.dispose();
  });
}

void recorderTests() {
  test('video recording makes a clip at up to 15 fps', () async {
    final dir = Directory.systemTemp.createTempSync('chip_rec');
    addTearDown(() => dir.deleteSync(recursive: true));
    final r = VideoRecorder(withSound: false);
    await r.start(dir);
    final zx = runEffect(ZxSpectrum(), testCard(0), 0);
    for (var i = 0; i < 20; i++) {
      r.addFrame(i.isEven ? zx : testCard(i * 0.05));
      await Future<void>.delayed(const Duration(milliseconds: 35));
    }
    final file = await r.stop(extra: {'effect': 'zx'});
    expect(file, isNotNull);
    final clip = VideoClip.fromBytes(await file!.readAsBytes());
    expect(clip.frames.length, inInclusiveRange(5, 16));
    for (var i = 1; i < clip.frames.length; i++) {
      expect(
        clip.frames[i].time - clip.frames[i - 1].time,
        greaterThanOrEqualTo(1 / videoFps - 0.005),
      );
    }
    expect(clip.extra['effect'], 'zx');
    expect(clip.hasSound, isFalse);
  });
}
