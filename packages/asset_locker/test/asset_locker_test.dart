import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asset_locker/asset_locker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory dir;
  late AssetLocker locker;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('locker_test');
    locker = AssetLocker.atDirectory('test_app', dir);
  });
  tearDown(() => dir.delete(recursive: true));

  test('save, list, read, update and delete', () async {
    final a = await locker.save(
      type: AssetType.sample,
      name: 'Kick Drum!',
      bytes: [1, 2, 3],
      extension: '.WAV',
      tags: ['drums'],
      thumbnail: Uint8List.fromList([9]),
    );
    await locker.save(
      type: AssetType.palette,
      name: 'Sunset',
      bytes: [4],
      extension: 'json',
    );
    expect(a.extension, 'wav');
    expect(a.id, startsWith('kick-drum-'));
    expect(File('${dir.path}/Samples/${a.id}.wav').existsSync(), isTrue);

    final all = await locker.list();
    expect(all.map((e) => e.name), containsAll(['Kick Drum!', 'Sunset']));
    final samples = await locker.list(type: AssetType.sample);
    expect(samples.single.tags, ['drums']);
    expect(samples.single.app, 'test_app');
    expect(await locker.read(samples.single), [1, 2, 3]);
    expect(await locker.thumbnail(samples.single), [9]);

    await locker.update(samples.single.copyWith(name: 'Kick', tags: ['a']));
    expect((await locker.list(type: AssetType.sample)).single.name, 'Kick');

    await locker.delete(samples.single);
    expect(await locker.list(type: AssetType.sample), isEmpty);
    expect(Directory('${dir.path}/Samples').listSync(), isEmpty);
  });

  test('extra details and replace', () async {
    final a = await locker.save(
      type: AssetType.recording,
      name: 'Birds',
      bytes: [1, 2],
      extension: 'wav',
      extra: {
        'markers': [1.5, 3.0],
      },
    );
    var got = (await locker.list()).single;
    expect(got.extra['markers'], [1.5, 3.0]);
    final b = await locker.replace(got, [7, 7, 7], extra: {'markers': []});
    got = (await locker.list()).single;
    expect(got.size, 3);
    expect(got.extra['markers'], isEmpty);
    expect(await locker.read(b), [7, 7, 7]);
    expect(got.id, a.id);
  });

  test('JSON assets keep their data (details are stored separately)', () async {
    final a = await locker.save(
      type: AssetType.preset,
      name: 'Kit',
      bytes: utf8.encode('{"kind":"sample_pad_kit","bpm":120}'),
      extension: 'json',
    );
    final listed = (await locker.list(type: AssetType.preset)).single;
    expect(listed.name, 'Kit');
    expect(
      utf8.decode((await locker.read(a))!),
      '{"kind":"sample_pad_kit","bpm":120}',
    );
    await locker.update(listed.copyWith(name: 'Kit 2'));
    expect(utf8.decode((await locker.read(a))!), contains('sample_pad_kit'));
    await locker.delete(listed);
    expect(Directory('${dir.path}/Presets').listSync(), isEmpty);
  });

  test('details saved by version 0.1 (<id>.json) still list', () async {
    Directory('${dir.path}/Samples').createSync(recursive: true);
    File('${dir.path}/Samples/old-1.wav').writeAsBytesSync([1, 2]);
    File('${dir.path}/Samples/old-1.json').writeAsStringSync(
      '{"id":"old-1","type":"sample","name":"Old","extension":"wav","app":"x","created":"2026-11-20T10:00:00Z"}',
    );
    final old = (await locker.list(type: AssetType.sample)).single;
    expect(old.name, 'Old');
    expect(await locker.read(old), [1, 2]);
    // Editing moves the details to the new file and removes the old one.
    await locker.update(old.copyWith(name: 'Old 2'));
    expect(File('${dir.path}/Samples/old-1.json').existsSync(), isFalse);
    expect((await locker.list(type: AssetType.sample)).single.name, 'Old 2');
  });

  test('broken metadata is skipped', () async {
    await locker.save(
      type: AssetType.map,
      name: 'ok',
      bytes: [1],
      extension: 'map',
    );
    File('${dir.path}/Maps/junk.json').writeAsStringSync('{nope');
    expect((await locker.list()).single.name, 'ok');
  });

  test('error reports and to-do list', () async {
    await locker.writeErrorReport({'name': 'Test', 'entries': []});
    final other = AssetLocker.atDirectory('other_app', dir);
    await other.writeErrorReport({'name': 'Other', 'entries': []});
    final reports = await locker.readErrorReports();
    expect(reports.keys, unorderedEquals(['test_app', 'other_app']));
    await locker.clearErrorReport('other_app');
    expect((await locker.readErrorReports()).keys, ['test_app']);

    final now = DateTime.now();
    await locker.writeTodos([
      TodoItem(id: '1', text: 'Fix pads', created: now, tag: 'touch_synth'),
      TodoItem(id: '2', text: 'Ship', created: now, done: true),
    ]);
    final todos = await other.readTodos();
    expect(todos.map((t) => t.text), ['Fix pads', 'Ship']);
    expect(todos.first.tag, 'touch_synth');
    expect(todos.last.done, isTrue);
  });

  test('tree folder names', () {
    expect(
      AssetLocker.treeFolderName(
        'content://com.android.externalstorage.documents/tree/primary%3ADocuments',
      ),
      'Documents',
    );
    expect(
      AssetLocker.treeFolderName(
        'content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FAsset%20Locker',
      ),
      'Asset Locker',
    );
  });

  testWidgets('browser filters by search and picks', (tester) async {
    await tester.runAsync(() async {
      await locker.save(
        type: AssetType.sample,
        name: 'Kick',
        bytes: [1],
        extension: 'wav',
        tags: ['drums'],
      );
      await locker.save(
        type: AssetType.sprite,
        name: 'Hero',
        bytes: [1],
        extension: 'png',
      );
    });
    AssetInfo? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LockerBrowser(locker: locker, onTap: (i) => picked = i),
        ),
      ),
    );
    for (var i = 0; i < 100 && find.text('Kick').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('Kick'), findsOneWidget);
    expect(find.text('Hero'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'drum');
    await tester.pump();
    expect(find.text('Hero'), findsNothing);
    await tester.tap(find.text('Kick'));
    expect(picked?.name, 'Kick');
  });
}
