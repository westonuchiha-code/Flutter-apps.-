// The cast doing moves (art check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/moves.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  test('cast', () async {
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
    final plan = [
      (Kind.man, 'walk', 0.3),
      (Kind.woman, 'wave', 0.4),
      (Kind.boy, 'cheer', 0.3),
      (Kind.girl, 'dance', 0.2),
      (Kind.oldMan, 'think', 0.5),
      (Kind.oldWoman, 'idle', 0.5),
    ];
    for (var i = 0; i < plan.length; i++) {
      final (kind, move, t) = plan[i];
      final c = buildCharacter(kind, defaultLooks[kind]!);
      c.root.position = Vector3(-3.75 + i * 1.5, 0, 0);
      final clip = clipsFor(c)[move]!;
      restPose(c);
      clip.apply(clip.duration * t);
      scene.root.add(c.root);
    }
    final r = Renderer();
    final rec = ui.PictureRecorder();
    final cam = Camera(position: Vector3(0, 1.3, 6.5), pitch: -0.08, fov: 55);
    r.paint(
      ui.Canvas(rec),
      const ui.Size(960, 400),
      scene,
      cam,
      const RenderOptions(lowRes: 0, wobble: false),
    );
    final img = await rec.endRecording().toImage(960, 400);
    File('$out/cast.png').writeAsBytesSync(
      (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List(),
    );
  });
}
