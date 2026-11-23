// Phone screenshots of the editor and home screen (layout check).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:field_recorder/main.dart';
import 'package:field_recorder/src/editor_page.dart';
import 'package:field_recorder/src/home_page.dart';
import 'package:field_recorder/src/model.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/widget_test.dart' show SilentPlayer;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  testWidgets('shot', (tester) async {
    createPlayer = SilentPlayer.new;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('rec_shot');
    final takes = Takes(Directory('${dir.path}/takes'));
    final take = takes.newFile();
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
      const rate = 8000;
      final r = math.Random(3);
      final samples = Int16List(rate * 12);
      for (var i = 0; i < samples.length; i++) {
        final t = i / rate;
        final env = (math.sin(t * 1.7) * 0.5 + 0.5) * (t % 3 < 2 ? 1 : 0.15);
        samples[i] = ((r.nextDouble() * 2 - 1) * env * 20000).round();
      }
      final w = await WavFileWriter.create(
        take,
        const WavFormat(sampleRate: rate),
      );
      await w.add(samples.buffer.asUint8List());
      await w.close();
      await s.locker.save(
        type: AssetType.recording,
        name: 'Creek at dawn',
        bytes: [0],
        extension: 'wav',
        tags: ['outdoors', 'water'],
        thumbnail: await waveformPng(
          Float32List.fromList(List.generate(200, (i) => r.nextDouble())),
        ),
        extra: {
          'seconds': 94.0,
          'markers': [1, 2],
        },
      );
      return s;
    }))!;
    Future<void> io() async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('s')),
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('s'),
        child: ShellApp(
          services: services,
          home: (_) => HomePage(takes: takes),
        ),
      ),
    );
    await io();
    await shot('rec_home');
    await tester.tap(find.text('Unsaved recording'));
    await io();
    final wave = find.byType(WaveformView);
    final tl = tester.getTopLeft(wave);
    final size = tester.getSize(wave);
    await tester.dragFrom(
      tl + Offset(2, size.height / 2),
      Offset(size.width * 0.1, 0),
    );
    await tester.pump();
    await tester.tap(find.text('Marker'));
    await tester.tapAt(tl + Offset(size.width * 0.6, size.height / 2));
    await tester.pump();
    await tester.tap(find.text('Marker'));
    await tester.pump();
    await shot('rec_editor');
  });
}
