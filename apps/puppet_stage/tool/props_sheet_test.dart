// Look check: every prop (contact sheet to OUT).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/props.dart';
import 'package:puppet_stage/src/sets.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  testWidgets('props', (tester) async {
    await tester.runAsync(() async {
      const w = 240, h = 220, cols = 6;
      final rows = (Prop.values.length + cols - 1) ~/ cols;
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec);
      final r = Renderer();
      for (var i = 0; i < Prop.values.length; i++) {
        final p = Prop.values[i];
        final scene = await buildSet(StageSet.studio);
        final node = scene.root.add(buildProp(p, propLooks[p]!));
        final b = boundsOf(node)!;
        final size = [
          b[3] - b[0],
          b[4] - b[1],
          b[5] - b[2],
        ].reduce((a, b) => a > b ? a : b);
        final rig = OrbitRig(
          target: Vector3(
            (b[0] + b[3]) / 2,
            (b[1] + b[4]) / 2,
            (b[2] + b[5]) / 2,
          ),
          distance: size * 1.7 + 0.2,
          yaw: 0.7,
          pitch: -0.3,
        )..update(0);
        canvas.save();
        canvas.translate((i % cols) * w.toDouble(), (i ~/ cols) * h.toDouble());
        canvas.clipRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
        r.paint(
          canvas,
          const ui.Size(w * 1.0, h * 1.0),
          scene,
          rig.camera,
          RenderOptions.clean,
        );
        canvas.restore();
      }
      final img = await rec.endRecording().toImage(w * cols, h * rows);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/props.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
