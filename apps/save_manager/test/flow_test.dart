// The screens between a button and its result (ported from the PC's
// CardFlowTests.gd): safe answers first, second presses, and jobs that
// really run, on copies in a temp folder registered as a test root.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:save_manager/src/flow.dart';
import 'package:save_manager/src/state.dart';

import 'fixtures.dart';

void main() {
  late Directory temp;
  late String dir;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('save_manager_flow');
    dir = temp.path;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  CardOpsConfig opsConfig({SlotsConfig? slots}) => CardOpsConfig(
    isApp: false,
    testRoots: [dir],
    backupRoot: p.join(dir, 'backups'),
    exportDir: p.join(dir, 'exports'),
    slots: slots,
    askSystem: false,
    running: const ['test-runner'], // no emulator among them
  );

  test('questions: delete, delete all, favorites, format, card verbs', () {
    final cards = fakeCards();
    final f = MemoryCardFlow();
    final one = [cards[0].saves[0]];
    expect(f.begin('delete', cards, one, one[0]), isNull);
    expect(f.kind, FlowKind.ask, reason: 'delete asks');
    expect(f.items[f.index].label, 'KEEP IT');
    expect(f.subject, same(one[0]));
    expect(f.confirm(), isNull);
    expect(f.isOpen(), isFalse, reason: 'Keep it does nothing');
    f
      ..begin('delete_all', cards, one, one[0])
      ..step(1, 0);
    expect(f.confirm(), isNull);
    expect(f.isOpen(), isTrue);
    expect(f.index, 0, reason: 'delete all asks twice, safe answer first');
    f.step(1, 0);
    final job = f.confirm();
    expect(job?.verb, 'delete');
    expect(f.kind, FlowKind.working);
    expect(f.cancel(), isFalse, reason: "a job under way can't be left");
    f.close();
    one[0].favorite = true;
    f.begin('delete', cards, one, one[0]);
    expect(f.items.length, 1);
    expect(f.confirm(), isNull);
    expect(f.isOpen(), isFalse, reason: 'Delete on a favorite only explains');
    f.begin('delete_all', cards, one, one[0]);
    expect(
      f.items[1].job!.groups[0].ids,
      isNot(contains(one[0].id)),
      reason: 'Delete all leaves favorites',
    );
    f.close();
    one[0].favorite = false;
    f.begin('format', cards, one, cards[1].saves[0]);
    expect(f.kind, FlowKind.pick);
    expect(f.index, 1, reason: "card verbs start on that save's card");
    f.confirm();
    expect(f.kind, FlowKind.ask);
    expect(f.items[f.index].label, 'KEEP IT');
    expect(f.cancel(), isTrue);
    expect(f.isOpen(), isFalse);
    f.begin('check', cards, [], null);
    expect(f.kind, FlowKind.pick);
    expect(f.items.length, 2, reason: 'card verbs work with no save');
    f.begin('delete_card', cards, [], null, cards[0]);
    expect(f.title, 'DELETE THIS CARD?');
    f.step(1, 0);
    f.confirm();
    expect(f.title, 'REALLY DELETE IT AND ITS SAVES?');
    expect(f.items[1].label, 'DELETE CARD');
  });

  test('the copy screen', () {
    final cards = fakeCards();
    final f = MemoryCardFlow();
    final s = cards[0].saves[1]..copyProtected = true;
    f.begin('copy', cards, [s], s);
    expect(f.kind, FlowKind.copy);
    expect(f.target(), same(cards[1]));
    expect(f.confirm(), isNull);
    expect(f.message, isNotEmpty, reason: 'copy-protected warns first');
    final job = f.confirm();
    expect(job?.verb, 'copy');
    expect(job!.groups[0].ids, [s.id], reason: 'goes on the second press');
    f.close();
    final free = cards[0].saves[0];
    f.begin('move', cards, [free], free);
    expect(f.button, 2);
    expect(f.confirm()?.move, isTrue, reason: 'Move is highlighted');
    f.close();
    f.begin('copy', cards, [free, cards[1].saves[0]], free);
    expect(f.kind, FlowKind.copy);
    expect(f.source, isNull);
    expect(f.arriving().length, 1, reason: "what's there already stays");
    f.close();
    final ps1 = fakeCards('PS1');
    f.begin('copy', [...cards, ...ps1], [free, ps1[0].saves[0]], free);
    expect(f.kind, FlowKind.ask, reason: 'two consoles at once explains');
    f.begin('copy', [cards[0]], [free], free);
    expect(f.items.length, 2);
    expect(f.items[1].job!.verb, 'new_card', reason: 'offers a new card');
    // the d-pad on the copy screen
    f.begin('copy', cards, [free], free);
    expect(f.step(-1, 0), isTrue);
    expect(f.inButtons, isFalse);
    expect(f.mark(), isTrue);
    expect(f.markedSaves(), isEmpty);
    expect(f.step(1, 0), isTrue);
    expect(f.cell, 1);
    expect(f.step(0, 1), isTrue);
    expect(f.cell, 3);
    expect(f.step(1, 0), isTrue);
    expect(f.inButtons, isTrue, reason: 'off the end: the buttons');
    f
      ..step(0, 1) // COPY ALL
      ..confirm();
    expect(f.markedSaves().length, 4);
    expect(f.turnPage(1), isFalse, reason: 'only one target');
  });

  test('to the disk: copy, then a same-named one asks first', () {
    final withSave = Ps1Writer.importSave(
      Ps1Writer.blank(),
      mcs('BASLUS-00001A', 1, 3),
    ).data;
    put(p.join(dir, 'a.mcd'), withSave);
    put(p.join(dir, 'b.mcd'), Ps1Writer.blank());
    final ops = opsConfig().build();
    final cards = [
      ...MemoryCards.readFile(p.join(dir, 'a.mcd')),
      ...MemoryCards.readFile(p.join(dir, 'b.mcd')),
    ];
    final f = MemoryCardFlow();
    final s = cards[0].saves[0];
    f.begin('copy', cards, [s], s);
    var said = f.finish(MemoryCardFlow.perform(ops, f.confirm()!), 0);
    expect(said, startsWith('Copied'));
    expect(f.isOpen(), isFalse);
    f.begin('copy', cards, [s], s);
    said = f.finish(MemoryCardFlow.perform(ops, f.confirm()!), 0);
    expect(said, '');
    expect(f.kind, FlowKind.ask);
    expect(f.index, 0, reason: 'a same-named save asks first');
    f.step(1, 0);
    said = f.finish(
      performJob((opsConfig(), f.confirm()!)),
      0,
    ); // through the isolate entry point
    expect(said, startsWith('Copied'), reason: 'Replace replaces');
    // the history of that save, then Restore asks
    final onB = MemoryCards.readFile(p.join(dir, 'b.mcd')).first.saves.first;
    f.begin('restore', cards, [onB], onB);
    said = f.finish(MemoryCardFlow.perform(ops, f.workingJob!), 0);
    expect(f.kind, FlowKind.pick, reason: said);
    expect(f.title, "This save's history");
    f.confirm();
    expect(f.title, 'RESTORE THIS BACKUP?');
  });

  test('empty and unformatted cards show, are reachable and formattable', () {
    for (final folder in [MemoryCards.downloads, MemoryCards.downloadsWas]) {
      final sample = MemoryCard()
        ..name = 'PS2 Boss 1'
        ..path =
            'C:/Users/x/Documents/$folder/Saves from the internet/PS2 Boss 1.ps2';
      expect(MemoryCards.isDownload(sample), isTrue);
      expect(sample.isTest(), isFalse);
      sample.name = 'TEST N64 1';
      expect(sample.isTest(), isTrue);
    }
    final full = Ps2Writer.importSave(
      Ps2Writer.blank(),
      psu('BASLUS-00001A', [964]),
    ).data;
    put(p.join(dir, 'Mcd001.ps2'), full);
    put(p.join(dir, 'Mcd002.ps2'), List.filled(full.length, 0xFF));
    put(p.join(dir, 'New PS2 card.ps2'), Ps2Writer.blank());
    final r = MemoryCards.readAll([dir]);
    final st = MemoryCardState()..setData(r.cards, r.saves);
    expect(st.column().length, 3);
    expect(st.step(-1, 0), isTrue);
    expect(st.cardI, greaterThanOrEqualTo(0));
    final reached = <String>{};
    for (var i = 0; i < 3; i++) {
      st.cardI = i;
      reached.add(st.focusedCard()!.name);
    }
    expect(reached.length, 3, reason: 'every card can be stood on');
    expect(st.confirm(), '');
    expect(st.mode, Mode.card);
    expect(st.toggleOptions(), isTrue);
    expect(st.flatOptions()[st.option].verb, 'customize');
    expect(st.optCard, same(st.focusedCard()));
    final blank = r.cards.where((c) => c.unformatted).firstOrNull;
    expect(blank?.freeText(), 'Not formatted');
    final f = MemoryCardFlow()..begin('format', r.cards, [], null, blank);
    expect(f.kind, FlowKind.ask);
    expect(f.items[f.index].label, 'KEEP IT');
    expect(f.items[1].job!.card, same(blank));
    final did = opsConfig().build().formatCard(blank!);
    expect(did.ok, isTrue, reason: did.text);
    expect(Ps2Writer.check(File(blank.path).readAsBytesSync()), '');
  });

  test('ten saves from three cards: moved together, deleted together', () {
    for (var k = 0; k < 4; k++) {
      var d = Ps1Writer.blank();
      if (k < 3) {
        for (var i = 0; i < 6; i++) {
          d = Ps1Writer.importSave(
            d,
            mcs('BASLUS-0000$k$i', 1, k * 10 + i),
          ).data;
        }
      }
      put(p.join(dir, 'card$k.mcd'), d);
    }
    final r = MemoryCards.readAll([dir]);
    final empty = r.cards.where((c) => c.saves.isEmpty).firstOrNull;
    expect(empty, isNotNull);
    expect(r.saves.length, 18);
    final st = MemoryCardState()
      ..setData(r.cards, r.saves)
      ..startSelecting();
    final taken = <String, int>{};
    for (var i = 0; i < st.saves.length; i++) {
      final s = st.saves[i];
      final n = taken[s.card!.key()] ?? 0;
      if (n < 4 && st.marks.length < 10) {
        st
          ..index = i
          ..confirm(); // A
        taken[s.card!.key()] = n + 1;
      }
    }
    expect(st.marks.length, 10);
    expect(taken.length, 3);
    expect(st.mode, Mode.list);
    st.toggleOptions(); // Y
    expect(st.flatOptions()[st.option].verb, 'copy');
    expect(st.groups[0].heading, 'THE 10 SELECTED');
    expect(st.actionLabel('Copy', 'copy'), 'Copy 10 selected');
    final f = MemoryCardFlow()
      ..begin('move', r.cards, st.chosen(), st.current());
    expect(f.kind, FlowKind.copy);
    expect(f.target()!.free, greaterThanOrEqualTo(10));
    final ops = opsConfig().build();
    var said = f.finish(MemoryCardFlow.perform(ops, f.confirm()!), 0);
    final there = ops.openCard(empty!).card;
    var left = 0;
    for (final c in r.cards) {
      if (c != empty) left += ops.openCard(c).card.saves.length;
    }
    expect(there.saves.length, 10, reason: said);
    expect(left, 8);
    f
      ..begin('delete', r.cards, there.saves.sublist(0, 5), there.saves[0])
      ..step(1, 0)
      ..confirm()
      ..step(1, 0);
    said = f.finish(MemoryCardFlow.perform(ops, f.confirm()!), 0);
    expect(ops.openCard(empty).card.saves.length, 5, reason: said);
  });

  test('into the console and out again', () {
    final dc = p.join(dir, 'RetroArch', 'system', 'dc');
    final a1 = p.join(dc, 'vmu_save_A1.bin');
    final boss = p.join(dir, 'Downloaded Saves', 'DC Boss.bin');
    final bossBytes = VmuWriter.importSave(
      VmuWriter.blank(),
      dci('BOSS', 2, VmuWriter.data),
    ).data;
    put(a1, VmuWriter.blank());
    put(boss, bossBytes);
    put(p.join(dir, 'x.ps1'), Ps1Writer.blank());
    final slots = SlotsConfig(
      recordFile: p.join(dir, 'card_slots.json'),
      raRoot: p.join(dir, 'RetroArch'),
    );
    final config = opsConfig(slots: slots);
    final ops = config.build();
    final cards = MemoryCards.readCards([dir]);
    final bossCard = cards.firstWhere((c) => c.path == boss);
    final f = MemoryCardFlow()..begin('slot_in', cards, [], null);
    final systems = {for (final it in f.items) it.card!.system};
    expect(f.kind, FlowKind.pick);
    expect(systems, contains('DC'));
    expect(systems.every(CardSlots.systems.contains), isTrue);
    var job = f.begin('slot_in', cards, [], null, bossCard);
    expect(job?.verb, 'slot_list');
    expect(job!.card, same(bossCard), reason: 'straight to the slots');
    f.finish(MemoryCardFlow.perform(ops, job), 0);
    expect(f.kind, FlowKind.pick);
    expect(f.items.length, 4);
    expect(f.items[0].detail, startsWith('Now: VMU A1'));
    expect(f.lines, contains(MemoryCardFlow.slotNote));
    job = f.confirm();
    var said = f.finish(performJob((config, job!)), 0);
    expect(File(a1).readAsBytesSync(), bossBytes);
    expect(said, startsWith('DC Boss is in Controller 1, slot 1'));
    f.begin('slot_out', cards, [], null);
    f.finish(MemoryCardFlow.perform(ops, f.workingJob!), 0);
    expect(f.kind, FlowKind.pick);
    expect(f.items[0].label, contains('Dreamcast'));
    said = f.finish(MemoryCardFlow.perform(ops, f.confirm()!), 0);
    expect(VmuWriter.saves(File(a1).readAsBytesSync()), isEmpty);
    expect(File(boss).readAsBytesSync(), bossBytes);
    expect(said, startsWith('Taken out'));
  });

  test('customize: colour and sticker show at once, B puts them back', () {
    final card = fakeCards()[0];
    final f = MemoryCardFlow()
      ..openLook(card, const [
        (key: '', label: 'No sticker'),
        (key: 'icon:x', label: 'Save icon: x'),
      ]);
    expect(f.colorName(), "Console's own");
    expect(f.step(1, 0), isTrue);
    expect(card.color, isNot(0));
    f.step(0, 1);
    expect(f.step(1, 0), isTrue);
    expect(card.sticker, 'icon:x');
    expect(f.cancel(), isTrue);
    expect(card.color, 0);
    expect(card.sticker, '');
    f.openLook(card, const [(key: '', label: 'No sticker')]);
    f.step(1, 0);
    f.confirm(); // on to the sticker
    f.confirm(); // on to the name
    expect(f.lookRow, 2);
    f.selectLookRow(3); // DONE
    final job = f.confirm();
    expect(job?.verb, 'save_look');
    expect(job!.color, CardLooks.palette[1].$2);
    expect(job.rename, isFalse);
    expect(f.isOpen(), isFalse);
  });

  test('import list: newest first, the console\'s own files', () {
    put(p.join(dir, 'in', 'a.mcs'), [1]);
    put(p.join(dir, 'in', 'b.txt'), [1]);
    final got = MemoryCardFlow.importList('PS1', [
      p.join(dir, 'in'),
      p.join(dir, 'missing'),
    ]);
    expect(got.map((e) => p.basename(e.file)), ['a.mcs']);
  });
}
