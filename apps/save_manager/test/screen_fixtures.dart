// A temp test root of made-up memory cards for the screen tests and
// shots, or a copy of real ones (SAVE_SAMPLES), and a controller over it.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:save_manager/src/controller.dart';

import 'fixtures.dart';

/// Runs a job here and now (tests).
Future<R> runNow<A, R>(R Function(A) work, A arg) async => work(arg);

/// Made-up cards under [root]/cards: two PS2 cards (one empty), two PS1
/// cards (one empty), a Dreamcast VMU.
void makeCards(String root) {
  final cards = p.join(root, 'cards');
  var ps2 = Ps2Writer.blank();
  for (final (i, id) in [
    'BASLUS-20000DIAMOND',
    'BASLUS-20001ROAD',
    'BESLES-50000CRASH',
  ].indexed) {
    ps2 = Ps2Writer.importSave(ps2, psu(id, [964, 2000 + i * 3000])).data;
  }
  put(p.join(cards, 'PCSX2', 'memcards', 'Mcd001.ps2'), ps2);
  put(p.join(cards, 'PCSX2', 'memcards', 'Mcd002.ps2'), Ps2Writer.blank());
  var ps1 = Ps1Writer.blank();
  for (var i = 0; i < 4; i++) {
    ps1 = Ps1Writer.importSave(ps1, mcs('BASLUS-0000$i', 1 + i % 2, i)).data;
  }
  put(p.join(cards, 'DuckStation', 'memcards', 'shared_card_1.mcd'), ps1);
  put(
    p.join(cards, 'DuckStation', 'memcards', 'shared_card_2.mcd'),
    Ps1Writer.blank(),
  );
  var vmu = VmuWriter.blank();
  for (final n in ['SONIC', 'CRAZY']) {
    vmu = VmuWriter.importSave(vmu, dci(n, 3, VmuWriter.data)).data;
  }
  put(p.join(cards, 'RetroArch', 'system', 'dc', 'vmu_save_A1.bin'), vmu);
}

/// Copies every file of [from] into [to] (real samples: never written to).
void copyTree(String from, String to) {
  for (final e in Directory(from).listSync(recursive: true)) {
    if (e is! File || p.split(e.path).contains('.git')) continue;
    final dest = p.join(to, p.relative(e.path, from: from));
    Directory(p.dirname(dest)).createSync(recursive: true);
    e.copySync(dest);
  }
}

/// The controller's config over [root] (a test root: it may be written).
SaveManagerConfig testConfig(String root, {List<String>? running}) =>
    SaveManagerConfig(
      cardDirs: [p.join(root, 'cards')],
      backupRoot: p.join(root, 'Save Manager', 'Backups'),
      exportDir: p.join(root, 'Memory Card Exports'),
      namesFile: p.join(root, 'Save Manager', 'names.json'),
      looksFile: p.join(root, 'Save Manager', 'looks.json'),
      favoritesFile: p.join(root, 'Save Manager', 'favorites.json'),
      stickerFolder: p.join(root, 'Save Manager', 'Stickers'),
      looseDir: p.join(root, 'Downloaded Saves'),
      importFolders: [p.join(root, 'Memory Card Exports')],
      testRoots: [root],
      running: () => running ?? const ['test-runner'],
      utcOffset: 0,
    );

/// A page size in dp, at [dpr].
void setView(WidgetTester tester, Size dp, {double dpr = 1}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = dp * dpr;
}

/// Presses and lets go of [key].
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 50));
}

/// The app's dark Material around [child].
Widget host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData.dark(),
  home: Scaffold(body: child),
);
