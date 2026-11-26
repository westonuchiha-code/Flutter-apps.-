import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/src/prefs.dart';
import 'package:save_kit/src/store.dart';
import 'package:test/test.dart';

String fine(Uint8List _) => '';

void main() {
  late Directory tmp;
  late String root, path;
  late CardStore s;
  final one = Uint8List.fromList(List.filled(1000, 1));
  final two = Uint8List.fromList(List.filled(1000, 2));
  final three = Uint8List.fromList(List.filled(1200, 3));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('store');
    root = p.join(tmp.path, '_card_copies');
    path = p.join(root, 'cards', 'Mcd001.ps2');
    Directory(p.dirname(path)).createSync(recursive: true);
    s = CardStore(
      safety: CardSafety(isApp: false, testRoots: [root]),
      root: p.join(root, 'backups'),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('changes, backups, history and restore', () {
    expect(s.create(path, one, fine), '');
    expect(File(path).readAsBytesSync(), one);
    expect(s.create(path, two, fine), isNot(''));
    expect(File(path).readAsBytesSync(), one, reason: 'never replaces');
    expect(s.change(path, one, two, 'delete', fine), '');
    expect(s.change(path, two, three, 'copy', fine), '');
    final h = s.history(path);
    expect(h, hasLength(2));
    expect([h[0].what, h[1].what], ['copy', 'delete'], reason: 'newest first');
    expect(s.readBackup(h[0]), two);
    expect(s.readBackup(h[1]), one);
    expect(s.restore(path, h[1], fine), '');
    expect(File(path).readAsBytesSync(), one);
    expect(s.history(path), hasLength(3));
    expect(s.readBackup(s.history(path)[0]), three);
    for (final ext in [CardStore.tempExt, CardStore.oldExt]) {
      expect(File(path + ext).existsSync(), isFalse);
    }
    final b = s.history(path)[0];
    final wrong = Backup(
      time: b.time,
      n: b.n,
      what: b.what,
      size: b.size,
      md5: 'x',
      file: b.file,
      path: b.path,
    );
    expect(s.restore(path, wrong, fine), isNot(''));
    expect(File(path).readAsBytesSync(), one);
  });

  test('refusals leave the card untouched', () {
    expect(s.create(path, one, fine), '');
    expect(
      s.change(path, two, one, 'x', fine),
      isNot(''),
      reason: 'changed since read',
    );
    expect(s.change(path, one, two, 'x', (_) => 'broken'), isNot(''));
    expect(s.change(path, one, Uint8List(0), 'x', fine), isNot(''));
    final busy = CardStore(
      safety: s.safety,
      root: s.root,
      ownerRunning: (_) => 'Close PCSX2 first',
    );
    expect(busy.change(path, one, two, 'x', fine), 'Close PCSX2 first');
    final blind = CardStore(safety: CardSafety(isApp: true), root: s.root);
    expect(
      blind.change(path, one, two, 'x', fine),
      isNot(''),
      reason: 'no emulator check',
    );
    final elsewhere = CardStore(
      safety: CardSafety(isApp: false, testRoots: [root]),
      root: p.join(tmp.path, 'real backups'),
    );
    expect(elsewhere.change(path, one, two, 'x', fine), CardSafety.refused);
    expect(File(path).readAsBytesSync(), one);
    expect(s.history(path), isEmpty);
    final outside = p.join(tmp.path, 'outside.mcd');
    expect(s.create(outside, one, fine), CardSafety.refused);
    expect(File(outside).existsSync(), isFalse);
    File(path + CardStore.oldExt).writeAsBytesSync(two);
    expect(
      s.change(path, one, two, 'x', fine),
      isNot(''),
      reason: 'an interrupted change stops the next',
    );
    expect(File(path).readAsBytesSync(), one);
  });

  test('an interrupted change stops the next, and neither copy is lost', () {
    expect(s.create(path, one, fine), '');
    File(path + CardStore.oldExt).writeAsBytesSync(two);
    expect(s.change(path, one, two, 'x', fine), isNot(''));
    expect(File(path).readAsBytesSync(), one);
    expect(File(path + CardStore.oldExt).readAsBytesSync(), two);
  });

  test('the gate: only test copies, unless it is the app', () {
    final tool = CardSafety(isApp: false, testRoots: [root]);
    expect(tool.refusal(path), '');
    expect(tool.refusal(p.join(tmp.path, 'x.mcd')), CardSafety.refused);
    expect(
      tool.refusal(p.join(root, '..', 'x.mcd')),
      CardSafety.refused,
      reason: "'..' can't climb out",
    );
    expect(tool.refusal(root), CardSafety.refused, reason: 'only inside it');
    expect(tool.refusal(' '), isNot(''), reason: 'no card chosen');
    expect(CardSafety(isApp: true).refusal(p.join(tmp.path, 'x.mcd')), '');
  });

  group('which emulator has a card open', () {
    final names = CardOwners.tasklistNames(
      '"System","4"\r\n"pcsx2-qt.exe","12"\r\n',
    );
    const ps2 = 'C:/Users/x/Documents/PCSX2/memcards/Mcd001.ps2';
    const ra = r'C:\RetroArch-Win64\saves\Flycast\a.bin';

    test('the process list is read', () {
      expect(names, ['system', 'pcsx2-qt.exe']);
    });

    test('an emulator locks only its own cards', () {
      expect(CardOwners.reason(ps2, names), isNot(''), reason: 'PCSX2 open');
      expect(CardOwners.reason(ra, names), '', reason: "RetroArch's alone");
      expect(
        CardOwners.reason('D:/cards/a.mcd', names),
        isNot(''),
        reason: 'a card kept elsewhere is locked by any emulator',
      );
      expect(CardOwners.reason(ra, ['retroarch.exe']), isNot(''));
      expect(
        CardOwners.reason(ps2, []),
        CardOwners.cantTell,
        reason: 'no process list = no write',
      );
    });

    test(
      'the real process list can be read',
      () => expect(CardOwners.inUse(ps2), isNot(CardOwners.cantTell)),
      skip: Platform.isWindows || Platform.isLinux
          ? false
          : 'only Windows and Linux list processes',
    );
  });

  test('a damaged backup record is passed over, not fatal', () {
    expect(s.create(path, one, fine), '');
    expect(s.change(path, one, two, 'delete', fine), '');
    final good = s.history(path).single;
    final dir = p.dirname(good.file);
    File(p.join(dir, '1-0001.card')).writeAsBytesSync(one);
    File(p.join(dir, '1-0001.json')).writeAsStringSync(
      '{"time": "soon", "n": null, "what": 1, "size": "x", "md5": 2}',
    );
    File(p.join(dir, '1-0002.json')).writeAsStringSync('[1, 2]');
    File(p.join(dir, '1-0003.json')).writeAsStringSync('{broken');
    final h = s.history(path);
    expect(h.first.what, 'delete', reason: 'the good one is still there');
    expect(s.readBackup(h.first), one);
    expect(s.allBackups().first.what, 'delete');
    for (final b in h.skip(1)) {
      expect(s.readBackup(b), isEmpty, reason: "a damaged one can't be read");
    }
  });
}
