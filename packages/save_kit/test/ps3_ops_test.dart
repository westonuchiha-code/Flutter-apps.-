// PS3 saves in the Save Manager (the CardOps parts of the PC's
// Ps3SaveTests.gd): a fake RPCS3 folder in a test area, read by the menu's
// own reader, copied to the USB stick, deleted, brought back and exported,
// all through CardOps.
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

import 'ops_test.dart' show bytesOf, opsIn, put;
import 'ps3_test.dart' show sfo;

const saveId = 'BCES00052_SAVE_1';

/// Left half orange, right half blue.
Uint8List icon() {
  final im = img.Image(width: 320, height: 176)
    ..clear(img.ColorRgb8(51, 153, 230));
  img.fillRect(
    im,
    x1: 0,
    y1: 0,
    x2: 159,
    y2: 175,
    color: img.ColorRgb8(230, 102, 26),
  );
  return img.encodePng(im);
}

void makeSave(String dir, int gameBytes) {
  final game = Uint8List(gameBytes);
  for (var i = 0; i < gameBytes; i++) {
    game[i] = i * 7 & 0xFF;
  }
  put(
    p.join(dir, 'PARAM.SFO'),
    sfo({
      'TITLE': 'Ratchet & Clank® Future™',
      'SUB_TITLE': 'Planet Kortog',
      'DETAIL': '',
      'SAVEDATA_DIRECTORY': p.basename(dir),
    }),
  );
  put(p.join(dir, 'ICON0.PNG'), icon());
  put(p.join(dir, 'GAME.SAV'), game);
}

void main() {
  late Directory temp;
  late String dir;
  late CardSafety safety;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ps3_ops_test');
    dir = p.join(temp.path, 'ps3');
    safety = CardSafety(isApp: false, testRoots: [temp.path]);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('the reader matches a save to the installed game', () {
    final home = p.join(dir, 'rpcs3', 'dev_hdd0', 'home');
    makeSave(p.join(home, '00000001', 'savedata', saveId), 3000);
    final r = MemoryCards.readAll(
      [home],
      games: [
        (
          id: 'console:ps3:bces00052',
          title: 'Ratchet & Clank: ToD',
          system: 'PS3',
          serial: 'BCES00052',
        ),
      ],
    );
    expect(r.cards, hasLength(1));
    final card = r.cards[0];
    expect(card.system, 'PS3');
    expect(card.isFolder, isTrue);
    expect(card.name, 'PS3 User 1', reason: "one user's savedata is a card");
    final s = card.saves.single;
    expect(s.id, saveId);
    expect(s.gameId, 'console:ps3:bces00052');
    expect(s.game, 'Ratchet & Clank: ToD');
    expect(s.sizeText(), endsWith('KB'));
    final f = s.frames.single;
    expect((f.w, f.h), (Ps3Card.tile, Ps3Card.tile));
    final at = ((Ps3Card.tile ~/ 2) * f.w + Ps3Card.tile ~/ 4) * 4;
    expect(
      f.rgba[at] > 178 && f.rgba[at + 2] < 77,
      isTrue,
      reason: 'the whole picture is in the square, not cropped',
    );
  });

  test('copy to USB, delete, undelete, export, move back', () {
    final root = p.join(dir, 'ops', 'rpcs3');
    final savedata = p.join(root, 'dev_hdd0', 'home', '00000001', 'savedata');
    makeSave(p.join(savedata, saveId), 5000);
    final opsDir = p.join(dir, 'ops');
    final ops = opsIn(opsDir, safety);
    final hdd = MemoryCards.readCards([p.join(root, 'dev_hdd0', 'home')])[0];
    expect(ops.newCard(hdd).ok, isTrue);
    expect(
      Directory(p.join(root, Ps3Card.usbSaves)).existsSync(),
      isTrue,
      reason: "New card makes RPCS3's USB stick",
    );
    expect(ops.newCard(hdd).ok, isFalse, reason: 'only once');
    final usb = MemoryCards.readCards([p.join(root, Ps3Card.usbSaves)])[0];
    expect(usb.system, 'PS3');
    expect(usb.name, 'PS3 USB');
    expect(usb.saves, isEmpty, reason: 'an empty USB stick is a card');

    final ids = [saveId];
    final copied = ops.copySaves(hdd, ids, usb);
    final there = p.join(root, Ps3Card.usbSaves, saveId);
    expect(copied.ok, isTrue, reason: copied.text);
    expect(
      bytesOf(p.join(there, 'GAME.SAV')),
      bytesOf(p.join(savedata, saveId, 'GAME.SAV')),
      reason: 'copy to USB: same bytes',
    );
    final again = ops.copySaves(hdd, ids, usb);
    expect(again.ok, isFalse);
    expect(again.conflicts, ids, reason: 'copying again asks first');
    expect(ops.checkCard(usb).ok, isTrue, reason: 'the copy checks out');

    final gone = ops.deleteSaves(hdd, ids);
    expect(gone.ok, isTrue, reason: gone.text);
    expect(
      Directory(p.join(savedata, saveId)).existsSync(),
      isFalse,
      reason: 'delete takes the whole folder',
    );
    final lost = ops.lostSaves(hdd);
    expect(lost, hasLength(1));
    final back = ops.undelete(hdd, lost[0]);
    expect(back.ok, isTrue, reason: 'undelete finds it (${back.text})');
    expect(
      bytesOf(p.join(savedata, saveId, 'GAME.SAV')).length,
      5000,
      reason: "it's whole again",
    );

    final out = ops.exportSaves(hdd, ids);
    final zips = Directory(p.join(opsDir, 'exports')).listSync();
    expect(out.ok, isTrue, reason: out.text);
    expect(zips, hasLength(1));
    expect(zips[0].path, endsWith('.zip'), reason: 'export writes a .zip');
    final imported = ops.importFile(usb, zips[0].path, replace: true);
    expect(imported.ok, isTrue, reason: 'the .zip imports (${imported.text})');

    final moved = ops.copySaves(usb, ids, hdd, replace: true, move: true);
    expect(moved.ok, isTrue, reason: moved.text);
    expect(
      Directory(there).existsSync(),
      isFalse,
      reason: 'move back with replace: USB copy gone',
    );
  });

  test('nothing changes while RPCS3 runs', () {
    expect(
      CardOwners.reason(
        'C:/Emulators/RPCS3/dev_hdd0/home/00000001/savedata/X/PARAM.SFO',
        ['rpcs3.exe'],
      ),
      isNot(''),
    );
    final root = p.join(dir, 'busy', 'RPCS3');
    final savedata = p.join(root, 'dev_hdd0', 'home', '00000001', 'savedata');
    makeSave(p.join(savedata, saveId), 100);
    final busy = opsIn(
      p.join(dir, 'busy'),
      safety,
      running: () => ['rpcs3.exe'],
    );
    final hdd = MemoryCards.readCards([p.join(root, 'dev_hdd0', 'home')])[0];
    final r = busy.deleteSaves(hdd, [saveId]);
    expect(r.ok, isFalse);
    expect(r.text, contains('RPCS3'));
    expect(Directory(p.join(savedata, saveId)).listSync(), hasLength(3));
  });
}
