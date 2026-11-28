// Put in console / Take out (ported from the PC's CardSlotsTests.gd), on
// copies laid out like RetroArch's, PCSX2's, DuckStation's and Dolphin's own
// folders: nothing is ever lost, whatever was in a slot goes back to where
// it came from, and the emulators' settings change only in the lines meant.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/src/formats/dreamcast.dart';
import 'package:save_kit/src/formats/gamecube.dart';
import 'package:save_kit/src/formats/ps1.dart';
import 'package:save_kit/src/formats/ps2.dart';
import 'package:save_kit/src/model.dart';
import 'package:save_kit/src/slots.dart';
import 'package:save_kit/src/store.dart';
import 'package:test/test.dart';

final formats = SlotFormats(
  vmuBlank: VmuWriter.blank,
  vmuCheck: VmuWriter.check,
  vmuSaves: (b) => VmuWriter.saves(b).length,
  ps1Saves: (b) => Ps1Writer.saves(b).length,
  ps2Check: Ps2Writer.check,
  ps2Saves: (b) => Ps2Writer.saveNames(b).length,
  gcCheck: GcWriter.check,
  gcSaves: (b) => GcWriter.saves(b).length,
);

/// A made-up .dci: every body byte = [blocks].
Uint8List dci(String name, int blocks, int type) {
  final b = Uint8List(32 + blocks * 512)
    ..fillRange(32, 32 + blocks * 512, blocks);
  b[0] = type;
  b.setAll(4, name.padRight(12).codeUnits);
  b[0x18] = blocks & 0xFF;
  b[0x19] = blocks >> 8;
  return b;
}

/// A .psu holding files of [sizes], each filled with a counting pattern.
Uint8List psu(String saveName, List<int> sizes) {
  const when = 1795355442;
  final b = BytesBuilder()
    ..add(Ps2Writer.newEntry(0x8427, sizes.length + 2, saveName, when))
    ..add(Ps2Writer.newEntry(0x8427, 0, '.', when))
    ..add(Ps2Writer.newEntry(0x8427, 0, '..', when));
  for (var i = 0; i < sizes.length; i++) {
    final size = sizes[i];
    b.add(Ps2Writer.newEntry(0x8497, size, 'file$i', when));
    final data = Uint8List((size / 1024).ceil() * 1024);
    for (var k = 0; k < size; k++) {
      data[k] = (k + i) & 0xFF;
    }
    b.add(data);
  }
  return b.takeBytes();
}

Uint8List vmuWith(String saveName) {
  final got = VmuWriter.importSave(
    VmuWriter.blank(),
    dci(saveName, 2, VmuWriter.data),
  );
  expect(got.ok, isTrue, reason: got.error);
  return got.data;
}

void put(String path, List<int> bytes) {
  Directory(p.dirname(path)).createSync(recursive: true);
  File(path).writeAsBytesSync(bytes, flush: true);
}

Uint8List bytesOf(String path) => File(path).readAsBytesSync();
String textOf(String path) => File(path).readAsStringSync();

const _systems = {'.bin': 'DC', '.ps2': 'PS2', '.mcd': 'PS1', '.raw': 'GC'};

/// The card in a file, as the reader would make it (null = not a card).
MemoryCard? card(String path) {
  final system = _systems[p.extension(path).toLowerCase()];
  if (system == null || !File(path).existsSync()) return null;
  final c = MemoryCard()
    ..system = system
    ..path = path
    ..name = CardSlots.cardName(p.basenameWithoutExtension(path));
  if (system == 'DC') VmuCard.parse(bytesOf(path), c);
  return c;
}

/// Every card under [dir].
List<MemoryCard> readCards(String dir) => [
  for (final f in Directory(dir).listSync(recursive: true).whereType<File>())
    ?card(f.path),
];

/// '/' everywhere, to compare a path the settings spell with '\'.
String slash(String path) => path.replaceAll(r'\', '/');

void main() {
  late Directory temp;
  late String dir, down, record;
  late CardStore store;
  late CardSlots slots;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('card_slots_test');
    dir = p.join(temp.path, 'slots');
    down = p.join(dir, 'Downloaded Saves', 'Saves from the internet');
    record = p.join(dir, 'card_slots.json');
    Directory(dir).createSync(recursive: true);
    store = CardStore(
      safety: CardSafety(isApp: false, testRoots: [temp.path]),
      root: p.join(dir, 'backups'),
    );
    slots = CardSlots(
      store: store,
      recordFile: record,
      formats: formats,
      raRoot: p.join(dir, 'RetroArch'),
      pcsx2Dir: p.join(dir, 'PCSX2'),
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('settings lines', () {
    const t =
        '[A]\nx = 1\n\n[MemoryCards]\nSlot1_Filename = a.ps2\n\n[B]\ny = 2\n';

    test('are read from their own section', () {
      expect(CardSlots.iniGet(t, 'MemoryCards', 'Slot1_Filename'), 'a.ps2');
      expect(CardSlots.iniGet(t, 'A', 'Slot1_Filename'), '');
    });

    test('a missing line is added inside its section', () {
      expect(
        CardSlots.iniSet(t, 'MemoryCards', 'Slot2_Filename', 'b.ps2'),
        '[A]\nx = 1\n\n[MemoryCards]\nSlot1_Filename = a.ps2\n'
        'Slot2_Filename = b.ps2\n\n[B]\ny = 2\n',
      );
    });

    test('a missing section is added', () {
      final added = CardSlots.iniSet(
        '[A]\nx = 1\n',
        'MemoryCards',
        'Slot1_Enable',
        'true',
      );
      expect(CardSlots.iniGet(added, 'MemoryCards', 'Slot1_Enable'), 'true');
    });
  });

  test('Dreamcast: cards go in by their bytes, nothing is lost', () {
    final dc = p.join(dir, 'RetroArch', 'system', 'dc');
    final a1 = p.join(dc, 'vmu_save_A1.bin');
    final b1 = p.join(dc, 'vmu_save_B1.bin');
    final mineBytes = vmuWith('MINE');
    put(a1, mineBytes);
    put(b1, VmuWriter.blank());
    final boss = p.join(down, 'DC Boss 1.bin');
    final bossBytes = vmuWith('BOSS');
    put(boss, bossBytes);
    final four = slots.slots('DC');
    expect(four.map((s) => s.short), [
      'A1',
      'B1',
      'C1',
      'D1',
    ], reason: 'no Flycast options: VMUs in A1 to D1');
    expect(slots.whyNot('DC'), '');
    expect(slots.whyNot('N64'), isNot(''), reason: 'the others say why not');

    // A downloaded card goes into A1; your own card from A1 is kept in a
    // file of its own.
    expect(slots.putIn('DC:A1', card(boss)), '');
    expect(bytesOf(a1), bossBytes, reason: 'A1 holds that card, byte for byte');
    final mine = p.join(dc, CardSlots.shelf, 'Your card from A1.bin');
    expect(File(mine).existsSync(), isTrue);
    expect(bytesOf(mine), mineBytes, reason: 'your own card is kept');
    expect(store.history(a1).length, 1, reason: 'A1 was backed up first');
    expect(slots.cameFrom('DC:A1'), boss);

    // On screen: A1 carries the card's name, its old copy is left out.
    final cards = readCards(dir);
    final saves = <CardSave>[for (final c in cards) ...c.saves];
    expect(saves.where((s) => s.card!.path == boss), isNotEmpty);
    slots.dress(cards, saves);
    final shown = {for (final c in cards) c.path: c};
    expect(shown.containsKey(boss), isFalse, reason: 'not shown twice');
    expect(shown[a1]!.name, 'DC Boss 1 (A1)');
    expect(shown[a1]!.inSlot, 'IN THE DREAMCAST, A1');
    expect(shown[a1]!.home, boss);
    expect(shown[b1]!.slotOrder, 2, reason: "B1 too, in the console's order");
    expect(
      saves.where((s) => s.card!.path == boss),
      isEmpty,
      reason: "the old copy's saves aren't listed twice",
    );
    final picker = slots.describe('DC');
    expect(picker[0].label, 'Controller 1, slot 1 (A1)');
    expect(picker[0].detail, 'Now: DC Boss 1, 1 save');
    expect(picker[1].detail, 'Now: VMU B1, empty');
    expect(picker[2].detail, 'Empty');

    // The game saves to A1, then your card goes back in: the progress goes
    // home to the downloaded card's file.
    final played = VmuWriter.importSave(
      bytesOf(a1),
      dci('PLAYED', 2, VmuWriter.data),
    ).data;
    put(a1, played);
    expect(slots.putIn('DC:A1', card(mine)), '');
    expect(bytesOf(boss), played, reason: 'what was played went home');
    expect(bytesOf(a1), mineBytes, reason: 'A1 holds your own card again');
    expect(slots.cameFrom('DC:A1'), mine, reason: 'the list follows it');

    // Two slots trade cards.
    final aWas = bytesOf(a1), bWas = bytesOf(b1);
    expect(slots.putIn('DC:B1', card(a1)), '');
    expect(bytesOf(b1), aWas);
    expect(bytesOf(a1), bWas, reason: 'A1 and B1 traded cards');
    expect(slots.cameFrom('DC:B1'), mine);
    expect(slots.cameFrom('DC:A1'), '', reason: 'the list traded with them');
    expect(
      slots.putIn('DC:B1', card(b1)),
      'That card is in B1 already',
      reason: "a card can't go into the slot it's in",
    );

    // Taking it out: back home, an empty card in the slot.
    expect(slots.takeOut('DC:B1'), '');
    expect(bytesOf(mine), mineBytes, reason: 'it went back to its own file');
    expect(VmuWriter.saves(bytesOf(b1)), isEmpty);
    expect(VmuWriter.check(bytesOf(b1)), '', reason: 'an empty, working card');
    expect(slots.cameFrom('DC:B1'), '', reason: 'nothing is listed in it');
    expect(slots.takeOut('DC:B1'), isNot(''), reason: 'an empty slot says so');

    // A slot whose file isn't there yet (Flycast makes them when a game
    // starts).
    expect(slots.putIn('DC:C1', card(boss)), '');
    expect(bytesOf(p.join(dc, 'vmu_save_C1.bin')), played);
    final saved = jsonDecode(textOf(record)) as Map;
    expect(saved, {'DC:C1': boss}, reason: 'the list is kept on disk');

    // A damaged list of slots stops everything.
    put(record, utf8.encode('{not json'));
    expect(slots.putIn('DC:A1', card(boss)), CardSlots.unreadable);
    expect(slots.error, CardSlots.unreadable);
  });

  test("Flycast's options decide which slots hold a VMU", () {
    Directory(
      p.join(dir, 'RetroArch', 'system', 'dc'),
    ).createSync(recursive: true);
    final opt = p.join(dir, 'RetroArch', 'config', 'Flycast', 'Flycast.opt');
    put(
      opt,
      utf8.encode(
        'reicast_device_port1_slot1 = "VMU"\n'
        'reicast_device_port1_slot2 = "VMU"\n'
        'reicast_device_port2_slot1 = "None"\n'
        'reicast_per_content_vmus = "disabled"\n',
      ),
    );
    expect(slots.slots('DC').map((s) => s.short), ['A1', 'A2', 'C1', 'D1']);
    put(opt, utf8.encode('reicast_per_content_vmus = "VMU A1"\n'));
    expect(slots.slots('DC'), isEmpty, reason: 'per-game VMUs: no slots');
    expect(slots.whyNot('DC'), contains('Per-Game'));
  });

  test('PCSX2: cards go in by name, only the lines meant change', () {
    final ini = p.join(dir, 'PCSX2', 'inis', 'PCSX2.ini');
    final mc = p.join(dir, 'PCSX2', 'memcards');
    const text =
        '[UI]\r\nTheme = dark\r\n\r\n[MemoryCards]\r\nSlot1_Enable = true\r\n'
        'Slot1_Filename = Mcd001.ps2\r\nSlot2_Enable = true\r\n'
        'Slot2_Filename = Mcd002.ps2\r\nMultitap1_Slot2_Enable = false\r\n'
        '\r\n[Folders]\r\nCards = memcards\r\n';
    put(ini, utf8.encode(text));
    final blank = Ps2Writer.blank();
    put(p.join(mc, 'Mcd001.ps2'), blank);
    put(p.join(mc, 'Mcd002.ps2'), blank);
    final made = Ps2Writer.importSave(blank, psu('BASLUS-00002B', [964]));
    expect(made.ok, isTrue, reason: made.error);
    final other = made.data;
    put(p.join(mc, 'Other.ps2'), other);
    final outside = p.join(down, 'PS2 Boss 1.ps2');
    put(outside, other);

    final two = slots.slots('PS2');
    expect(two.length, 2);
    expect(two[0].on, isTrue);
    expect(two[1].path, endsWith('Mcd002.ps2'), reason: 'from its settings');
    expect(slots.describe('PS2')[0].detail, 'Now: PS2 Card 1, empty');
    expect(slots.putIn('PS2:2', card(p.join(mc, 'Other.ps2'))), '');
    expect(
      textOf(ini),
      text.replaceFirst(
        'Slot2_Filename = Mcd002.ps2',
        'Slot2_Filename = Other.ps2',
      ),
      reason: 'only that one line changed, Windows line endings kept',
    );
    expect(store.history(ini).length, 1, reason: 'backed up first');
    expect(slots.describe('PS2')[1].detail, 'Now: Other, 1 save');
    expect(slots.putIn('PS2:1', card(p.join(mc, 'Other.ps2'))), '');
    var now = textOf(ini);
    expect(CardSlots.iniGet(now, 'MemoryCards', 'Slot1_Filename'), 'Other.ps2');
    expect(
      CardSlots.iniGet(now, 'MemoryCards', 'Slot2_Filename'),
      'Mcd001.ps2',
      reason: 'the two slots traded: one card is never in both',
    );
    expect(
      slots.putIn('PS2:1', card(p.join(mc, 'Other.ps2'))),
      'That card is in Slot 1 already',
    );

    expect(slots.putIn('PS2:2', card(outside)), '');
    final copied = p.join(mc, 'PS2 Boss 1.ps2');
    expect(bytesOf(copied), other, reason: "copied into PCSX2's folder");
    expect(bytesOf(outside), other, reason: 'the download stays as it was');
    expect(
      CardSlots.iniGet(textOf(ini), 'MemoryCards', 'Slot2_Filename'),
      'PS2 Boss 1.ps2',
      reason: 'slot 2 names the copy',
    );
    final cards = readCards(dir);
    slots.dress(cards, []);
    final tagged = cards.where((c) => c.inSlot.isNotEmpty).toList();
    expect(tagged.length, 2, reason: "the two cards in PCSX2's slots");
    expect(tagged.map((c) => c.inSlot).toSet(), {
      'IN PCSX2 SLOT 1',
      'IN PCSX2 SLOT 2',
    });

    expect(slots.takeOut('PS2:2'), '');
    expect(
      CardSlots.iniGet(textOf(ini), 'MemoryCards', 'Slot2_Enable'),
      'false',
      reason: 'taking out switches slot 2 off',
    );
    expect(slots.describe('PS2')[1].detail, startsWith('Switched off'));
    expect(slots.takeOut('PS2:2'), isNot(''), reason: 'an empty slot says so');
    expect(slots.putIn('PS2:2', card(copied)), '');
    expect(
      CardSlots.iniGet(textOf(ini), 'MemoryCards', 'Slot2_Enable'),
      'true',
      reason: 'putting a card in switches it back on',
    );
  });

  test("a PC copy (read-only) doesn't go in a slot", () {
    final copies = p.join(dir, 'XMB Frontend', 'Saves', 'PCSX2');
    final locked = CardSlots(
      store: CardStore(
        safety: CardSafety(
          isApp: false,
          testRoots: [temp.path],
          readOnly: [copies],
        ),
        root: p.join(dir, 'backups'),
      ),
      recordFile: record,
      formats: formats,
      raRoot: p.join(dir, 'RetroArch'),
      pcsx2Dir: p.join(dir, 'PCSX2'),
    );
    final ini = p.join(dir, 'PCSX2', 'inis', 'PCSX2.ini');
    const text =
        '[MemoryCards]\r\nSlot1_Enable = true\r\nSlot1_Filename = Mcd001.ps2\r\n';
    put(ini, utf8.encode(text));
    put(p.join(dir, 'PCSX2', 'memcards', 'Mcd001.ps2'), Ps2Writer.blank());
    final pc = p.join(copies, 'memcards', 'Mcd001.ps2');
    put(pc, Ps2Writer.blank());
    expect(locked.putIn('PS2:1', card(pc)), CardSafety.readOnlyNotice);
    expect(textOf(ini), text);
    expect(
      Directory(p.join(dir, 'PCSX2', 'memcards')).listSync().length,
      1,
      reason: 'nothing copied in',
    );
  });

  // PS1 through DuckStation: a card goes in by switching that slot to
  // Shared and naming the card's file, so every game uses it; taking it out
  // sets the slot to None. Only the lines meant change.
  test('DuckStation: Shared cards by path', () {
    slots = CardSlots(
      store: store,
      recordFile: record,
      formats: formats,
      duckDir: p.join(dir, 'DuckStation'),
      windowsPaths: true,
    );
    final ini = p.join(dir, 'DuckStation', 'settings.ini');
    const text =
        '[Main]\nSettingsVersion = 3\n\n[MemoryCards]\n'
        'Card1Type = PerGameTitle\nCard2Type = None\nCard3Type = None\n'
        'UsePlaylistTitle = true\n\n[Display]\nScale = 4\n';
    put(ini, utf8.encode(text));
    final a = p.join(down, 'PS1 Boss 1.mcd');
    final b = p.join(down, 'PS1 More 1.mcd');
    put(a, Ps1Writer.blank());
    put(b, Ps1Writer.blank());
    final odd = p.join(down, 'PS1 Odd.mcd');
    put(odd, Ps1Writer.blank().sublist(0, 8192));
    final two = slots.slots('PS1');
    expect(two.length, 2);
    expect(two[0].on || two[1].on, isFalse, reason: 'neither shared yet');
    expect(slots.whyNot('PS1'), '');
    expect(
      two[0].path,
      p.join(dir, 'DuckStation', 'memcards', 'shared_card_1.mcd'),
    );
    expect(
      slots.describe('PS1')[0].detail,
      startsWith('Each game keeps its own card'),
    );
    expect(slots.putIn('PS1:1', card(a)), '');
    var now = textOf(ini);
    final named = CardSlots.iniGet(now, 'MemoryCards', 'Card1Path');
    expect(CardSlots.iniGet(now, 'MemoryCards', 'Card1Type'), 'Shared');
    expect(named, isNot(contains('/')), reason: "Windows spells it with '\\'");
    expect(slash(named), slash(a), reason: 'slot 1 names that card');
    expect(now, contains('Scale = 4\n'));
    expect(now, contains('UsePlaylistTitle = true\n'));
    expect(
      now,
      contains('Card3Type = None\n'),
      reason: 'every other line stays as it was, line endings too',
    );
    expect(slots.describe('PS1')[0].detail, 'Now: PS1 Boss 1, empty');
    final cards = [card(a)!, card(b)!];
    slots.dress(cards, []);
    expect(cards[0].inSlot, 'IN DUCKSTATION SLOT 1');
    expect(cards[1].inSlot, '');
    expect(slots.putIn('PS1:1', card(a)), startsWith('That card is in'));
    expect(slots.putIn('PS1:2', card(a)), '', reason: 'moving it to slot 2');
    now = textOf(ini);
    expect(CardSlots.iniGet(now, 'MemoryCards', 'Card2Type'), 'Shared');
    expect(
      CardSlots.iniGet(now, 'MemoryCards', 'Card1Type'),
      'None',
      reason: 'slot 1 has nothing (it held nothing shared before)',
    );
    expect(slots.putIn('PS1:1', card(b)), '');
    expect(slots.takeOut('PS1:1'), '', reason: 'another card in, then out');
    now = textOf(ini);
    expect(CardSlots.iniGet(now, 'MemoryCards', 'Card1Type'), 'None');
    expect(bytesOf(b), Ps1Writer.blank(), reason: 'the card itself untouched');
    expect(slots.takeOut('PS1:1'), endsWith('already'));
    expect(
      slots.putIn('PS1:1', card(odd)),
      isNot(''),
      reason: "a card that isn't 128 KB doesn't go in",
    );
    expect(slots.putIn('PS1:1', null), isNot(''), reason: 'nothing chosen');
  });

  test('DuckStation on Linux / Android keeps "/" in its paths', () {
    slots = CardSlots(
      store: store,
      recordFile: record,
      formats: formats,
      duckDir: p.join(dir, 'DuckStation'),
      windowsPaths: false,
    );
    final ini = p.join(dir, 'DuckStation', 'settings.ini');
    put(ini, utf8.encode('[Folders]\nMemoryCards = cards\n[MemoryCards]\n'));
    final a = p.join(dir, 'DuckStation', 'cards', 'mine.mcd');
    put(a, Ps1Writer.blank());
    expect(
      slots.slots('PS1')[1].path,
      p.join(p.dirname(a), 'shared_card_2.mcd'),
    );
    expect(slots.putIn('PS1:2', card(a)), '');
    final now = textOf(ini);
    expect(CardSlots.iniGet(now, 'MemoryCards', 'Card2Path'), a);
    expect(slots.slots('PS1')[1].on, isTrue);
  });

  // GameCube through Dolphin: SlotA / SlotB 1 = a card file (MemcardAPath /
  // MemcardBPath), 255 = nothing.
  test('Dolphin: card files in slots A and B', () {
    slots = CardSlots(
      store: store,
      recordFile: record,
      formats: formats,
      dolphinDir: p.join(dir, 'Dolphin'),
      windowsPaths: true,
    );
    put(p.join(dir, 'Dolphin', 'portable.txt'), []);
    final ini = p.join(dir, 'Dolphin', 'User', 'Config', 'Dolphin.ini');
    expect(slots.dolphinIni(), ini, reason: 'portable: next to the exe');
    put(
      ini,
      utf8.encode(
        '[General]\nISOPath0 = x\n[Core]\nSlotA = 8\nSlotB = 255\n'
        'CPUThread = True\n',
      ),
    );
    final a = p.join(down, 'GC Done 1.raw');
    final b = p.join(down, 'GC More 1.raw');
    put(a, GcWriter.blank());
    put(b, GcWriter.blank());
    final two = slots.slots('GC');
    expect(two.length, 2);
    expect(two[0].on || two[1].on, isFalse, reason: 'no card file yet');
    expect(slots.whyNot('GC'), '');
    expect(
      two[1].path,
      p.join(dir, 'Dolphin', 'User', 'GC', 'MemoryCardB.USA.raw'),
    );
    expect(
      slots.describe('GC')[0].detail,
      startsWith('Dolphin keeps a folder'),
    );
    expect(slots.putIn('GC:A', card(a)), '');
    var now = textOf(ini);
    expect(CardSlots.iniGet(now, 'Core', 'SlotA'), '1');
    expect(slash(CardSlots.iniGet(now, 'Core', 'MemcardAPath')), slash(a));
    expect(now, contains('CPUThread = True\n'));
    expect(now, contains('ISOPath0 = x\n'), reason: 'other lines stay');
    final cards = [card(a)!, card(b)!];
    slots.dress(cards, []);
    expect(cards[0].inSlot, 'IN DOLPHIN SLOT A');
    expect(slots.putIn('GC:B', card(a)), '', reason: 'moved to slot B');
    now = textOf(ini);
    expect(CardSlots.iniGet(now, 'Core', 'SlotB'), '1');
    expect(CardSlots.iniGet(now, 'Core', 'SlotA'), '255', reason: 'A empty');
    expect(slots.takeOut('GC:B'), '');
    expect(CardSlots.iniGet(textOf(ini), 'Core', 'SlotB'), '255');
    expect(
      slots.putIn('GC:A', card(p.join(dir, 'Dolphin', 'portable.txt'))),
      isNot(''),
      reason: "something that isn't a card doesn't go in",
    );
    final odd = p.join(down, 'GC Odd.raw');
    put(odd, Uint8List(8192));
    expect(
      slots.putIn('GC:A', card(odd)),
      "That card can't go in: it isn't a whole, working GameCube card",
    );
  });

  test(
    'a Dolphin that is not portable keeps its settings in its user folder',
    () {
      final user = p.join(dir, 'Dolphin Emulator');
      slots = CardSlots(
        store: store,
        recordFile: record,
        formats: formats,
        dolphinDir: p.join(dir, 'Dolphin'),
        dolphinUser: user,
      );
      expect(slots.dolphinIni(), p.join(user, 'Config', 'Dolphin.ini'));
      expect(slots.whyNot('GC'), contains("Dolphin's settings weren't found"));
    },
  );

  test('refusals', () {
    final dc = p.join(dir, 'RetroArch', 'system', 'dc');
    final a1 = p.join(dc, 'vmu_save_A1.bin');
    put(a1, VmuWriter.blank());
    put(p.join(dir, 'x.ps2'), Ps2Writer.blank());
    expect(
      slots.putIn('DC:A1', card(p.join(dir, 'x.ps2'))),
      'Only a Dreamcast card goes in there',
      reason: "a PS2 card can't go into a Dreamcast slot",
    );
    expect(slots.putIn('DC:Z9', card(a1)), "That slot isn't there any more");
    expect(slots.takeOut('DC:A1'), 'A1 has an empty card in it already');
    expect(slots.whyNot('PS2'), contains("PCSX2's settings weren't found"));
    expect(slots.whyNot('PS1'), contains("DuckStation's settings"));
    final reader = CardSlots(
      store: null,
      recordFile: record,
      formats: formats,
      raRoot: p.join(dir, 'RetroArch'),
    );
    expect(
      reader.putIn('DC:A1', card(a1)),
      isNot(''),
      reason: "the one made for reading can't move anything",
    );
    // Not the app, keeping its list outside the test copies: the safety
    // gate says no.
    final real = CardStore(
      safety: CardSafety(isApp: false),
      root: p.join(dir, 'backups'),
    );
    final wild = CardSlots(
      store: real,
      recordFile: p.join(Directory.systemTemp.path, 'card_slots.json'),
      formats: formats,
      raRoot: p.join(dir, 'RetroArch'),
    );
    expect(wild.putIn('DC:A1', card(a1)), CardSafety.refused);
    expect(wild.takeOut('DC:A1'), CardSafety.refused);
  });

  test('file names', () {
    expect(CardSlots.fileSafe('PS2: Boss/1?'), 'PS2_ Boss_1_');
    expect(CardSlots.fileSafe('con'), 'save con');
    expect(CardSlots.fileSafe(''), 'save ');
    expect(CardSlots.cardName('Mcd001'), 'PS2 Card 1');
    expect(CardSlots.cardName('vmu_save_b2'), 'VMU B2');
    expect(CardSlots.cardName('MemoryCardA.USA'), 'GC Card A (USA)');
    expect(CardSlots.cardName('Boss (USA)_1'), 'Boss');
    final base = p.join(dir, 'card');
    expect(CardSlots.freePath(base, 'ps2'), '$base.ps2');
    put('$base.ps2', [1]);
    expect(CardSlots.freePath(base, 'ps2'), '$base 2.ps2');
  });
}
