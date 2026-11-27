import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:app_shell/app_shell.dart';
import 'package:cross_save/src/controller.dart';
import 'package:cross_save/src/cross_save.dart';
import 'package:cross_save/src/setup.dart';

/// GitHub in memory: commits are (tree = files), the branch moves only
/// forward.
class FakeRepo implements SaveRepo {
  final blobs = <String, Uint8List>{};
  final trees = <String, Map<String, String>>{'t0': {}};
  final commits = <String, (String tree, String parent, String message)>{
    'c0': ('t0', '', 'start'),
  };
  String branch = 'c0';
  int _n = 0;

  /// Called once before the next moveBranch (another device pushes).
  void Function()? racer;

  Map<String, String> get current => trees[commits[branch]!.$1]!;
  String get lastMessage => commits[branch]!.$3;

  @override
  Future<({String commit, String tree})> head() async =>
      (commit: branch, tree: commits[branch]!.$1);
  @override
  Future<Map<String, String>> files(String tree) async => {...trees[tree]!};
  @override
  Future<Uint8List> blob(String sha) async => blobs[sha]!;
  @override
  Future<String> putBlob(Uint8List bytes) async {
    final sha = blobSha(bytes);
    blobs[sha] = bytes;
    return sha;
  }

  @override
  Future<String> putTree(String base, Map<String, String> files) async {
    final id = 't${++_n}';
    trees[id] = {...trees[base]!, ...files};
    return id;
  }

  @override
  Future<String> commit(String message, String tree, String parent) async {
    final id = 'c${++_n}';
    commits[id] = (tree, parent, message);
    return id;
  }

  @override
  Future<bool> moveBranch(String commit) async {
    final r = racer;
    racer = null;
    r?.call();
    if (commits[commit]!.$2 != branch) return false; // not a fast-forward
    branch = commit;
    return true;
  }

  /// Another device pushes [path] = [text] directly.
  void pushAs(String path, String text) {
    final bytes = Uint8List.fromList(text.codeUnits);
    final sha = blobSha(bytes);
    blobs[sha] = bytes;
    final t = 't${++_n}', c = 'c${++_n}';
    trees[t] = {...current, path: sha};
    commits[c] = (t, branch, 'pc: $path');
    branch = c;
  }
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('xs'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the table matches the PC (and PROTOCOL.md)', () {
    expect(decide('', '', ''), 'none');
    expect(decide('a', 'a', ''), 'same');
    expect(decide('', 'r', ''), 'take');
    expect(decide('l', '', ''), 'send');
    expect(decide('s', 'r', 's'), 'take');
    expect(decide('l', 's', 's'), 'send');
    expect(decide('l', 'r', 's'), 'conflict');
    expect(decide('l', 'r', ''), 'conflict'); // first sync: nothing lost
    expect(decide('', 'r', 's'), 'take'); // deleted here: comes back
  });

  test('never-synced names and git blob hashes', () {
    expect(skipped('Crystal.from-repo-20261125-101010.srm'), isTrue);
    expect(skipped('main.box-backup-20261125'), isTrue);
    expect(skipped('box.json.tmp'), isTrue);
    expect(skipped('Pokemon - Crystal Version (USA, Europe).srm'), isFalse);
    // `git hash-object` of "hello\n".
    expect(
      blobSha('hello\n'.codeUnits),
      'ce013625030ba8dba906f756967f9e9ca394464a',
    );
    const m = SyncMap('saves/retroarch', '/x', exts: ['srm', 'rtc']);
    expect(m.takes('Gambatte/Red.srm'), isTrue);
    expect(m.takes('Gambatte/Red.state'), isFalse);
    expect(m.takes('.hidden/Red.srm'), isFalse);
    const pv = SyncMap('pokeville', '/x', skipDirs: ['sent', 'save backups']);
    expect(pv.takes('mons/sent/a.pk2'), isFalse);
    expect(pv.takes('mons/a.pk2'), isTrue);
  });

  test(
    'two devices: send, take, nothing, conflict once, pick a side',
    () async {
      final repo = FakeRepo();
      const rel = 'Gambatte/Pokemon - Crystal Version (USA, Europe).srm';
      final aDir = p.join(root.path, 'a'), bDir = p.join(root.path, 'b');
      final mapA = [
        SyncMap('saves/retroarch', aDir, exts: const ['srm']),
      ];
      final mapB = [
        SyncMap('saves/retroarch', bDir, exts: const ['srm']),
      ];
      final stA = <String, String>{}, stB = <String, String>{};
      File f(String dir) => File(
        p.join(dir, 'Gambatte', 'Pokemon - Crystal Version (USA, Europe).srm'),
      );
      Future<SyncReport> sync(String who) => crossSync(
        repo: repo,
        maps: who == 'a' ? mapA : mapB,
        state: who == 'a' ? stA : stB,
        device: who == 'a' ? 'phone' : 'retroid',
        backups: p.join(root.path, '$who-backups'),
      );

      // 1. A has a save: sent, one commit named after the game.
      f(aDir)
        ..createSync(recursive: true)
        ..writeAsStringSync('crystal v1');
      final r1 = await sync('a');
      expect(r1.ok, isTrue, reason: r1.error);
      expect(r1.sent, [rel]);
      expect(
        repo.lastMessage,
        'phone: Pokemon - Crystal Version (USA, Europe)',
      );
      // 2. B gets it.
      final r2 = await sync('b');
      expect(r2.took, [rel]);
      expect(f(bDir).readAsStringSync(), 'crystal v1');
      // 3. B plays; A takes the newer one, its own backed up first.
      f(bDir).writeAsStringSync('crystal v2 from the retroid');
      expect((await sync('b')).sent, [rel]);
      final r3 = await sync('a');
      expect(r3.took, [rel]);
      expect(f(aDir).readAsStringSync(), 'crystal v2 from the retroid');
      final backup = Directory(p.join(root.path, 'a-backups'))
          .listSync(recursive: true)
          .whereType<File>()
          .single;
      expect(backup.readAsStringSync(), 'crystal v1');
      // 4. Nothing changed: nothing moves.
      final r4 = await sync('a');
      expect(
        r4.took.isEmpty && r4.sent.isEmpty && r4.conflicts.isEmpty,
        isTrue,
      );
      // 5. Both play: conflict; ours stays, theirs beside it.
      f(bDir).writeAsStringSync('retroid v3');
      await sync('b');
      f(aDir).writeAsStringSync('phone v3');
      final r5 = await sync('a');
      expect(r5.conflicts.length, 1);
      expect(f(aDir).readAsStringSync(), 'phone v3');
      final copies = Directory(p.join(aDir, 'Gambatte'))
          .listSync()
          .where((e) => p.basename(e.path).contains(conflictTag))
          .toList();
      expect(copies.length, 1);
      expect(File(copies.single.path).readAsStringSync(), 'retroid v3');
      // ...not copied again on the next sync, and never sent to the repo.
      final r6 = await sync('a');
      expect(r6.conflicts.length, 1);
      expect(
        Directory(p.join(aDir, 'Gambatte'))
            .listSync()
            .where((e) => p.basename(e.path).contains(conflictTag))
            .length,
        1,
      );
      expect(repo.current.keys.where((k) => k.contains(conflictTag)), isEmpty);
      // 6. The player keeps the phone's: it's sent, and B then takes it.
      await keepLocal(r6.conflicts.single, stA, p.join(root.path, 'a-backups'));
      final r7 = await sync('a');
      expect(r7.sent, [rel]);
      expect((await sync('b')).took, [rel]);
      expect(f(bDir).readAsStringSync(), 'phone v3');
    },
  );

  test('the other side wins when the player picks it', () async {
    final repo = FakeRepo();
    final dir = p.join(root.path, 'a');
    final maps = [
      SyncMap('saves/retroarch', dir, exts: const ['srm']),
    ];
    final st = <String, String>{};
    final save = File(p.join(dir, 'mGBA', 'Emerald.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('phone');
    repo.pushAs('saves/retroarch/mGBA/Emerald.srm', 'pc');
    final r = await crossSync(
      repo: repo,
      maps: maps,
      state: st,
      device: 'phone',
      backups: p.join(root.path, 'bk'),
    );
    expect(r.conflicts.length, 1); // first sync, different files
    await keepOther(
      r.conflicts.single,
      st,
      p.join(root.path, 'bk'),
      DateTime(2026),
    );
    expect(save.readAsStringSync(), 'pc');
    final again = await crossSync(
      repo: repo,
      maps: maps,
      state: st,
      device: 'phone',
      backups: p.join(root.path, 'bk'),
    );
    expect(
      again.took.isEmpty && again.sent.isEmpty && again.conflicts.isEmpty,
      isTrue,
    );
  });

  test('someone pushes meanwhile: read again, then send', () async {
    final repo = FakeRepo();
    final dir = p.join(root.path, 'a');
    File(p.join(dir, 'Gambatte', 'Red.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('red');
    repo.racer = () => repo.pushAs('saves/retroarch/Gambatte/Blue.srm', 'blue');
    final r = await crossSync(
      repo: repo,
      maps: [
        SyncMap('saves/retroarch', dir, exts: const ['srm']),
      ],
      state: {},
      device: 'phone',
      backups: p.join(root.path, 'bk'),
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(r.sent, ['Gambatte/Red.srm']);
    expect(r.took, ['Gambatte/Blue.srm']);
    expect(
      repo.current.keys,
      containsAll([
        'saves/retroarch/Gambatte/Red.srm',
        'saves/retroarch/Gambatte/Blue.srm',
      ]),
    );
    expect(
      File(p.join(dir, 'Gambatte', 'Blue.srm')).readAsStringSync(),
      'blue',
    );
  });

  test('parts of the repo a device does not map are left alone', () async {
    final repo = FakeRepo()
      ..pushAs('saves/pcsx2/memcards/Mcd001.ps2', 'ps2 card')
      ..pushAs('docs/START-HERE.md', 'docs');
    final dir = p.join(root.path, 'a');
    final r = await crossSync(
      repo: repo,
      maps: [SyncMap('saves/retroarch', dir)],
      state: {},
      device: 'phone',
      backups: p.join(root.path, 'bk'),
    );
    expect(r.took, isEmpty);
    expect(Directory(dir).existsSync(), isFalse);
  });

  test('the XMB Frontend folder: layout, RetroArch settings, device', () {
    final f = XmbFolders(p.join(root.path, 'XMB Frontend'))..create();
    for (final d in [
      f.bios,
      f.raSaves,
      f.duckCards,
      f.pspSaves,
      f.dolphinGc,
      f.dolphinWii,
      f.pokeville,
    ]) {
      expect(Directory(d).existsSync(), isTrue, reason: d);
    }
    expect(f.maps.map((m) => m.repo), [
      'saves/retroarch',
      'saves/duckstation/memcards',
      'saves/ppsspp/SAVEDATA',
      'saves/dolphin/GC',
      'saves/dolphin/Wii/title',
      'pokeville',
    ]);
    // RetroArch's own lines stay; ours are set (and not doubled).
    File(f.raConfig).writeAsStringSync(
      'video_shader_enable = "true"\nsavefile_directory = "/old"\n',
    );
    writeRetroArchConfig(f);
    writeRetroArchConfig(f);
    final cfg = File(f.raConfig).readAsStringSync();
    expect(cfg, contains('video_shader_enable = "true"'));
    expect(cfg, contains('savefile_directory = "${f.raSaves}"'));
    expect('savefile_directory'.allMatches(cfg).length, 1);
    expect(cfg, contains('sort_savefiles_enable = "true"'));
    expect(cfg, contains('input_quit_gamepad_combo = "4"'));
    expect(deviceName('Retroid Retroid Pocket Classic'), 'retroid');
    expect(deviceName('samsung SM-S918U'), 'phone');
  });

  test('controller: syncs, keeps conflicts across runs, resolves', () async {
    final storage = AppStorage(Directory(p.join(root.path, 'app')));
    final repo = FakeRepo()..pushAs('saves/retroarch/mGBA/Emerald.srm', 'pc');
    final f = XmbFolders(p.join(root.path, 'XMB Frontend'))..create();
    File(p.join(f.raSaves, 'mGBA', 'Emerald.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('phone');
    final cs = CrossSaveController(storage, makeRepo: (_) => repo)
      ..folders = f
      ..model = 'Retroid Pocket Classic';
    expect(await cs.sync(), isNull); // no token yet: nothing happens
    expect(await cs.setToken('t'), isNull);
    final rep = (await cs.sync())!;
    expect(rep.conflicts.length, 1);
    final again = CrossSaveController(storage, makeRepo: (_) => repo)
      ..folders = f;
    await again.load();
    expect(again.token, 't');
    expect(again.conflicts.single.key, 'saves/retroarch/mGBA/Emerald.srm');
    await again.resolve(again.conflicts.single, keepThisDevice: true);
    // resolve() syncs by itself; wait for it.
    while (again.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await again.sync();
    expect(
      repo.blobs[repo.current['saves/retroarch/mGBA/Emerald.srm']]!,
      'phone'.codeUnits,
    );
    expect(again.conflicts, isEmpty);
    expect(repo.lastMessage, startsWith('phone: ')); // no model: a phone
  });

  test("Dolphin: the PC's GC cards and Wii saves, nothing else", () {
    const f = XmbFolders('/storage/emulated/0/XMB Frontend');
    final gc = f.maps.singleWhere((m) => m.repo == 'saves/dolphin/GC');
    final wii = f.maps.singleWhere((m) => m.repo == 'saves/dolphin/Wii/title');
    expect(
      gc.local,
      p.join('/storage/emulated/0/XMB Frontend', 'Saves', 'Dolphin', 'GC'),
    );
    expect(wii.local, p.join(f.dolphin, 'Wii', 'title'));
    // GCI folder cards in every region, as the repo has them.
    expect(gc.takes('USA/Card A/01-GC6E-pokemon_colosseum.gci'), isTrue);
    expect(gc.takes('USA/Card A/01-GXXE-PokemonXD.gci'), isTrue);
    expect(gc.takes('EUR/Card B/01-GZLP-zelda.GCI'), isTrue);
    expect(gc.takes('JAP/Card A/8P-GALJ-smash.gci'), isTrue);
    // Whole-card files too; SRAM.raw is settings.
    expect(gc.takes('MemoryCardA.USA.raw'), isTrue);
    expect(gc.takes('SRAM.raw'), isFalse);
    expect(gc.takes('USA/SRAM.raw'), isFalse);
    // Not saves, and never our own temp files or conflict copies.
    expect(gc.takes('USA/Card A/desktop.ini'), isFalse);
    expect(gc.takes('USA/Card A/a.gci.xs-new'), isFalse);
    expect(gc.takes('USA/Card A/a.from-repo-20261126-101010.gci'), isFalse);
    expect(gc.takes('USA/Card A/notes.txt'), isFalse);
    // Wii: each title's save folder; not system titles or channel content.
    expect(wii.takes('00010002/48414341/data/NigaoeCh.dat'), isTrue);
    expect(wii.takes('00010000/52534245/data/banner.bin'), isTrue);
    expect(wii.takes('00000001/00000002/data/setting.txt'), isFalse);
    expect(wii.takes('00010001/48414241/content/00000001.app'), isFalse);
  });

  test('Dolphin: the repo\'s GCI cards arrive in the region folders', () async {
    final repo = FakeRepo()
      ..pushAs('saves/dolphin/GC/USA/Card A/01-GXXE-PokemonXD.gci', 'xd')
      ..pushAs('saves/dolphin/GC/SRAM.raw', 'settings')
      ..pushAs('saves/dolphin/Wii/title/00010002/48414341/data/a.dat', 'mii');
    final f = XmbFolders(p.join(root.path, 'XMB Frontend'))..create();
    final rep = await crossSync(
      repo: repo,
      maps: f.maps,
      state: {},
      device: 'retroid',
      backups: f.backups,
    );
    expect(
      rep.took,
      unorderedEquals([
        'USA/Card A/01-GXXE-PokemonXD.gci',
        '00010002/48414341/data/a.dat',
      ]),
    );
    expect(
      File(p.join(f.dolphinGc, 'USA', 'Card A', '01-GXXE-PokemonXD.gci'))
          .readAsStringSync(),
      'xd',
    );
    expect(File(p.join(f.dolphinGc, 'SRAM.raw')).existsSync(), isFalse);
  });

  test('a map limited to some files syncs only those, both ways', () async {
    final m = SyncMap(
      'saves/retroarch',
      p.join(root.path, 'ra'),
      exts: const ['srm'],
    ).limitedTo({'Gambatte/Red.srm'});
    expect(m.takes('Gambatte/Red.srm'), isTrue);
    expect(m.takes('Gambatte/Tetris.srm'), isFalse);
    expect(m.takes('Gambatte/Red.srm.box-new'), isFalse);
    expect(m.exts, ['srm']);
  });

  test('controller: only + files sync Pokéville and the named saves', () async {
    final storage = AppStorage(Directory(p.join(root.path, 'app')));
    final repo = FakeRepo()
      ..pushAs('saves/retroarch/Gambatte/Red.srm', 'pc red')
      ..pushAs('saves/retroarch/Gambatte/Tetris.srm', 'pc tetris')
      ..pushAs('saves/duckstation/memcards/A_1.mcd', 'card');
    final f = XmbFolders(p.join(root.path, 'XMB Frontend'))..create();
    void local(String rel, String text) =>
        File(p.joinAll([f.raSaves, ...rel.split('/')]))
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
    local('mGBA/Emerald.srm', 'phone emerald');
    local('mGBA/Zelda.srm', 'phone zelda');
    File(p.join(f.pokeville, 'box.json')).writeAsStringSync('{}');
    var asked = 0;
    final cs =
        CrossSaveController(
            storage,
            makeRepo: (_) => repo,
            only: const ['pokeville', 'saves/retroarch'],
            files: {
              'saves/retroarch': () async {
                asked++;
                return {'Gambatte/Red.srm', 'mGBA/Emerald.srm'};
              },
            },
          )
          ..folders = f
          ..token = 't';
    final rep = (await cs.sync())!;
    expect(asked, 1);
    expect(rep.took, ['Gambatte/Red.srm']);
    expect(rep.sent, unorderedEquals(['mGBA/Emerald.srm', 'box.json']));
    expect(
      File(p.join(f.raSaves, 'Gambatte', 'Tetris.srm')).existsSync(),
      isFalse,
    );
    expect(repo.current.containsKey('saves/retroarch/mGBA/Zelda.srm'), isFalse);
    expect(Directory(f.duckCards).listSync(), isEmpty);
  });
}
