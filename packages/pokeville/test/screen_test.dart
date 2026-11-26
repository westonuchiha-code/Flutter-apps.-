// The widgets: keys / pad, taps, long-press drag, swipe, B leaving, and
// PokevilleHome's "no Pokéville yet" page.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pokeville/pokeville.dart';

import 'fixtures.dart';

void main() {
  late Directory temp;
  late String dir;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pokeville_screen');
    dir = makePokeville(temp.path);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  BoxData onDisk() =>
      PokeBoxStore.parse(File(p.join(dir, 'box.json')).readAsStringSync())!;

  // The wide layout's slot centres (the PC's 1920×1080 coordinates).
  Offset slot(int i) =>
      Offset(690 + (i % 6) * 160 + 80, 270 + (i ~/ 6) * 112 + 56);

  Future<(PokevilleController, List<int>)> pump(
    WidgetTester tester, {
    bool swapAB = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.reset);
    final c = PokevilleController(PokevilleFolder(dir, runner: runHere));
    await c.open();
    final left = <int>[];
    final sprites = PokeSprites(
      p.join(temp.path, 'sprites'),
      fetcher: (_) async => null,
    );
    addTearDown(sprites.dispose);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PokevilleScreen(
          dir,
          temp.path,
          controller: c,
          sprites: sprites,
          swapAB: swapAB,
          onLeave: () => left.add(1),
        ),
      ),
    );
    await tester.pump();
    return (c, left);
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  testWidgets('keys: arrows, Enter picks up / puts down, Esc backs out', (
    tester,
  ) async {
    final (c, left) = await pump(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(c.slotIndex, 1);
    await key(tester, LogicalKeyboardKey.enter);
    expect(c.held!.mon.name, 'Kingdra');
    await key(tester, LogicalKeyboardKey.pageDown);
    expect(c.page, 1);
    await key(tester, LogicalKeyboardKey.gameButtonA);
    await tester.pump();
    expect(c.holding, isFalse);
    expect(Mon.of(PokeBoxStore.slot(onDisk(), 1, 1))!.name, 'Kingdra');
    await key(tester, LogicalKeyboardKey.keyY);
    expect(c.view, PokeView.check);
    await key(tester, LogicalKeyboardKey.escape);
    expect(c.view, PokeView.box);
    await key(tester, LogicalKeyboardKey.keyX);
    expect(c.menuOpen, isTrue);
    await key(tester, LogicalKeyboardKey.gameButtonB);
    expect(c.menuOpen, isFalse);
    expect(left, isEmpty);
    await key(tester, LogicalKeyboardKey.escape);
    expect(left, [1], reason: 'nothing left to back out of: leave');
  });

  testWidgets("swapAB: the pad's A and B trade places (Enter doesn't)", (
    tester,
  ) async {
    final (c, left) = await pump(tester, swapAB: true);
    await key(tester, LogicalKeyboardKey.gameButtonB);
    expect(c.holding, isTrue);
    await key(tester, LogicalKeyboardKey.gameButtonA);
    expect(c.holding, isFalse);
    await key(tester, LogicalKeyboardKey.enter);
    expect(c.holding, isTrue);
    expect(left, isEmpty);
  });

  testWidgets('taps: select, pick up, put down; buttons; strip', (
    tester,
  ) async {
    final (c, _) = await pump(tester);
    await tester.tapAt(slot(2));
    await tester.pump();
    expect((c.slotIndex, c.holding), (2, false));
    await tester.tapAt(slot(2));
    await tester.pump();
    expect(c.held!.mon.name, 'Dodrio');
    await tester.tapAt(slot(20));
    await tester.pump();
    await tester.tapAt(slot(20));
    await tester.pump();
    expect(Mon.of(PokeBoxStore.slot(onDisk(), 0, 20))!.name, 'Dodrio');
    // the Y button, then Check's footer (B)
    await tester.tapAt(const Offset(1800, 540));
    await tester.pump();
    expect(c.view, PokeView.check);
    await tester.tapAt(const Offset(960, 1062));
    await tester.pump();
    expect(c.view, PokeView.box);
    // the strip's second box
    await tester.tapAt(const Offset(640 + 178 + 82, 955));
    await tester.pump();
    expect(c.page, 1);
    // the banner's left arrow
    await tester.tapAt(const Offset(950, 204));
    await tester.pump();
    expect(c.page, 0);
  });

  testWidgets('long-press and drag carries one; a swipe changes box', (
    tester,
  ) async {
    final (c, _) = await pump(tester);
    final g = await tester.startGesture(slot(0));
    await tester.pump(const Duration(milliseconds: 700));
    expect(c.held!.mon.name, 'Meowth');
    await g.moveTo(slot(9));
    await tester.pump();
    await g.moveTo(slot(15));
    await tester.pump();
    expect(c.slotIndex, 15);
    await g.up();
    await tester.pump();
    expect(c.holding, isFalse);
    expect(Mon.of(PokeBoxStore.slot(onDisk(), 0, 15))!.name, 'Meowth');
    await tester.flingFrom(slot(26), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(c.page, 1);
  });

  testWidgets('every layout paints without errors, every view', (tester) async {
    final (c, _) = await pump(tester);
    for (final size in const [
      Size(1920, 1080),
      Size(1280, 720),
      Size(451, 393),
      Size(844, 390),
      Size(390, 844),
      Size(360, 640),
      Size(320, 480),
    ]) {
      tester.view.physicalSize = size;
      for (final setUp in <void Function()>[
        () {},
        () => c.check(),
        () {
          c.check();
          c.setTab(1);
        },
        () {
          c.check();
          c.setTab(2);
        },
        () => c.menu(),
        () => c.step(0, -1),
      ]) {
        while (c.cancel()) {}
        c.select(0);
        setUp();
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size');
      }
    }
  });

  testWidgets('PokevilleHome: no box.json yet, then one arrives', (
    tester,
  ) async {
    File(p.join(dir, 'box.json')).deleteSync();
    final left = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PokevilleHome(
          dir,
          temp.path,
          onLeave: () => left.add(1),
          fetcher: (_) async => null,
        ),
      ),
    );
    expect(find.text('No Pokéville here yet'), findsOneWidget);
    expect(find.textContaining('sync first'), findsOneWidget);
    await tester.tap(find.text('Look again'));
    await tester.pump();
    expect(find.byType(PokevilleScreen), findsNothing);
    copyTree(exampleDir, dir);
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(PokevilleScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PokevilleHome: B leaves', (tester) async {
    File(p.join(dir, 'box.json')).deleteSync();
    final left = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PokevilleHome(dir, temp.path, onLeave: () => left.add(1)),
      ),
    );
    await tester.tap(find.text('Back'));
    expect(left, [1]);
  });
}
