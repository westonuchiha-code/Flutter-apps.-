// The PC's saves the phone keeps as copies (Cross-Save brings them to
// XMB Frontend/Saves/PCSX2, RPCS3, RMG, Switch...): found by the Android
// folder list, marked as PC copies, and never changed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:save_screens/src/controller.dart';
import 'package:save_screens/src/flow.dart';
import 'package:save_screens/src/folders.dart';
import 'package:save_screens/src/host.dart';
import 'package:save_screens/src/texts.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('pc_copies'));
  tearDown(() => temp.deleteSync(recursive: true));

  test("Android: the PC's copies are read, and read-only", () {
    final s = temp.path;
    final saves = p.join(s, 'XMB Frontend', 'Saves');
    for (final d in ['RetroArch', 'Dolphin', 'PCSX2', 'RPCS3', 'NewEmu']) {
      Directory(p.join(saves, d)).createSync(recursive: true);
    }
    final at = Places(home: s, documents: p.join(s, 'Documents'), storage: s);
    final c = appConfigFor(at, platform: 'android');
    expect(c.cardDirs, contains(saves));
    expect(c.readOnlyDirs.map(p.basename).toSet(), {
      'PCSX2', 'RPCS3', 'RMG', 'Switch', 'Xenia', 'NewEmu', //
    });
    final safety = c.safety();
    expect(
      safety.refusal(p.join(saves, 'PCSX2', 'memcards', 'Mcd001.ps2')),
      CardSafety.readOnlyNotice,
    );
    expect(
      safety.isReadOnly(p.join(saves, 'RetroArch', 'Gambatte', 'Red.srm')),
      isFalse,
      reason: 'the two-way saves stay changeable',
    );
    expect(
      appConfigFor(at, platform: 'windows').readOnlyDirs,
      isEmpty,
      reason: "the PC's own cards are its to change",
    );
  });

  test('a PC copy is marked, and every job refuses to change it', () {
    final saves = p.join(temp.path, 'XMB Frontend', 'Saves');
    final card = p.join(saves, 'PCSX2', 'memcards', 'Mcd001.ps2');
    File(card)
      ..createSync(recursive: true)
      ..writeAsBytesSync(Ps2Writer.blank());
    final mine = p.join(temp.path, 'mine', 'card.ps2');
    File(mine)
      ..createSync(recursive: true)
      ..writeAsBytesSync(Ps2Writer.blank());
    final readOnly = [p.join(saves, 'PCSX2'), p.join(saves, 'RPCS3')];
    final got = readCardsJob(
      ReadConfig(
        dirs: [saves, p.dirname(mine)],
        namesFile: p.join(temp.path, 'names.json'),
        favoritesFile: p.join(temp.path, 'favorites.json'),
        looksFile: p.join(temp.path, 'looks.json'),
        isApp: false,
        testRoots: [temp.path],
        readOnlyDirs: readOnly,
      ),
    );
    final pc = got.cards.singleWhere((c) => c.path == card);
    final own = got.cards.singleWhere((c) => c.path == mine);
    expect(pc.readOnly, isTrue);
    expect(own.readOnly, isFalse);
    expect(Texts.cardTag(pc), endsWith(Texts.pcCopyTag));
    expect(Texts.cardTag(own), isNot(contains(Texts.pcCopyTag)));
    expect(
      Texts.cardRows(pc, 0),
      contains(('In the console', Texts.pcCopyNote)),
    );

    final ops = CardOpsConfig(
      isApp: false,
      testRoots: [temp.path],
      readOnlyDirs: readOnly,
      backupRoot: p.join(temp.path, 'backups'),
      exportDir: p.join(temp.path, 'exports'),
      askSystem: false,
      running: const ['bash'],
    ).build();
    final before = File(card).readAsBytesSync();
    expect(ops.formatCard(pc).text, CardSafety.readOnlyNotice);
    expect(ops.deleteCard(pc).text, CardSafety.readOnlyNotice);
    expect(ops.duplicateCard(pc).text, CardSafety.readOnlyNotice);
    expect(ops.backUpCards([pc]).ok, isTrue, reason: 'backing up is fine');
    expect(ops.duplicateCard(own).ok, isTrue, reason: 'its own cards change');
    expect(File(card).readAsBytesSync(), before);
    expect(Directory(p.dirname(card)).listSync().length, 1);
  });
}
