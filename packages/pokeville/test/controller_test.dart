// The screen logic: navigation, holding, moves written at once, the
// changed-on-disk refusal, Check, the Box Dex and the menu (the Box half of
// the PC's tools/PokeBoxTests.gd _screen_paging, plus the sync rule).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pokeville/pokeville.dart';

import 'fixtures.dart';

void main() {
  late Directory temp;
  late String dir;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pokeville_ctl');
    dir = makePokeville(temp.path);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<PokevilleController> opened() async {
    final c = PokevilleController(PokevilleFolder(dir, runner: runHere));
    await c.open();
    return c;
  }

  BoxData onDisk() =>
      PokeBoxStore.parse(File(p.join(dir, 'box.json')).readAsStringSync())!;

  test(
    'opens on Box 1; LB / RB wrap; walking off the edge changes box',
    () async {
      final c = await opened();
      expect(c.state, BoxState.ready);
      expect(c.page, 0);
      expect(c.pageCount, 2);
      expect(c.shown!.name, 'Meowth');
      expect(c.turnPage(-1), isTrue);
      expect(c.page, 1, reason: 'wraps to the last box');
      expect(c.turnPage(1), isTrue);
      expect(c.page, 0);
      expect(c.step(-1, 0), isTrue, reason: 'off the left edge');
      expect((c.page, c.col), (1, 5));
      expect(c.step(1, 0), isTrue);
      expect((c.page, c.col), (0, 0));
      expect(c.step(0, -1), isTrue);
      expect(c.row, -1, reason: 'up to the banner');
      expect(c.step(1, 0), isTrue);
      expect(c.page, 1, reason: 'left / right on the banner change box');
      expect(c.step(0, 1), isTrue);
      expect(c.row, 0);
    },
  );

  test(
    'pick up, put down on an empty slot: written at once, atomically',
    () async {
      final c = await opened();
      await c.confirm();
      expect(c.holding, isTrue);
      expect(c.held!.mon.name, 'Meowth');
      expect(c.heldIsHere(0), isTrue);
      expect(c.heldWhere, 'Box 1');
      c.turnPage(1);
      c.select(29);
      await c.confirm();
      expect(c.holding, isFalse);
      final d = onDisk();
      expect(PokeBoxStore.isEmpty(d, 0, 0), isTrue);
      expect(Mon.of(PokeBoxStore.slot(d, 1, 29))!.name, 'Meowth');
      expect(
        PokeBoxStore.boxCount(d),
        3,
        reason: 'Box 2 filled: a spare Box 3',
      );
      expect(File(p.join(dir, 'box.json.tmp')).existsSync(), isFalse);
    },
  );

  test(
    'putting one on another swaps them; back in its own slot changes nothing',
    () async {
      final c = await opened();
      final before = File(p.join(dir, 'box.json')).readAsStringSync();
      await c.confirm(); // Meowth
      await c.confirm(); // same slot
      expect(c.holding, isFalse);
      expect(File(p.join(dir, 'box.json')).readAsStringSync(), before);
      await c.confirm();
      c.select(1);
      await c.confirm(); // onto Kingdra
      final d = onDisk();
      expect(Mon.of(PokeBoxStore.slot(d, 0, 0))!.name, 'Kingdra');
      expect(Mon.of(PokeBoxStore.slot(d, 0, 1))!.name, 'Meowth');
    },
  );

  test('touch: the first tap selects, the next picks up / puts down', () async {
    final c = await opened();
    await c.tap(2);
    expect((c.slotIndex, c.holding), (2, false));
    await c.tap(2);
    expect(c.held!.mon.name, 'Dodrio');
    await c.tap(10);
    expect(c.holding, isTrue);
    await c.tap(10);
    expect(c.holding, isFalse);
    expect(Mon.of(PokeBoxStore.slot(onDisk(), 0, 10))!.name, 'Dodrio');
  });

  test('B lets go of a carried Pokémon, then says "leave"', () async {
    final c = await opened();
    await c.confirm();
    expect(c.cancel(), isTrue);
    expect(c.holding, isFalse);
    expect(c.cancel(), isFalse);
  });

  test(
    'box.json changed on disk (a sync): re-read, the move refused',
    () async {
      final c = await opened();
      await c.confirm(); // Meowth
      c.select(5);
      // a sync brings in a new box.json: Kingdra went to Box 2
      final synced = onDisk();
      PokeBoxStore.move(synced, 0, 1, 1, 0);
      final text = PokeBoxStore.encode(synced);
      File(p.join(dir, 'box.json')).writeAsStringSync(text);
      await c.confirm();
      expect(c.holding, isFalse);
      expect(c.notice, contains('changed on disk'));
      expect(
        File(p.join(dir, 'box.json')).readAsStringSync(),
        text,
        reason: 'not overwritten',
      );
      expect(c.pageMon(0, 1), isNull, reason: 'shows the synced Box');
      expect(c.pageMon(1, 0)!.name, 'Kingdra');
      expect(c.pageMon(0, 5), isNull);
      // and the next move works on the new one
      c.select(0);
      await c.confirm();
      c.select(5);
      await c.confirm();
      expect(Mon.of(PokeBoxStore.slot(onDisk(), 0, 5))!.name, 'Meowth');
    },
  );

  test('refreshIfChanged reads a synced box.json once', () async {
    final c = await opened();
    expect(await c.refreshIfChanged(), isFalse);
    final synced = onDisk();
    PokeBoxStore.clear(synced, 0, 2);
    File(p.join(dir, 'box.json'))
        .writeAsStringSync(PokeBoxStore.encode(synced));
    expect(await c.refreshIfChanged(), isTrue);
    expect(c.pageMon(0, 2), isNull);
    expect(c.notice, contains('updated'));
    expect(await c.refreshIfChanged(), isFalse);
  });

  test("a write that fails puts things back as they were", () async {
    final c = await opened();
    // a folder where box.json.tmp can't be made
    Directory(p.join(dir, 'box.json.tmp')).createSync();
    await c.confirm();
    c.select(7);
    await c.confirm();
    expect(c.notice, contains("Couldn't save"));
    expect(c.pageMon(0, 0)!.name, 'Meowth');
    expect(c.pageMon(0, 7), isNull);
  });

  test('Check: tabs, other Pokémon, the Box Dex', () async {
    final c = await opened();
    c.select(1); // Kingdra, No. 230
    expect(c.check(), isTrue);
    expect(c.view, PokeView.check);
    expect(c.dexPage, 3, reason: '181-240');
    expect(c.owned, {52, 85, 230});
    c.tabCount = 2;
    expect(c.step(1, 0), isTrue);
    expect(c.tab, 1);
    expect(
      c.step(1, 0),
      isFalse,
      reason: 'two tabs beside the Dex on wide screens',
    );
    c.tabCount = 3;
    expect(c.step(1, 0), isTrue);
    expect(c.tab, 2);
    expect(c.step(0, 1), isTrue);
    expect(c.shown!.name, 'Dodrio');
    expect(c.dexPage, 1);
    expect(c.step(0, 1), isTrue);
    expect(c.shown!.name, 'Meowth', reason: 'wraps round the box');
    expect(c.dexPage, 0);
    expect(c.turnPage(-1), isTrue);
    expect(c.dexPage, c.dexPages - 1, reason: 'Dex pages wrap');
    expect(c.turnPage(1), isTrue);
    expect(c.dexPage, 0);
    expect(c.page, 0, reason: 'LB / RB turn the Dex, not the Box');
    await c.confirm();
    expect(c.notice, OnThePc.edit);
    expect(c.menu(), isFalse, reason: 'no menu in Check');
    expect(c.cancel(), isTrue);
    expect(c.view, PokeView.box);
  });

  test('the menu: every box, then games (on the PC)', () async {
    final c = await opened();
    expect(c.menu(), isTrue);
    expect(c.menuOpen, isTrue);
    expect(c.menuRows.map((r) => r.title), ['Box 1', 'Box 2', 'Your games']);
    expect(c.menuRows[0].detail, '3 Pokémon');
    expect(c.menuRows.last.enabled, isFalse);
    expect(c.step(0, 1), isTrue);
    await c.confirm();
    expect(c.menuOpen, isFalse);
    expect(c.page, 1);
    c.menu();
    c.menuSelect(2);
    await c.confirm();
    expect(c.menuOpen, isTrue);
    expect(c.notice, OnThePc.games);
    expect(c.cancel(), isTrue);
    expect(c.menuOpen, isFalse);
    expect(c.menu(), isTrue);
    expect(c.menu(), isTrue, reason: 'X again closes it');
    expect(c.menuOpen, isFalse);
  });

  test('carrying one across boxes, Check shows the carried one', () async {
    final c = await opened();
    await c.confirm();
    c.turnPage(1);
    expect(c.shown!.name, 'Meowth');
    c.check();
    expect(c.shown!.name, 'Meowth');
    c.cancel();
    expect(c.holding, isTrue, reason: 'B leaves Check first');
  });

  test('a folder without box.json, and a broken one', () async {
    File(p.join(dir, 'box.json')).deleteSync();
    final c = await opened();
    expect(c.state, BoxState.missing);
    expect(c.step(1, 0), isFalse);
    await c.confirm();
    expect(
      File(p.join(dir, 'box.json')).existsSync(),
      isFalse,
      reason: 'never makes one',
    );
    File(p.join(dir, 'box.json')).writeAsStringSync('{broken');
    await c.reload();
    expect(c.state, BoxState.broken);
    expect(File(p.join(dir, 'box.json')).readAsStringSync(), '{broken');
  });
}
