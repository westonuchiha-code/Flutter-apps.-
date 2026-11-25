// Look check: close-ups of worn things from all round (no clipping).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/moves.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  test('clip check', () async {
    final looks = <(Kind, Set<Extra>)>[
      (Kind.woman, {Extra.cap, Extra.glasses}),
      (Kind.woman, {Extra.jacket, Extra.beard, Extra.glasses}),
      (Kind.man, {Extra.hat, Extra.backpack}),
      (Kind.teen, {Extra.cap, Extra.backpack, Extra.glasses}),
      (Kind.oldMan, {Extra.jacket, Extra.glasses, Extra.hat}),
    ];
    const yaws = [0.0, 40.0, 90.0, 140.0, 200.0, 300.0];
    const w = 220, h = 220;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final r = Renderer();
    for (var row = 0; row < looks.length; row++) {
      final (kind, extras) = looks[row];
      final c = buildCharacter(kind, defaultLooks[kind]!, extras: extras);
      restPose(c);
      clipsFor(c)['idle']!.apply(0.6);
      final scene = Scene(
        sky: 0xFF39404E,
        ambient: 0xFF707480,
        sunDirection: Vector3(-0.4, -1, -0.6),
        sunColor: 0xFFE0D8C8,
      )..root.add(c.root);
      final headY = c.hipsY + 0.62;
      for (var col = 0; col < yaws.length; col++) {
        final a = yaws[col] * math.pi / 180;
        final rig = OrbitRig(
          target: Vector3(0, headY - 0.08, 0),
          distance: 0.75,
          yaw: a,
          pitch: -0.15,
        )..update(0);
        canvas.save();
        canvas.translate(col * w.toDouble(), row * h.toDouble());
        canvas.clipRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
        r.paint(
          canvas,
          const ui.Size(w * 1.0, h * 1.0),
          scene,
          rig.camera,
          const RenderOptions(lowRes: 0, wobble: false),
        );
        canvas.restore();
      }
    }
    final img = await rec.endRecording().toImage(
      w * yaws.length,
      h * looks.length,
    );
    File('$out/clip_check.png').writeAsBytesSync(
      (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List(),
    );
  });
}
