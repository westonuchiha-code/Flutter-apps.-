// Screenshot of the ranch with a few monsters (text renders as boxes in
// tests). Run: flutter test tool/ranch_shot_test.dart --dart-define=OUT=/dir
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scan_ranch/main.dart';
import 'package:scan_ranch/model/game_state.dart';
import 'package:scan_ranch/render/monster_art.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  testWidgets('ranch shot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final game = GameState(MemorySaveStore(), random: math.Random(7));
    var code = 900000000000;
    while (game.ranch.length < 6) {
      final r = game.scan('${code++}');
      if (r is CreatureFound) game.keep(r.creature);
    }
    await tester.runAsync(() async {
      await MonsterArt.instance.load();
      for (final c in game.creatures) {
        await MonsterArt.instance.imageAsync(
          c.genome.silhouette,
          paletteFor(c.genome, c.individual),
        );
      }
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('s'),
        child: ScanRanchApp(game: game),
      ),
    );
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    await tester.runAsync(() async {
      // Let the background image decode.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 33));
    final b = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('s')),
    );
    await tester.runAsync(() async {
      final img = await b.toImage(pixelRatio: 1);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/ranch.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
