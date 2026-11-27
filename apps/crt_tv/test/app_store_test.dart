import 'dart:convert';
import 'dart:io';

import 'package:crt_tv/src/app_store.dart';
import 'package:crt_tv/src/loudness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tv_store_test');
    file = File('${dir.path}${Platform.pathSeparator}tv_data.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a steady stream of changes still gets saved', () async {
    final store = AppStore.at(file);
    // Changes arrive faster than the save delay for well over twice its
    // length, as they do while thousands of video lengths are being checked.
    final step = AppStore.saveDelay ~/ 5;
    for (var i = 0; i < 13; i++) {
      store.durations['video $i.mkv'] = 1000 + i;
      store.scheduleSave();
      await Future<void>.delayed(step);
    }
    expect(
      file.existsSync(),
      isTrue,
      reason: 'nothing was written while changes kept coming',
    );
    final saved = jsonDecode(file.readAsStringSync()) as Map;
    expect((saved['durations'] as Map).length, greaterThanOrEqualTo(5));
  });

  test('saveNow writes everything, including loudness and settings', () async {
    final store = AppStore.at(file);
    store.settings.libraryPath = r'E:\';
    store.settings.levelSound = true;
    store.durations[r'E:\a.mkv'] = 60000;
    store.loudness[r'E:\a.mkv'] = const Loudness(-21.5, -2);
    await store.saveNow();
    final saved = jsonDecode(file.readAsStringSync()) as Map;
    expect((saved['settings'] as Map)['libraryPath'], r'E:\');
    expect((saved['settings'] as Map)['levelSound'], isTrue);
    expect((saved['loudness'] as Map)[r'E:\a.mkv'], [-21.5, -2.0]);
  });
}
