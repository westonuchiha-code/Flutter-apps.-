import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lofi_video/main.dart';
import 'package:lofi_video/src/controller.dart';
import 'package:lofi_video/src/media.dart';
import 'package:lofi_video/src/preview.dart';
import 'package:lofi_video/src/project.dart';
import 'package:lofi_video/src/ui/home.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_kit/video_kit.dart';

import 'support.dart';

Future<VideoController> sampleController(Directory dir) async {
  final c = VideoController(
    preview: DirectPreview(),
    storage: AppStorage(dir),
    withSound: false,
  );
  await c.init();
  c.addMedia('clip', decodeMedia(clipExtension, await makeClip(dir)));
  c.addMedia('sprite', decodeMedia('json', makeSprite()));
  await c.addScene(
    Scene(
      kind: SceneKind.title,
      text: 'NIGHT\nSHIFT',
      textColor: 0xFFFFEC27,
      background: 0xFF1D2B53,
      duration: 1.5,
    ),
  );
  await c.addScene(
    Scene(
      kind: SceneKind.clip,
      asset: {'id': 'clip', 'name': 'ZX Spectrum video'},
      label: 'ZX Spectrum video',
      duration: 2,
      transition: Transition.vhs,
    ),
  );
  await c.addScene(
    Scene(
      kind: SceneKind.sprite,
      asset: {'id': 'sprite', 'name': 'Blob'},
      label: 'Blob',
      duration: 2,
      effectId: 'gbcam',
    ),
  );
  await c.addScene(
    Scene(
      kind: SceneKind.bars,
      duration: 2,
      effectId: 'vhs',
      label: 'Test bars',
      transition: Transition.teletext,
      overlays: [
        SceneOverlay(
          kind: OverlayKind.text,
          text: 'PRESS PLAY',
          color: 0xFFFFEC27,
          y: 0.8,
          scale: 3,
        ),
      ],
    ),
  );
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('editing, saving and reopening a storyboard', () async {
    final dir = Directory.systemTemp.createTempSync('lofi_c');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = await sampleController(dir);
    expect(c.duration, 6.5); // the short sprite loop starts at 1 s
    await c.seek(2);
    expect(c.currentScene, 1);
    expect(c.image, isNotNull);
    await c.moveScene(3, 0);
    expect(c.project.scenes.first.kind, SceneKind.bars);
    await c.duplicateScene(c.project.scenes.first);
    expect(c.project.scenes.length, 5);
    expect(c.project.scenes[0].id, isNot(c.project.scenes[1].id));
    await c.flush();
    c.dispose();

    final again = VideoController(
      preview: DirectPreview(),
      storage: AppStorage(dir),
      withSound: false,
    );
    await again.init();
    expect(again.project.scenes.length, 5);
    expect(again.project.scenes.first.effectId, 'vhs');
    expect(again.titles.isNotEmpty, isTrue);
    again.dispose();
  });

  testWidgets('home page lists the storyboard', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('lofi_w');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final c = (await tester.runAsync(() => sampleController(dir)))!;
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(controller: c),
      ),
    );
    await tester.pump();
    expect(find.text('NIGHT SHIFT'), findsOneWidget);
    expect(find.text('Add scene'), findsOneWidget);
    expect(find.textContaining('→ VHS tracking roll'), findsOneWidget);
    expect(find.textContaining('+1 on top'), findsOneWidget);
    expect(tester.takeException(), isNull);
    c.dispose();
  });
}
