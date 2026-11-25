// Look check: every animal doing every move (contact sheets to OUT).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/animals.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/moves.dart';
import 'package:puppet_stage/src/sets.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final animal in Animal.values) {
    testWidgets('sheet ${animal.name}', (tester) async {
      await tester.runAsync(() async {
        final ms = movesFor(animal.rig);
        const w = 260, h = 220, cols = 6;
        final rows = (ms.length + cols - 1) ~/ cols;
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        final r = Renderer();
        final c = buildAnimal(animal, animalLooks[animal]!);
        final clips = clipsFor(c);
        final scene = await buildSet(StageSet.studio);
        scene.root.add(c.root);
        final b = boundsOf(c.root)!;
        final size = [
          b[3] - b[0],
          b[4] - b[1],
          b[5] - b[2],
        ].reduce((a, b) => a > b ? a : b);
        final d = size * 1.6;
        for (var i = 0; i < ms.length; i++) {
          final m = ms[i];
          final fly = m.id == 'fly';
          final rig = OrbitRig(
            target: Vector3(
              (b[0] + b[3]) / 2,
              (b[1] + b[4]) / 2 + (fly ? 1.2 : 0),
              (b[2] + b[5]) / 2,
            ),
            distance: d,
            yaw: 1.15,
            pitch: -0.25,
          )..update(0);
          final cam = rig.camera;
          applyState(
            c,
            clips,
            ActorState(0, 0, 0, m.id, m.loop ? m.duration * 0.3 : m.duration),
          );
          canvas.save();
          canvas.translate(
            (i % cols) * w.toDouble(),
            (i ~/ cols) * h.toDouble(),
          );
          canvas.clipRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
          r.paint(
            canvas,
            const ui.Size(w * 1.0, h * 1.0),
            scene,
            cam,
            RenderOptions.clean,
          );
          final tp = TextPainter(
            text: TextSpan(
              text: m.label,
              style: const TextStyle(color: Color(0xFF000000), fontSize: 14),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, const Offset(6, 4));
          canvas.restore();
        }
        final img = await rec.endRecording().toImage(w * cols, h * rows);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/animal_${animal.name}.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }
}
