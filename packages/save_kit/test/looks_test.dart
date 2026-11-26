// A card's colour, sticker and place in the list (ported from the PC's
// CardLooksTests.gd): kept by this app only and following the card into a
// slot. The menu parts (Move card, Customize) live in the app; here are the
// CardLooks calls they make.
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

int rgb(String hex) => 0xFF000000 | int.parse(hex, radix: 16);

void main() {
  late Directory temp;
  late String dir;
  late CardSafety safety;

  MemoryCard card(String path, [String system = 'DC']) => MemoryCard()
    ..system = system
    ..path = path
    ..name = p.basenameWithoutExtension(path);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('card_looks_test');
    dir = p.join(temp.path, 'looks');
    Directory(dir).createSync(recursive: true);
    safety = CardSafety(isApp: false, testRoots: [temp.path]);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('the looks file', () {
    final file = p.join(dir, 'looks.json');
    final a = card(p.join(dir, 'a.bin')), b = card(p.join(dir, 'b.bin'));
    expect(CardLooks.setLook(a, 'b4202f', '', file, safety), '');
    var cards = [card(a.path), card(b.path)];
    CardLooks.apply(cards, file);
    expect(cards[0].color, rgb('b4202f'));
    expect(cards[1].color, 0, reason: 'on that card only');
    expect(
      CardLooks.paletteIndex(cards[0].color, cards[0].finish),
      4,
      reason: 'found in the palette again',
    );
    expect(
      CardLooks.paletteIndex(cards[1].color),
      0,
      reason: "no colour = the console's own",
    );
    expect(CardLooks.setOrder([b, a], file, safety), '', reason: 'an order');
    cards = [card(a.path), card(b.path)];
    CardLooks.apply(cards, file);
    expect((cards[1].orderRank, cards[0].orderRank), (1, 2));
    expect(cards[0].color, isNot(0), reason: 'with the colour still there');

    final inside = card(p.join(dir, 'RetroArch', 'system', 'dc', 'vmu.bin'))
      ..home = a.path;
    CardLooks.apply([inside], file);
    expect(inside.color, rgb('b4202f'));
    expect(
      inside.orderRank,
      2,
      reason: 'a card in a console slot keeps its look and place',
    );

    expect(CardLooks.setLook(a, '2a6fd6/clear', '', file, safety), '');
    cards = [card(a.path)];
    CardLooks.apply(cards, file);
    expect(cards[0].finish, 'clear', reason: 'a crystal colour comes back');
    expect(
      CardLooks.paletteIndex(cards[0].color, cards[0].finish),
      greaterThan(4),
    );
    expect(CardLooks.setLook(a, '', '', file, safety), '');
    expect(
      File(file).readAsStringSync(),
      isNot(contains('2a6fd6')),
      reason: "back to the console's own and no sticker: nothing kept",
    );
    expect(File(file).readAsStringSync(), isNot(contains('b4202f')));

    File(file).writeAsStringSync('{broken');
    expect(
      CardLooks.setLook(a, '1f56c2', '', file, safety),
      CardLooks.unreadable,
    );
    expect(
      File(file).readAsStringSync(),
      '{broken',
      reason: "a damaged looks file isn't written over",
    );
    expect(CardLooks.setOrder([a], file, safety), CardLooks.unreadable);
    final appFile = p.join(temp.parent.path, 'card_looks_not_a_test.json');
    expect(
      CardLooks.setLook(a, '1f56c2', '', appFile, safety),
      CardSafety.refused,
      reason: "a tool can't change the app's looks",
    );
    expect(File(appFile).existsSync(), isFalse);
  });

  test('stickers', () {
    final folder = p.join(dir, 'stickers');
    Directory(folder).createSync(recursive: true);
    final pic = img.Image(width: 400, height: 200)
      ..clear(img.ColorRgb8(255, 165, 0));
    File(p.join(folder, 'Sonic.png')).writeAsBytesSync(img.encodePng(pic));
    File(p.join(dir, 'cover.png')).writeAsBytesSync(img.encodePng(pic));
    File(p.join(folder, 'notes.txt')).writeAsStringSync('not a picture');
    final c = card(p.join(dir, 'c.bin'));
    for (var i = 0; i < 2; i++) {
      c.saves.add(
        CardSave()
          ..system = 'DC'
          ..id = 'SAVE$i'
          ..game = 'Sonic Adventure 2'
          ..gameId = 'dc:sa2'
          ..frames.add(Pixels(32, 32))
          ..card = c,
      );
    }
    final cover = p.join(dir, 'cover.png');
    final got = CardLooks.stickerChoices(c, [
      (id: 'dc:sa2', title: 'Sonic Adventure 2', art: cover, shots: const []),
      (id: 'dc:other', title: 'Not on it', art: cover, shots: const []),
    ], folder);
    expect(
      [for (final g in got) g.label],
      [
        'No sticker',
        'Game art: Sonic Adventure 2',
        'Save icon: Sonic Adventure 2',
        'Your picture: Sonic',
      ],
      reason:
          'none, the art of the game on it (once), its save icon (once), '
          'your own pictures (not other files)',
    );
    final big = CardLooks.stickerImage(got[3].key, c);
    expect(big, isNotNull);
    expect(
      (big!.w, big.h),
      (CardLooks.stickerMax, CardLooks.stickerMax ~/ 2),
      reason: 'a big picture is made sticker-sized, in proportion',
    );
    expect(
      CardLooks.stickerImage(got[2].key, c),
      same(c.saves[0].frames[0]),
      reason: "a save icon sticker is that save's own picture",
    );
    expect(
      CardLooks.stickerImage('file:${p.join(dir, 'gone.png')}', c),
      isNull,
      reason: "a picture that's gone is just no sticker",
    );

    final file = p.join(dir, 'looks.json');
    expect(CardLooks.setLook(c, '', got[3].key, file, safety), '');
    final again = card(c.path);
    CardLooks.apply([again], file);
    expect(again.sticker, got[3].key, reason: 'a sticker is kept');
    expect(again.stickerImage, isNotNull, reason: 'and its picture loaded');
    expect(again.color, 0, reason: "on the console's own colour");
  });

  test('the order comes back next time, a new card goes last', () {
    final file = p.join(dir, 'order.json');
    final names = ['Three', 'Two', 'One'];
    final cards = [
      for (final n in names) card(p.join(dir, '$n.bin')),
      card(p.join(dir, 'Four.ps2'), 'PS2'),
    ];
    expect(CardLooks.setOrder([...cards, cards[0]], file, safety), '');
    final again = [
      for (final n in ['One', 'Two', 'Three']) card(p.join(dir, '$n.bin')),
      card(p.join(dir, 'Four.ps2'), 'PS2'),
      card(p.join(dir, 'New.bin')),
    ];
    CardLooks.apply(again, file);
    expect([for (final c in again) c.orderRank], [3, 2, 1, 4, 0]);
    expect(
      CardLooks.read(file).order,
      hasLength(4),
      reason: 'a card listed twice is kept once',
    );
  });

  test('Customize: the palette', () {
    final c = card(p.join(dir, 'look.bin'));
    expect(CardLooks.palette[0].$1, "Console's own");
    CardLooks.wear(c, CardLooks.palette[1].$2);
    expect(c.color, rgb('1c1d24'));
    expect(CardLooks.palette[1].$1, 'Midnight Black');
    final blue = CardLooks.palette.indexWhere((e) => e.$1 == 'Crystal Blue');
    expect(blue, 13);
    CardLooks.wear(c, CardLooks.palette[blue].$2);
    expect(
      (c.finish, c.color),
      ('clear', rgb('2a6fd6')),
      reason: 'the crystal ones are see-through plastic',
    );
    expect(CardLooks.paletteIndex(c.color, c.finish), blue);
    CardLooks.wear(c, '');
    expect((c.color, c.finish), (0, ''), reason: "back to the console's own");
    for (var i = 1; i < CardLooks.palette.length; i++) {
      final (_, value) = CardLooks.palette[i];
      CardLooks.wear(c, value);
      expect(
        CardLooks.paletteIndex(c.color, c.finish),
        i,
        reason: 'every colour is found again',
      );
      expect(CardLooks.finishes, contains(c.finish));
    }
  });
}
