// Screenshots on a phone and a desktop window (layout check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:chip_cam/main.dart';
import 'package:chip_cam/src/controller.dart';
import 'package:chip_cam/src/processor.dart';
import 'package:chip_cam/src/source.dart';
import 'package:chip_cam/src/ui/home.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_kit/video_kit.dart';

class CardSource extends FrameSource {
  void Function(VideoFrame f)? onFrame;
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
  Future<void> stop() async {}
}

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final (name, size, dpr, effect, crt) in [
    ('cam_phone', const Size(1080, 2340), 2.625, 'zx', false),
    ('cam_phone_ntsc', const Size(1080, 2340), 2.625, 'vhs', true),
    ('cam_desktop', const Size(1400, 860), 1.0, 'ruttetra', false),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('cam_shot');
      final src = CardSource();
      final c = ChipCamController(processor: DirectProcessor(), source: src);
      final services = (await tester.runAsync(() async {
        for (final (fam, files) in [
          (
            'Roboto',
            [
              'Regular',
              'Medium',
              'SemiBold',
            ].map((w) => '/usr/share/fonts/opentype/inter/Inter-$w.otf'),
          ),
          (
            'MaterialIcons',
            [
              '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ],
          ),
        ]) {
          final l = FontLoader(fam);
          for (final f in files) {
            l.addFont(
              Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
            );
          }
          await l.load();
        }
        final s = await ShellServices.create(appConfig, root: dir);
        s.settings.set(themeModeSetting, 'dark');
        await c.init();
        final i = c.effects.indexWhere((e) => e.id == effect);
        c.selectEffect(i < 0 ? 0 : i);
        if (crt) c.toggleCrt();
        for (var t = 0.0; t < 1.5; t += 0.1) {
          src.onFrame!(testCard(t));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        return s;
      }))!;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('s'),
          child: ShellApp(
            services: services,
            home: (_) => HomePage(controller: c),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('s')),
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }
}
