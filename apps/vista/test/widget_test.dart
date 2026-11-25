import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vista/main.dart';
import 'package:vista/src/flyover.dart';
import 'package:vista/src/land.dart';
import 'package:vista/src/raytrace.dart';
import 'package:vista/src/sky.dart';
import 'package:vista/src/ui/home.dart';
import 'package:vista/src/world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a seed always makes the same land; settings round-trip', () {
    const s = LandSettings(seed: 42);
    final a = generate(s, n: 65), b = generate(s, n: 65);
    expect(a.h, b.h);
    final c = generate(s.copyWith(seed: 43), n: 65);
    expect(c.h, isNot(a.h));
    final back = LandSettings.fromJson(
      jsonDecode(jsonEncode(s.copyWith(time: 7.5, haze: 0.9).toJson())),
    );
    expect(back.seed, 42);
    expect(back.time, 7.5);
    expect(back.haze, 0.9);
    expect(
      () => LandSettings.fromJson({'kind': 'other'}),
      throwsFormatException,
    );
  });

  test('presets shape the land: islands in the sea, heights in range', () {
    final s = presets['islands']!.$2;
    final f = generate(s, n: 65);
    final sea = seaHeight(s);
    expect(f.at(0, 0), lessThan(sea)); // corners under water
    expect(
      f.h.reduce((a, b) => a > b ? a : b),
      greaterThan(sea),
    ); // land above it
    for (final p in presets.values) {
      final g = generate(p.$2, n: 33);
      expect(
        g.h.every((v) => v >= -1 && v <= LandSettings.maxHeight + 5),
        isTrue,
        reason: p.$1,
      );
    }
  });

  test('sky: day is blue overhead, night is dark, the sun sets', () {
    final noon = skyFor(const LandSettings(time: 12));
    final night = skyFor(const LandSettings(time: 23));
    expect(noon.sunHeight, greaterThan(0.5));
    expect(night.sunHeight, lessThan(0));
    expect(noon.zenith & 0xFF, greaterThan(150));
    expect(night.zenith & 0xFF, lessThan(80));
    expect(night.night, greaterThan(0.5));
  });

  test('ray tracing: sky at the top, ground below', () {
    const s = LandSettings(time: 12, clouds: 0);
    final f = generate(s, n: 65);
    final y = f.heightAt(0, 150) + 25;
    final job = TraceJob(s, f, Shot(0, y, 150, 0, -0.25), 32, 18);
    final img = Uint32List(32 * 18);
    placePass(img, 32, 18, tracePass((job, 0, 1, 1)), 0, 1, 1);
    final top = img[16], bottom = img[17 * 32 + 16];
    expect(top & 0xFF, greaterThan((top >> 16) & 0xFF)); // blue sky
    expect(top, isNot(bottom));
    // Two workers make the same picture as one.
    final split = Uint32List(32 * 18);
    for (var k = 0; k < 2; k++) {
      placePass(split, 32, 18, tracePass((job, k, 2, 1)), k, 2, 1);
    }
    expect(split, img);
  });

  test('camera path passes through its points', () {
    final p = CameraPath([
      const Shot(0, 10, 0, 0, 0),
      const Shot(10, 20, 0, 3, 0),
      const Shot(20, 10, 10, -3, 0.2),
    ]);
    expect(p.at(0).x, 0);
    expect(p.at(0.5).x, closeTo(10, 1e-9));
    expect(p.at(1).z, closeTo(10, 1e-9));
    // 3 → -3 radians turns the short way (through π), not all the way round.
    final mid = p.at(0.75).yaw;
    expect(mid.abs(), greaterThan(2.5));
    expect(pathFromJson(jsonDecode(jsonEncode(pathToJson(p)))).keys.length, 3);
  });

  test('fast flyover makes a video', () async {
    const s = LandSettings(seed: 3, clouds: 0.3);
    final world = await VistaWorld.build(s, generate(s, n: 65), detail: 33);
    final dir = Directory.systemTemp.createTempSync('vista');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold it.
      }
    });
    var last = 0.0;
    final file = await exportFlyover(
      world: world,
      path: CameraPath([
        const Shot(0, 60, 150, 0, -0.2),
        const Shot(50, 70, 50, 0.8, -0.3),
      ]),
      seconds: 1,
      basePath: '${dir.path}/fly',
      rayTraced: false,
      width: 160,
      height: 90,
      fps: 10,
      progress: (p) => last = p,
      cancelled: () => false,
      preferMp4: false,
    );
    expect(file, isNotNull);
    expect(file!.lengthSync(), greaterThan(1000));
    expect(last, 1.0);
  });

  testWidgets('home page builds a world and shows the tabs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('vista_ui');
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    await tester.pumpWidget(
      ShellApp(services: services, home: (_) => const HomePage()),
    );
    for (var i = 0; i < 40 && find.byType(Viewport3D).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(Viewport3D), findsOneWidget);
    expect(find.text('Land'), findsOneWidget);
    await tester.tap(find.text('Flyover'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Add this view'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('1 camera point'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
