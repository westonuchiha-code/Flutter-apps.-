import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab3d/main.dart';
import 'package:lab3d/src/home.dart';
import 'package:lab3d/src/world.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the lab world draws thousands of triangles in PS1 mode', () async {
    final w = await LabWorld.build();
    final r = Renderer();
    final rec = ui.PictureRecorder();
    final rig = WalkRig(
      start: Vector3(0, 1.6, 8),
      walls: w.walls,
      ground: LabWorld.hills,
    )..update(1);
    r.paint(
      ui.Canvas(rec),
      const ui.Size(800, 480),
      w.scene,
      rig.camera,
      const RenderOptions(),
    );
    expect(r.stats.triangles, greaterThan(3000));
    expect(r.stats.drawn, greaterThan(500));
    expect(r.stats.height, 240);
    rec.endRecording().dispose();
    // Walls stop you walking out.
    for (var i = 0; i < 200; i++) {
      rig.move(-1, 0, 1 / 30);
    }
    expect(rig.camera.position.z, lessThan(12));
    // A model replaces the cube on the showcase.
    w.setModel(loadObj('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n'));
    expect(w.cube.visible, isFalse);
    expect(w.showcase.children.length, 2);
  });

  testWidgets('home page shows the viewport and controls', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('lab3d');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final world = (await tester.runAsync(LabWorld.build))!;
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(world: world),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Viewport3D), findsOneWidget);
    expect(find.textContaining('triangles'), findsOneWidget);
    await tester.tap(find.byTooltip('Orbit the showcase'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byTooltip('Walk around'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
