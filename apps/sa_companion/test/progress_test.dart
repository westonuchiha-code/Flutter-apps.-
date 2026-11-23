import 'package:flutter_test/flutter_test.dart';
import 'package:sa_companion/data/game_data.dart';
import 'package:sa_companion/data/progress.dart';

void main() {
  test('data matches the original web app', () {
    expect(allCheats, hasLength(91));
    expect(missionCount, 97);
    expect(exportCount, 30);
    expect(places, hasLength(32));
    expect(referenceSections.map((s) => s.title), contains('About'));
  });

  test('every cheat uses known buttons', () {
    const known = {
      'X',
      'O',
      'T',
      'S',
      'U',
      'D',
      'L',
      'R',
      'L1',
      'L2',
      'R1',
      'R2',
    };
    for (final c in allCheats) {
      expect(known.containsAll(c.buttons), isTrue, reason: c.name);
    }
  });

  test('ids are unique', () {
    final missionIds = [
      for (final c in chapters) ...c.missions.map((m) => slug(m.name)),
    ];
    expect(missionIds.toSet(), hasLength(missionIds.length));
    final itemIds = allTrackItems.map((i) => i.id).toList();
    expect(itemIds.toSet(), hasLength(itemIds.length));
    final cheatNames = allCheats.map((c) => c.name).toList();
    expect(cheatNames.toSet(), hasLength(cheatNames.length));
  });

  test('slug matches the web version', () {
    expect(slug('Tagging Up Turf'), 'tagging-up-turf');
    expect(slug("Nines and AK's"), 'nines-and-ak-s');
    expect(slug('Farewell, My Love...'), 'farewell-my-love-');
  });

  // Expected values computed by running the original JavaScript stats().
  test('stats: empty progress', () {
    final s = Progress().stats;
    expect(s.percent, 0);
    expect(s.collectibleTotal, 250);
    expect(s.sideTotal, 33);
  });

  test('stats: mixed progress matches the web version', () {
    final p = Progress.decode(
      '{"m":{"big-smoke":1,"ryder":1,"tagging-up-turf":1},'
      '"k":{"medic":1,"ex-patriot":1,"ex-infernus":1},'
      '"c":{"tags":37,"oysters":50,"rls":4},"f":{}}',
    );
    final s = p.stats;
    expect(s.storyDone, 3);
    expect(s.collected, 87);
    expect(s.sideDone, closeTo(1.5111111, 1e-6));
    expect(s.percent, 7);
    expect(s.stars, 0);
  });

  test('stats: all story missions', () {
    final p = Progress(
      missions: {
        for (final c in chapters)
          for (final m in c.missions) slug(m.name): 1,
      },
    );
    expect(p.stats.percent, 2);
    expect(p.nextMission, isNull);
  });

  test('next mission follows story order', () {
    final p = Progress();
    expect(p.nextMission!.name, 'Big Smoke');
    p.missions[slug('Big Smoke')] = 1;
    expect(p.nextMission!.name, 'Ryder');
  });

  test('backup round trip and rejects junk', () {
    final p = Progress(
      missions: {'ryder': 1},
      checks: {'medic': 1},
      counts: {'tags': 12},
      favorites: {'Jetpack': 1},
    );
    final copy = Progress.decode(p.encode());
    expect(copy.toJson(), p.toJson());
    expect(() => Progress.decode('hello'), throwsFormatException);
    expect(() => Progress.decode('{"m":{}}'), throwsFormatException);
    expect(() => Progress.decode('[1,2]'), throwsFormatException);
    // Web backups may lack "f".
    expect(Progress.decode('{"m":{},"k":{},"c":{}}').favorites, isEmpty);
  });
}
