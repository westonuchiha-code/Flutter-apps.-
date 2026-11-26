// The controller drives state and flow like the PC's MemoryCardScreen.gd:
// reads in the background, runs jobs, favorites, rename, customize.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:save_manager/src/controller.dart';
import 'package:save_manager/src/flow.dart';
import 'package:save_manager/src/state.dart';

import 'fixtures.dart';

Future<R> runNow<A, R>(R Function(A) work, A arg) async => work(arg);

void main() {
  late Directory temp;
  late SaveManagerController c;
  final sounds = <String>[];

  setUp(() {
    temp = Directory.systemTemp.createTempSync('save_manager_ctl');
    final dir = temp.path;
    var d = Ps1Writer.blank();
    for (var i = 0; i < 3; i++) {
      d = Ps1Writer.importSave(d, mcs('BASLUS-0000$i', 1, i)).data;
    }
    put(p.join(dir, 'cards', 'a.mcd'), d);
    put(p.join(dir, 'cards', 'b.mcd'), Ps1Writer.blank());
    sounds.clear();
    c = SaveManagerController(
      SaveManagerConfig(
        cardDirs: [p.join(dir, 'cards')],
        backupRoot: p.join(dir, 'backups'),
        exportDir: p.join(dir, 'exports'),
        namesFile: p.join(dir, 'names.json'),
        looksFile: p.join(dir, 'looks.json'),
        testRoots: [dir],
        running: () => const ['test-runner'],
        utcOffset: 0,
      ),
      runner: runNow,
      onSound: sounds.add,
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('opens and reads the cards', () async {
    c.open();
    expect(c.isLoading, isTrue);
    await c.settled();
    expect(c.loaded, isTrue);
    expect(c.state.allSaves.length, 3);
    expect(c.state.column().length, 2);
  });

  test('favorite, then delete only explains', () async {
    c.open();
    await c.settled();
    c.toggleFavorite();
    expect(c.notice, startsWith('Favorite:'));
    expect(c.state.current()!.favorite, isTrue);
    c.state.selectListButton(3); // DELETE
    c.confirm();
    expect(c.flow.title, "THAT'S A FAVORITE");
    c.confirm();
    expect(c.flow.isOpen(), isFalse);
    c.refresh();
    await c.settled();
    expect(c.state.current()!.favorite, isTrue, reason: 'read back as one');
    c.toggleFavorite();
    expect(c.notice, startsWith('Star taken off'));
  });

  test('copy through the controller lands and re-reads', () async {
    c.open();
    await c.settled();
    c.state.selectListButton(0); // COPY
    c.confirm();
    expect(c.flow.kind, FlowKind.copy);
    c.confirm();
    expect(c.isJobRunning, isTrue);
    await c.settled();
    expect(c.notice, startsWith('Copied'));
    expect(c.state.allSaves.length, 4);
    expect(sounds, contains('confirm'));
  });

  test('B all the way out closes', () async {
    c.open();
    await c.settled();
    c.confirm(); // open the save
    expect(c.state.mode, Mode.opened);
    expect(c.cancel(), isTrue);
    expect(c.cancel(), isFalse);
    expect(c.isOpen, isFalse);
  });

  test('rename and customize from a card page', () async {
    c.open();
    await c.settled();
    c.selectCard(0);
    c.confirm(); // its page
    c.selectPageButton(1); // RENAME
    c.confirm();
    expect(c.renaming, isNotNull);
    c.named('My card');
    await c.settled();
    expect(c.state.column().any((k) => k.name == 'My card'), isTrue);
    c.selectCard(0);
    c.confirm();
    c.selectPageButton(0); // CUSTOMIZE
    c.confirm();
    expect(c.flow.kind, FlowKind.look);
    c.step(1, 0); // a colour
    c.selectLookRow(3);
    c.confirm(); // DONE
    expect(c.notice, contains('Midnight Black'));
    c.refresh();
    await c.settled();
    expect(c.state.cards.any((k) => k.color != 0), isTrue);
  });

  test('Move card saves the order', () async {
    c.open();
    await c.settled();
    c.selectCard(0);
    c.toggleOptions();
    c.selectOption(
      c.state.flatOptions().indexWhere((o) => o.verb == 'reorder'),
    );
    c.confirm();
    expect(c.state.moving, isTrue);
    final first = c.state.column()[0];
    c.step(0, 1);
    c.confirm();
    expect(c.notice, 'Card order saved');
    c.refresh();
    await c.settled();
    expect(c.state.column()[1].key(), first.key());
  });
}
