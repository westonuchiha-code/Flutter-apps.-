import 'package:flutter_test/flutter_test.dart';
import 'package:sa_companion/app/app_state.dart';
import 'package:sa_companion/app/progress_store.dart';
import 'package:sa_companion/data/game_data.dart';
import 'package:sa_companion/data/progress.dart';

void main() {
  test('loads, changes and saves progress', () async {
    final store = MemoryProgressStore('{"m":{"ryder":1},"k":{},"c":{},"f":{}}');
    final state = AppState(store);
    await state.load();
    expect(state.progress.missions, {'ryder': 1});

    final bigSmoke = chapters.first.missions.first;
    state.toggleMission(bigSmoke);
    expect(state.missionPassed.value, 'Big Smoke');
    expect(Progress.decode(store.saved!).missionPassed(bigSmoke), isTrue);
    state.toggleMission(bigSmoke);
    expect(state.progress.missionPassed(bigSmoke), isFalse);

    final tags = allTrackItems.firstWhere((i) => i.id == 'tags');
    state.step(tags, 5);
    state.step(tags, -10);
    expect(state.progress.count('tags'), 0);
    state.setCount(tags, 500);
    expect(state.progress.count('tags'), 100);

    state.toggleFavorite(allCheats.first);
    expect(state.progress.isFavorite(allCheats.first), isTrue);
  });

  test('corrupt saved data starts fresh', () async {
    final state = AppState(MemoryProgressStore('not json'));
    await state.load();
    expect(state.loaded, isTrue);
    expect(state.progress.missions, isEmpty);
  });

  test('restore and reset (reset keeps favorites)', () async {
    final state = AppState(MemoryProgressStore());
    await state.load();
    expect(state.restore('nope'), isFalse);
    expect(
      state.restore(
        '{"m":{"ryder":1},"k":{"fire":1},"c":{"tags":3},"f":{"Jetpack":1}}',
      ),
      isTrue,
    );
    expect(state.progress.checked('fire'), isTrue);
    state.resetAll();
    expect(state.progress.missions, isEmpty);
    expect(state.progress.counts, isEmpty);
    expect(state.progress.favorites, {'Jetpack': 1});
  });
}
