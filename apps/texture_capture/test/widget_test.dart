import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:texture_capture/main.dart';
import 'package:texture_capture/src/controller.dart';
import 'package:texture_capture/src/engine/formats.dart';
import 'package:texture_capture/src/engine/surface.dart';
import 'package:texture_capture/src/ui/home.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a photographed wall becomes an even, tiling texture', () async {
    final shot = photoOf(bricks(512));
    final c = TextureController(useIsolates: false);
    await c.setPhoto(shot.photo);
    for (var i = 0; i < 4; i++) {
      c.moveCorner(i, shot.corners[i]);
    }
    await c.setMasterSize(512);
    final m = c.master!;
    expect(m.width, 512);
    expect(LightMap(m).unevenness, lessThan(1.3));
    expect(seamScore(m), lessThan(1.6));
    expect(c.consolePic!.width, c.size);
    // Other console and format.
    await c.selectConsole(consoles.firstWhere((p) => p.id == 'gc'));
    expect(c.consolePic!.width, 256);
    final png = await c.consolePng();
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    // Turning swaps width-ways and height-ways.
    final before = List.of(c.settings!.corners);
    await c.rotate();
    expect(c.settings!.corners.first, before.last);
    c.dispose();
  });

  testWidgets('empty page, then the three tabs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('texture_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final c = TextureController(useIsolates: false);
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(controller: c),
      ),
    );
    expect(find.text('Picture on this device'), findsOneWidget);
    final shot = photoOf(bricks(256), w: 600, h: 450);
    await tester.runAsync(() => c.setPhoto(shot.photo));
    await tester.pump();
    expect(find.text('Corners'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Texture')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Make seamless'), findsOneWidget);
    await tester.tap(find.text('Console'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dreamcast'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(c.console.id, 'dc');
    expect(tester.takeException(), isNull);
    c.dispose();
  });
}
