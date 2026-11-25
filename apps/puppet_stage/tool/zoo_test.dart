// The animals (art check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/animals.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/moves.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  test('zoo', () async {
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
      (Animal.horse, 'idle', 0.5, -3.6, -1.0, 40.0),
      (Animal.cow, 'eat', 0.3, -1.2, -1.3, 70.0),
      (Animal.pig, 'idle', 0.3, 1.1, -0.6, -60.0),
      (Animal.dog, 'sit', 1.0, -2.2, 1.0, 25.0),
      (Animal.cat, 'idle', 0.4, -0.9, 1.4, 50.0),
      (Animal.chicken, 'peck', 0.4, 0.4, 1.3, -40.0),
      (Animal.bird, 'flap', 0.5, 1.5, 1.6, -70.0),
      (Animal.dog, 'run', 0.2, 2.8, 0.4, -80.0),
    ];
    for (var i = 0; i < plan.length; i++) {
      final (a, move, t, x, z, f) = plan[i];
      final c = buildAnimal(a, animalLooks[a]!);
      c.root
        ..position = Vector3(x, 0, z)
        ..rotation = Quaternion.axisAngle(Vector3(0, 1, 0), f * 3.14159 / 180);
      final clip = clipsFor(c)[move]!;
      restPose(c);
      clip.apply(clip.duration * t);
      scene.root.add(c.root);
    }
    final r = Renderer();
    final rec = ui.PictureRecorder();
    final cam = Camera(position: Vector3(0, 1.6, 5.6), pitch: -0.2, fov: 55);
    r.paint(
      ui.Canvas(rec),
      const ui.Size(960, 400),
      scene,
      cam,
      const RenderOptions(lowRes: 0, wobble: false),
    );
    final img = await rec.endRecording().toImage(960, 400);
    File('$out/zoo.png').writeAsBytesSync(
      (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List(),
    );
  });
}
