// Local check: imported models doing built-in moves (needs test models in
// MODELS; renders contact sheets to OUT).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/figure.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/sets.dart';

void main() {
  const dir = String.fromEnvironment('MODELS');
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final f in Directory(dir).listSync().whereType<File>()) {
    if (!f.path.endsWith('.glb')) continue;
    final name = f.uri.pathSegments.last.split('.').first;
    testWidgets(name, (tester) async {
      await tester.runAsync(() async {
        final fig = await loadModelFigure(
          f.readAsBytesSync(),
          'glb',
          ownWalk: false,
        );
        // ignore: avoid_print
        print('$name: humanoid ${fig.humanoid}, own ${fig.own.keys.toList()}');
        final scene = await buildSet(StageSet.studio);
        scene.root.add(fig.root);
        final cam = Camera()
          ..position = Vector3(0, 1.1, 3.6)
          ..yaw = 0
          ..pitch = -0.08;
        const ids = [
          'idle',
          'walk',
          'wave',
          'jump',
          'sit',
          'kick',
          'cheer',
          'lie',
        ];
        const w = 240, h = 300;
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        final r = Renderer();
        for (var i = 0; i < ids.length; i++) {
          final m = ids[i];
          final t = m == 'sit' || m == 'lie' || m == 'jump' ? 0.6 : 0.3;
          fig.apply(ActorState(0, 0, 25, m, t));
          canvas.save();
          canvas.translate((i % 4) * w.toDouble(), (i ~/ 4) * h.toDouble());
          canvas.clipRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
          r.paint(
            canvas,
            const ui.Size(w * 1.0, h * 1.0),
            scene,
            cam,
            RenderOptions.clean,
          );
          canvas.restore();
        }
        final img = await rec.endRecording().toImage(w * 4, h * 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/model_$name.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }
}
