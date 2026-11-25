// Templates and extras (art check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/moves.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  test('templates', () async {
    final scene = Scene(
      sky: 0xFF39404E,
      ambient: 0xFF707480,
      sunDirection: Vector3(-0.4, -1, -0.6),
      sunColor: 0xFFE0D8C8,
    );
    scene.root.add(
      Node(
        mesh: planeMesh(14, 8, split: 8, tile: 1),
        material: Surface(color: 0xFF8A8478),
        layer: -1,
      ),
    );
    final plan = <(Kind, String, double, Body, Set<Extra>)>[
      (Kind.bigMan, 'idle', 0.5, const Body(), {}),
      (Kind.teen, 'wave', 0.4, const Body(), {Extra.cap, Extra.backpack}),
      (Kind.toddler, 'cheer', 0.3, const Body(), {}),
      (Kind.robot, 'point', 0.8, const Body(), {}),
      (Kind.woman, 'idle', 0.3, const Body(), {Extra.dress, Extra.hat}),
      (
        Kind.man,
        'think',
        0.5,
        const Body(),
        {Extra.jacket, Extra.glasses, Extra.beard},
      ),
      (
        Kind.man,
        'shrug',
        0.5,
        const Body(head: 1.6, legs: 0.7, build: 1.3),
        {},
      ),
      (
        Kind.woman,
        'idle',
        0.5,
        const Body(height: 1.2, build: 0.7, legs: 1.3),
        {},
      ),
    ];
    for (var i = 0; i < plan.length; i++) {
      final (kind, move, t, body, extras) = plan[i];
      final c = buildCharacter(
        kind,
        defaultLooks[kind]!,
        body: body,
        extras: extras,
      );
      c.root.position = Vector3(-4.9 + i * 1.4, 0, 0);
      final clip = clipsFor(c)[move]!;
      restPose(c);
      clip.apply(clip.duration * t);
      scene.root.add(c.root);
    }
    final r = Renderer();
    final rec = ui.PictureRecorder();
    final cam = Camera(position: Vector3(0, 1.2, 7.2), pitch: -0.06, fov: 55);
    r.paint(
      ui.Canvas(rec),
      const ui.Size(1200, 420),
      scene,
      cam,
      const RenderOptions(lowRes: 0, wobble: false),
    );
    final img = await rec.endRecording().toImage(1200, 420);
    File('$out/templates.png').writeAsBytesSync(
      (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List(),
    );
  });
}
