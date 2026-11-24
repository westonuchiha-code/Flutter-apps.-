import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixel_forge/main.dart';
import 'package:pixel_forge/src/editor.dart';
import 'package:pixel_forge/src/ui/canvas_view.dart';
import 'package:pixel_forge/src/ui/home.dart';
import 'package:pixel_kit/pixel_kit.dart' as px;

void main() {
  testWidgets('draw with a finger; two fingers zoom instead of drawing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('forge_widget');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final e = Editor(sprite: px.Sprite.blank(16, 16))..setPrimary(0xFFFF0000);
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(editor: e),
      ),
    );
    await tester.pump();
    final view = tester.state<CanvasViewState>(find.byType(CanvasView));
    final origin = tester.getTopLeft(find.byType(CanvasView));

    // One finger: a line across row 5.
    final g = await tester.startGesture(origin + view.pixelCenter(1, 5));
    await g.moveTo(origin + view.pixelCenter(10, 5));
    await g.up();
    await tester.pump();
    expect(e.cel[5 * 16 + 1], 0xFFFF0000);
    expect(e.cel[5 * 16 + 10], 0xFFFF0000);

    // Two fingers: no drawing, the view zooms.
    final a = await tester.startGesture(
      origin + view.pixelCenter(2, 12),
      pointer: 5,
    );
    final b = await tester.startGesture(
      origin + view.pixelCenter(6, 12),
      pointer: 6,
    );
    await a.moveTo(origin + view.pixelCenter(0, 12));
    await b.moveTo(origin + view.pixelCenter(9, 12));
    await a.up();
    await b.up();
    await tester.pump();
    expect(
      [for (var x = 0; x < 16; x++) e.cel[12 * 16 + x]].every((v) => v == 0),
      isTrue,
    );
    expect(e.canUndo, isTrue);

    // Tools and layers.
    await tester.tap(find.byTooltip('Fill (G)'));
    await tester.pump();
    expect(e.tool, Tool.fill);
    await tester.tap(find.byTooltip('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New layer'));
    await tester.pump();
    expect(e.sprite.layers, hasLength(2));
    expect(find.text('Layer 2'), findsOneWidget);
  });
}
