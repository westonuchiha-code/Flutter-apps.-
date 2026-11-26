// box.json reads and writes through a real background isolate (as in the
// apps): atomic, and refused when the file changed on disk.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pokeville/pokeville.dart';

import 'fixtures.dart';

void main() {
  late Directory temp;
  late String dir;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pokeville_folder');
    dir = makePokeville(temp.path);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('read, write, changed on disk (background isolate)', () async {
    final f = PokevilleFolder(dir);
    final r = await f.read();
    expect(r.state, BoxState.ready);
    final data = r.data!;
    PokeBoxStore.move(data, 0, 0, 0, 5);
    expect((await f.write(data)).outcome, WriteOutcome.saved);
    expect(await f.changedOnDisk(), isFalse);
    expect(File(p.join(dir, 'box.json.tmp')).existsSync(), isFalse);
    final back = PokeBoxStore.parse(File(f.indexPath).readAsStringSync())!;
    expect(Mon.of(PokeBoxStore.slot(back, 0, 5))!.name, 'Meowth');

    File(f.indexPath)
        .writeAsStringSync(PokeBoxStore.encode(PokeBoxStore.blank()));
    expect(await f.changedOnDisk(), isTrue);
    PokeBoxStore.move(data, 0, 5, 0, 6);
    final w = await f.write(data);
    expect(w.outcome, WriteOutcome.changed);
    expect(PokeBoxStore.total(w.read!.data!), 0, reason: 'the synced one');
    expect(
      PokeBoxStore.total(
        PokeBoxStore.parse(File(f.indexPath).readAsStringSync())!,
      ),
      0,
      reason: 'not overwritten',
    );
  });

  test('missing and broken', () async {
    File(p.join(dir, 'box.json')).deleteSync();
    final f = PokevilleFolder(dir, runner: runHere);
    expect((await f.read()).state, BoxState.missing);
    expect(f.exists, isFalse);
    File(p.join(dir, 'box.json')).writeAsStringSync('nope');
    final r = await f.read();
    expect(r.state, BoxState.broken);
    expect(r.text, 'nope');
  });
}
