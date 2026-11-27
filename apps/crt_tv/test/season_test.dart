import 'dart:io';

import 'package:crt_tv/src/library_scanner.dart';
import 'package:crt_tv/src/season.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('months, ranges, lists and season words are understood', () {
    expect(parseSeason('Oct'), {10});
    expect(parseSeason('October'), {10});
    expect(parseSeason('Sept'), {9});
    expect(parseSeason('12'), {12});
    expect(parseSeason('Jun-Aug'), {6, 7, 8});
    expect(parseSeason('June to August'), {6, 7, 8});
    expect(parseSeason('Nov-Jan'), {11, 12, 1}, reason: 'runs over New Year');
    expect(parseSeason('Oct, Dec'), {10, 12});
    expect(parseSeason('Summer'), {6, 7, 8});
    expect(parseSeason('winter'), {12, 1, 2});
  });

  test('other things in brackets are not seasons', () {
    expect(parseSeason('HD'), isNull);
    expect(parseSeason('1080p'), isNull);
    expect(parseSeason('Ma'), isNull, reason: 'too short to tell March from May');
    expect(parseSeason('13'), isNull);
    expect(parseSeason('English Dubbed'), isNull);
  });

  test('the tag is taken out of the folder name', () {
    void check(String folder, String name, Set<int> months) {
      final (gotName, gotMonths) = splitSeasonTag(folder);
      expect(gotName, name);
      expect(gotMonths, months);
    }

    check('Channel Halloween [Oct]', 'Channel Halloween', {10});
    check('Channel 9 [Dec] Xmas', 'Channel 9 Xmas', {12});
    check('Channel Beach Episodes [Jun-Aug]', 'Channel Beach Episodes', {6, 7, 8});
    check('Channel Otaku [HD]', 'Channel Otaku [HD]', {});
    check('Channel 4 (Saturday Mornings)', 'Channel 4 (Saturday Mornings)', {});
  });

  test('a channel is on the air only in its months', () {
    expect(inSeason({10}, DateTime(2026, 10, 31)), isTrue);
    expect(inSeason({10}, DateTime(2026, 11, 1)), isFalse);
    expect(inSeason({12, 1, 2}, DateTime(2027, 1, 15)), isTrue);
    expect(inSeason(const {}, DateTime(2026, 7, 4)), isTrue, reason: 'no tag means all year');
  });

  test('seasons are shown compactly', () {
    expect(seasonLabel({10}), 'OCT');
    expect(seasonLabel({6, 7, 8}), 'JUN-AUG');
    expect(seasonLabel({12, 1, 2}), 'DEC-FEB');
    expect(seasonLabel({10, 12}), 'OCT, DEC');
    expect(seasonLabel(const {}), '');
  });

  test('the scanner reads seasons and keeps channel numbers steady all year', () {
    final root = Directory.systemTemp.createTempSync('tv_season_test');
    addTearDown(() => root.deleteSync(recursive: true));
    void touch(String relative) {
      final f = File('${root.path}/$relative');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('x');
    }

    touch('Channel Anime/a.mkv');
    touch('Channel Halloween [Oct]/spooky.mkv');
    touch('Channel Robo/r.mkv');

    final lib = scanLibrarySync(root.path);
    expect(lib.channels.map((c) => '${c.number} ${c.name}').toList(), ['1 Anime', '2 Robo', '3 Halloween'],
        reason: 'the seasonal channel goes after the year-round ones');
    final halloween = lib.channel(3)!;
    expect(halloween.months, {10});
    expect(halloween.folderName, 'Channel Halloween [Oct]', reason: 'settings stay keyed by the real folder');
    expect(lib.channel(1)!.months, isEmpty);
  });
}
