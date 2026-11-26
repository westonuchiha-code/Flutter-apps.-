import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
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
}
