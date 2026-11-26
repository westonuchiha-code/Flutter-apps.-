// The app's folders and config, the grid's visible columns, and Android's
// emulators-closed question.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:save_screens/src/controller.dart';
import 'package:save_screens/src/flow.dart';
import 'package:save_screens/src/folders.dart';
import 'package:save_screens/src/host.dart';
import 'package:save_screens/src/state.dart';

import 'fixtures.dart';

void main() {
  test('extra folders: one per line or split by ;', () {
    expect(splitFolders(' a ;b\n\nc\r\n'), ['a', 'b', 'c']);
    expect(splitFolders(''), isEmpty);
  });

  test('the app keeps its files in Documents/Save Manager', () {
    final docs = p.join('home', 'me', 'Documents');
    final at = Places(home: p.join('home', 'me'), documents: docs);
    final c = appConfigFor(at, platform: 'linux');
    final mine = p.join(docs, 'Save Manager');
    expect(c.isApp, isTrue);
    expect(c.backupRoot, p.join(mine, 'Backups'));
    expect(c.favoritesPath, p.join(mine, 'favorites.json'));
    expect(c.namesFile, p.join(mine, 'names.json'));
    expect(c.looksFile, p.join(mine, 'looks.json'));
    expect(c.stickerFolder, p.join(mine, 'Stickers'));
    expect(c.exportDir, CardFolders.exports(at));
    expect(c.looseDir, CardFolders.downloads(at));
    expect(c.running, isNull, reason: 'desktops ask the system');
    final check = EmulatorCheck();
    final android = appConfigFor(at, platform: 'android', check: check);
    expect(android.running!(), isNull, reason: "no yes yet: can't tell");
    check.yes();
    expect(android.running!(), EmulatorCheck.confirmed);
  });

  test(
    'a yes counts for two minutes; an empty list would mean "can\'t tell"',
    () {
      var now = DateTime(2026, 1, 1, 12);
      final check = EmulatorCheck(now: () => now);
      expect(check.fresh, isFalse);
      check.yes();
      now = now.add(const Duration(seconds: 119));
      expect(check.fresh, isTrue);
      expect(
        CardOwners.reason('/x/RetroArch/saves/a.srm', check.running()!),
        '',
        reason: 'the confirmed list names no emulator',
      );
      expect(CardOwners.reason('/x/a.srm', const []), CardOwners.cantTell);
      now = now.add(const Duration(seconds: 2));
      expect(check.fresh, isFalse);
      expect(check.running(), isNull);
    },
  );

  test('which emulators the question names', () {
    expect(
      EmulatorCheck.namesFor([
        '/storage/emulated/0/RetroArch/saves/x.srm',
        '/storage/emulated/0/Android/data/com.github.stenzek.duckstation/files/memcards/a.mcd',
      ]),
      'RetroArch and DuckStation',
    );
    expect(EmulatorCheck.namesFor(['/sdcard/Cards/a.mcd']), 'your emulators');
  });

  test('only jobs that change a card ask, not ones on downloads', () {
    final c = SaveManagerController(
      SaveManagerConfig(
        cardDirs: const [],
        backupRoot: 'b',
        exportDir: p.join('docs', 'Memory Card Exports'),
        namesFile: 'n',
        looksFile: 'l',
        looseDir: p.join('docs', 'Downloaded Saves'),
      ),
      check: EmulatorCheck(),
    );
    final mine = MemoryCard()..path = p.join('RetroArch', 'saves', 'a.srm');
    final loose = MemoryCard()
      ..path = p.join('docs', 'Downloaded Saves', 'b.srm');
    expect(c.changesCards(FlowJob('delete', card: mine)), isTrue);
    expect(c.changesCards(FlowJob('delete', card: loose)), isFalse);
    expect(c.changesCards(FlowJob('back_up', card: mine)), isFalse);
    expect(c.changesCards(FlowJob('copy', card: loose, to: mine)), isTrue);
    c.dispose();
  });

  test('the grid steps as many across as the screen shows', () {
    final st = MemoryCardState();
    final cards = fakeCards();
    st.setData(cards, savesOf(cards));
    expect(st.cols, MemoryCardState.defaultCols);
    expect(st.setGrid(3, 2), isTrue);
    expect(st.setGrid(3, 2), isFalse);
    expect(st.step(0, 1), isTrue);
    expect(st.index, 3, reason: 'down = one row of three');
    st.step(0, 1);
    expect(st.index, 6);
    expect(st.topRow, 1, reason: 'two rows on screen: it scrolled');
    expect(st.visibleSpan(), (3, 8));
    st.setGrid(4, 4);
    expect(st.topRow, 0);
    expect(st.current(), isNotNull);
  });

  test('platform name', () {
    expect(['windows', 'linux', 'android'], contains(platformName()));
    if (Platform.isLinux) expect(platformName(), 'linux');
  });
}
