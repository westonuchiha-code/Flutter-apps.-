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
      'saves', // the rest of saves/: download-only copies
    ]);
    expect(f.maps.last.downloadOnly, isTrue);
    expect(f.maps.where((m) => m.downloadOnly).length, 1);
    expect(Directory(f.pcsx2Cards).existsSync(), isTrue);
    expect(Directory(f.rpcs3Saves).existsSync(), isTrue);
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

  // ---- data-loss review ------------------------------------------------------

  Future<SyncReport> one(
    SaveRepo repo,
    String dir,
    Map<String, String> st, {
    String backups = 'bk',
    bool takes = true,
    bool Function()? stopTakes,
  }) => crossSync(
    repo: repo,
    maps: [
      SyncMap('saves/retroarch', dir, exts: const ['srm']),
    ],
    state: st,
    device: 'phone',
    backups: p.join(root.path, backups),
    takes: takes,
    stopTakes: stopTakes,
  );

  /// Every file under the test folder: path → contents and time.
  Map<String, String> disk() => {
    for (final e in root.listSync(recursive: true))
      if (e is File) e.path: '${e.readAsStringSync()}@${e.lastModifiedSync()}',
  };

  // ---- send-only (saves are only replaced when a game is opened) ----------

  test('send-only never writes here, even when the repo is newer', () async {
    final repo = FakeRepo();
    final dir = p.join(root.path, 'a');
    final crystal = File(p.join(dir, 'Gambatte', 'Crystal.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('phone v1');
    final st = <String, String>{};
    await one(repo, dir, st); // v1 sent: what was last synced
    repo
      ..pushAs('saves/retroarch/Gambatte/Crystal.srm', 'pc v2')
      ..pushAs('saves/retroarch/Gambatte/Gold.srm', 'pc gold'); // new here
    // Something this device saved meanwhile.
    File(p.join(dir, 'Gambatte', 'Red.srm')).writeAsStringSync('phone red');
    final before = disk();
    final was = {...st};
    final r = await one(repo, dir, st, takes: false);
    expect(disk(), before); // not one file written, made or replaced
    expect(Directory(p.join(root.path, 'bk')).existsSync(), isFalse);
    expect(r.took, isEmpty);
    expect(r.sent, ['Gambatte/Red.srm']);
    expect(
      repo.current['saves/retroarch/Gambatte/Red.srm'],
      blobSha('phone red'.codeUnits),
    );
    expect(r.waiting.toSet(), {'Gambatte/Crystal.srm', 'Gambatte/Gold.srm'});
    expect(r.summary, contains('2 newer saves waiting'));
    // The would-be takes were not recorded as synced...
    for (final k in [
      'saves/retroarch/Gambatte/Crystal.srm',
      'saves/retroarch/Gambatte/Gold.srm',
    ]) {
      expect(st[k], was[k]);
    }
    // ...so another send-only sync leaves them waiting too,
    final again = await one(repo, dir, st, takes: false);
    expect(again.sent, isEmpty);
    expect(again.waiting.length, 2);
    expect(crystal.readAsStringSync(), 'phone v1');
    // and the next full sync (a game opens) takes them.
    final full = await one(repo, dir, st);
    expect(full.took.toSet(), {'Gambatte/Crystal.srm', 'Gambatte/Gold.srm'});
    expect(full.waiting, isEmpty);
    expect(crystal.readAsStringSync(), 'pc v2');
    expect(
      File(p.join(dir, 'Gambatte', 'Gold.srm')).readAsStringSync(),
      'pc gold',
    );
  });

  test('send-only reports conflicts the same way, writing nothing', () async {
    final repo = FakeRepo();
    final dir = p.join(root.path, 'a');
    final save = File(p.join(dir, 'mGBA', 'Emerald.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('phone');
    repo.pushAs('saves/retroarch/mGBA/Emerald.srm', 'pc');
    final st = <String, String>{};
    final before = disk();
    final r = await one(repo, dir, st, takes: false);
    expect(disk(), before); // no conflict copy either
    expect(r.sent, isEmpty);
    expect(r.waiting, isEmpty);
    final c = r.conflicts.single;
    expect(c.key, 'saves/retroarch/mGBA/Emerald.srm');
    expect(c.repoSha, blobSha('pc'.codeUnits));
    expect(c.copy, '');
    expect(r.summary, contains('changed on both sides: Emerald'));
    // A full sync leaves the copy; a send-only one after it points at it.
    final full = await one(repo, dir, st);
    final copy = full.conflicts.single.copy;
    expect(File(copy).readAsStringSync(), 'pc');
    final later = await one(repo, dir, st, takes: false);
    expect(later.conflicts.single.copy, copy);
    expect(save.readAsStringSync(), 'phone');
    // The emulator writing back what a take replaced is still caught.
    final st2 = <String, String>{};
    final dir2 = p.join(root.path, 'b');
    final crystal = File(p.join(dir2, 'Gambatte', 'Crystal.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('v1');
    await one(repo, dir2, st2);
    repo.pushAs('saves/retroarch/Gambatte/Crystal.srm', 'pc v2');
    await one(repo, dir2, st2); // took v2
    crystal.writeAsStringSync('v1'); // stale emulator writes v1 back
    final stale = await one(repo, dir2, st2, takes: false);
    expect(stale.sent, isEmpty);
    expect(stale.conflicts.single.key, 'saves/retroarch/Gambatte/Crystal.srm');
  });

  test('stopTakes: no save is replaced once it says stop', () async {
    final repo = _HookRepo();
    final dir = p.join(root.path, 'a');
    final save = File(p.join(dir, 'Gambatte', 'Crystal.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('v1');
    final st = <String, String>{};
    await one(repo, dir, st);
    repo.pushAs('saves/retroarch/Gambatte/Crystal.srm', 'pc v2');
    var stop = false;
    // The XMB gives up waiting (and starts the game) mid-download.
    repo.onBlob = () => stop = true;
    final r = await one(repo, dir, st, stopTakes: () => stop);
    expect(save.readAsStringSync(), 'v1');
    expect(r.took, isEmpty);
    expect(r.waiting, ['Gambatte/Crystal.srm']);
    expect(r.ok, isTrue);
    expect(
      Directory(p.join(dir, 'Gambatte'))
          .listSync()
          .map((e) => p.basename(e.path)),
      ['Crystal.srm'],
    );
    repo.onBlob = null;
    expect((await one(repo, dir, st)).took, ['Gambatte/Crystal.srm']);
    expect(save.readAsStringSync(), 'pc v2');
  });

  test(
    'controller: sendOnly, then a conflict without a copy resolved',
    () async {
      final storage = AppStorage(Directory(p.join(root.path, 'app')));
      final repo = FakeRepo()
        ..pushAs('saves/retroarch/mGBA/Emerald.srm', 'pc')
        ..pushAs('saves/retroarch/mGBA/Ruby.srm', 'pc ruby');
      final f = XmbFolders(p.join(root.path, 'XMB Frontend'))..create();
      final emerald = File(p.join(f.raSaves, 'mGBA', 'Emerald.srm'))
        ..createSync(recursive: true)
        ..writeAsStringSync('phone');
      final cs = CrossSaveController(storage, makeRepo: (_) => repo)
        ..folders = f;
      expect(await cs.setToken('t'), isNull);
      final rep = (await cs.sendOnly())!;
      expect(rep.waiting, ['mGBA/Ruby.srm']);
      expect(File(p.join(f.raSaves, 'mGBA', 'Ruby.srm')).existsSync(), isFalse);
      expect(cs.conflicts.single.copy, '');
      expect(cs.lastSummary, contains('1 newer save waiting'));
      await cs.resolve(cs.conflicts.single, keepThisDevice: false);
      await cs.whenIdle(); // resolve() sends by itself; it takes nothing
      expect(emerald.readAsStringSync(), 'pc');
      expect(File(p.join(f.raSaves, 'mGBA', 'Ruby.srm')).existsSync(), isFalse);
      expect(cs.conflicts, isEmpty);
      final full = (await cs.sync())!;
      expect(full.took, ['mGBA/Ruby.srm']);
    },
  );

  test(
    'a save changed while the repo copy downloads is not overwritten',
    () async {
      final repo = _HookRepo();
      final dir = p.join(root.path, 'a');
      final save = File(p.join(dir, 'Gambatte', 'Crystal.srm'))
        ..createSync(recursive: true)
        ..writeAsStringSync('v1');
      final st = <String, String>{};
      await one(repo, dir, st); // sent: v1 is what was last synced
      repo.pushAs('saves/retroarch/Gambatte/Crystal.srm', 'pc v2');
      // The game (or the other app on this phone) saves while the sync is
      // downloading the PC's copy.
      repo.onBlob = () => save.writeAsStringSync('phone v3, just saved');
      final r = await one(repo, dir, st);
      expect(save.readAsStringSync(), 'phone v3, just saved');
      expect(r.took, isEmpty);
      expect(r.ok, isFalse);
      // ...and the next sync calls it what it is: changed on both sides.
      repo.onBlob = null;
      final again = await one(repo, dir, st);
      expect(again.conflicts.length, 1);
      expect(save.readAsStringSync(), 'phone v3, just saved');
    },
  );

  test('a cut-off download never becomes the conflict copy', () async {
    final repo = _HookRepo();
    final dir = p.join(root.path, 'a');
    final save = File(p.join(dir, 'mGBA', 'Emerald.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('phone');
    repo.pushAs('saves/retroarch/mGBA/Emerald.srm', 'the whole pc save');
    repo.cut = true;
    final st = <String, String>{};
    final r = await one(repo, dir, st);
    expect(r.conflicts, isEmpty);
    expect(r.ok, isFalse);
    expect(
      Directory(p.join(dir, 'mGBA')).listSync().map((e) => p.basename(e.path)),
      ['Emerald.srm'],
    );
    // A copy that isn't the repo's any more is never swapped in.
    repo.cut = false;
    final good = await one(repo, dir, st);
    final c = good.conflicts.single;
    File(c.copy).writeAsStringSync('the whole');
    await expectLater(
      keepOther(c, st, p.join(root.path, 'bk'), DateTime(2026)),
      throwsA(isA<FileSystemException>()),
    );
    expect(save.readAsStringSync(), 'phone');
  });

  test(
    "an emulator writing its old copy back is a conflict, not sent",
    () async {
      final repo = FakeRepo();
      final dir = p.join(root.path, 'a');
      final save = File(p.join(dir, 'Gambatte', 'Crystal.srm'))
        ..createSync(recursive: true)
        ..writeAsStringSync('phone v1');
      final st = <String, String>{};
      await one(repo, dir, st);
      repo.pushAs('saves/retroarch/Gambatte/Crystal.srm', 'pc v2');
      expect((await one(repo, dir, st)).took, ['Gambatte/Crystal.srm']);
      // RetroArch was still open (Home, not quit) and writes its copy back.
      save.writeAsStringSync('phone v1');
      final r = await one(repo, dir, st);
      expect(r.sent, isEmpty);
      expect(
        repo.current['saves/retroarch/Gambatte/Crystal.srm'],
        blobSha('pc v2'.codeUnits),
      );
      expect(r.conflicts.length, 1);
      // The player says the phone's is the one: then it goes.
      await keepLocal(r.conflicts.single, st, p.join(root.path, 'bk'));
      expect((await one(repo, dir, st)).sent, ['Gambatte/Crystal.srm']);
      // A real new save after a take is sent as usual.
      repo.pushAs('saves/retroarch/Gambatte/Crystal.srm', 'pc v4');
      expect((await one(repo, dir, st)).took, ['Gambatte/Crystal.srm']);
      save.writeAsStringSync('phone v5');
      expect((await one(repo, dir, st)).sent, ['Gambatte/Crystal.srm']);
    },
  );

  test(
    'a save named differently only by case is not sent as a second one',
    () async {
      final repo = FakeRepo()
        ..pushAs('saves/retroarch/Gambatte/Pokemon Red.srm', 'pc red');
      final dir = p.join(root.path, 'a');
      File(p.join(dir, 'Gambatte', 'pokemon red.srm'))
        ..createSync(recursive: true)
        ..writeAsStringSync('phone red');
      final r = await one(repo, dir, {});
      expect(r.sent, isEmpty);
      expect(r.ok, isFalse);
      expect(
        repo.current.keys.where((k) => k.toLowerCase().contains('pokemon red')),
        ['saves/retroarch/Gambatte/Pokemon Red.srm'],
      );
    },
  );

  test("the save manager's temp files are never synced", () {
    const m = SyncMap('saves/ppsspp/SAVEDATA', 'x');
    expect(m.takes('ULUS10000/DATA.BIN.xmb-new'), isFalse);
    expect(m.takes('ULUS10000/DATA.BIN.xmb-old'), isFalse);
    expect(m.takes('ULUS10000/DATA.BIN'), isTrue);
  });

  test('a push race does not list a conflict twice', () async {
    final repo = FakeRepo();
    final dir = p.join(root.path, 'a');
    File(p.join(dir, 'Gambatte', 'Red.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('phone red');
    File(p.join(dir, 'Gambatte', 'Blue.srm'))
      ..createSync(recursive: true)
      ..writeAsStringSync('phone blue');
    repo.pushAs('saves/retroarch/Gambatte/Blue.srm', 'pc blue');
    repo.racer = () => repo.pushAs('saves/retroarch/Gambatte/Gold.srm', 'g');
    final r = await one(repo, dir, {});
    expect(r.sent, ['Gambatte/Red.srm']);
    expect(r.conflicts.length, 1);
  });

  // ---- download-only copies (the PC's PS2/PS3/N64/Switch saves) -----------

  Future<SyncReport> copies(
    SaveRepo repo,
    XmbFolders f,
    Map<String, String> st, {
    bool takes = true,
  }) => crossSync(
    repo: repo,
    maps: f.maps,
    state: st,
    device: 'phone',
    backups: f.backups,
    takes: takes,
  );

  test('the PC\'s other saves arrive as copies, under Saves/', () async {
    final f = XmbFolders(p.join(root.path, 'XMB Frontend'))..create();
    final repo = FakeRepo()
      ..pushAs('saves/pcsx2/memcards/Mcd001.ps2', 'ps2 card')
      ..pushAs('saves/rpcs3/savedata/BLUS30968/PARAM.SFO', 'sfo')
      ..pushAs('saves/rpcs3/savedata/BLUS30968/E_SLOT_1', 'slot')
      ..pushAs('saves/rmg/Game/Zelda-1234.eep', 'n64')
      ..pushAs('saves/switch/user/0100ABC/main', 'switch')
      ..pushAs('saves/retroarch/Gambatte/Red.srm', 'red');
    final st = <String, String>{};
    final r = await copies(repo, f, st);
    expect(r.ok, isTrue, reason: r.error);
    String read(List<String> parts) =>
        File(p.joinAll([f.root, 'Saves', ...parts])).readAsStringSync();
    expect(read(['PCSX2', 'memcards', 'Mcd001.ps2']), 'ps2 card');
    expect(File(p.join(f.pcsx2Cards, 'Mcd001.ps2')).existsSync(), isTrue);
    expect(read(['RPCS3', 'savedata', 'BLUS30968', 'PARAM.SFO']), 'sfo');
    expect(read(['RPCS3', 'savedata', 'BLUS30968', 'E_SLOT_1']), 'slot');
    expect(read(['RMG', 'Game', 'Zelda-1234.eep']), 'n64');
    expect(read(['Switch', 'user', '0100ABC', 'main']), 'switch');
    // The two-way maps are as they were: RetroArch's comes down once.
    expect(read(['RetroArch', 'Gambatte', 'Red.srm']), 'red');
    expect(r.took.where((t) => t.endsWith('Red.srm')).length, 1);
    // A folder the repo gets later comes down too, without a new map.
    repo.pushAs('saves/xenia/content/0000/save.bin', 'x360');
    repo.pushAs('saves/newemu/cards/a.card', 'new');
    final again = await copies(repo, f, st);
    expect(again.took.toSet(), {
      'xenia/content/0000/save.bin',
      'newemu/cards/a.card',
    });
    expect(read(['Xenia', 'content', '0000', 'save.bin']), 'x360');
    expect(read(['newemu', 'cards', 'a.card']), 'new');
    expect((await copies(repo, f, st)).took, isEmpty);
  });

  test('copies are never sent: local edits and new files stay here', () async {
    final f = XmbFolders(p.join(root.path, 'XMB Frontend'))..create();
    final repo = FakeRepo()
      ..pushAs('saves/pcsx2/memcards/Mcd001.ps2', 'pc card');
    final st = <String, String>{};
    await copies(repo, f, st);
    final card = File(p.join(f.pcsx2Cards, 'Mcd001.ps2'));
    final made = File(p.join(f.pcsx2Cards, 'Mine.ps2'))
      ..writeAsStringSync('made here');
    final ps3 = File(p.join(f.rpcs3Saves, 'NEW00000', 'PARAM.SFO'))
      ..createSync(recursive: true)
      ..writeAsStringSync('new ps3');
    card.writeAsStringSync('changed here');
    final before = repo.branch;
    final r = await copies(repo, f, st, takes: false);
    expect(r.sent, isEmpty);
    expect(r.conflicts, isEmpty);
    expect(repo.branch, before); // no commit at all
    expect(made.readAsStringSync(), 'made here');
    expect(ps3.readAsStringSync(), 'new ps3');
    expect(card.readAsStringSync(), 'changed here'); // send-only: no take
    expect(r.waiting, ['pcsx2/memcards/Mcd001.ps2']);
    final full = await copies(repo, f, st);
    expect(full.sent, isEmpty);
    expect(full.conflicts, isEmpty);
    expect(repo.branch, before);
    expect(made.readAsStringSync(), 'made here'); // only here: left alone
  });

  test('a changed copy is backed up and the PC\'s put back', () async {
    final f = XmbFolders(p.join(root.path, 'XMB Frontend'))..create();
    final repo = FakeRepo()
      ..pushAs('saves/rpcs3/savedata/BLUS30968/E_SLOT_1', 'pc v1');
    final st = <String, String>{};
    await copies(repo, f, st);
    final slot = File(p.join(f.rpcs3Saves, 'BLUS30968', 'E_SLOT_1'));
    slot.writeAsStringSync('phone edit');
    final r = await copies(repo, f, st);
    expect(r.took, ['rpcs3/savedata/BLUS30968/E_SLOT_1']);
    expect(r.conflicts, isEmpty);
    expect(slot.readAsStringSync(), 'pc v1');
    final backups = [
      for (final e in Directory(f.backups).listSync(recursive: true))
        if (e is File) e,
    ];
    expect(backups.single.readAsStringSync(), 'phone edit');
    expect(backups.single.path, endsWith('E_SLOT_1'));
    // Changed on both sides (or never synced before): still the PC's.
    slot.writeAsStringSync('phone again');
    repo.pushAs('saves/rpcs3/savedata/BLUS30968/E_SLOT_1', 'pc v2');
    final both = await copies(repo, f, st);
    expect(both.conflicts, isEmpty);
    expect(both.sent, isEmpty);
    expect(slot.readAsStringSync(), 'pc v2');
    final fresh = <String, String>{};
    slot.writeAsStringSync('before any sync');
    expect((await copies(repo, f, fresh)).conflicts, isEmpty);
    expect(slot.readAsStringSync(), 'pc v2');
  });

  test('send-only writes nothing for copies, even new ones', () async {
    final f = XmbFolders(p.join(root.path, 'XMB Frontend'))..create();
    final repo = FakeRepo()
      ..pushAs('saves/pcsx2/memcards/Mcd001.ps2', 'pc card')
      ..pushAs('saves/switch/user/01/main', 'sw');
    final before = disk();
    final r = await copies(repo, f, {}, takes: false);
    expect(disk(), before);
    expect(r.waiting.toSet(), {
      'pcsx2/memcards/Mcd001.ps2',
      'switch/user/01/main',
    });
  });

  test('the copies map leaves the two-way folders to their own maps', () {
    final f = XmbFolders(p.join(root.path, 'XMB Frontend'));
    final m = f.maps.last;
    expect(m.takes('retroarch/Gambatte/Red.srm'), isFalse);
    expect(m.takes('RetroArch/Gambatte/Red.state'), isFalse);
    expect(m.takes('dolphin/GC/USA/Card A/x.gci'), isFalse);
    expect(m.takes('dolphin/Wii/title/00000001/x'), isFalse);
    expect(m.takes('ppsspp/SAVEDATA/ULUS/DATA.BIN'), isFalse);
    expect(m.takes('pcsx2/memcards/Mcd001.ps2'), isTrue);
    expect(m.takes('rpcs3/trophy/NPWR0/TROPUSR.DAT'), isTrue);
    expect(
      m.localPath('pcsx2/memcards/Mcd001.ps2'),
      p.join(f.root, 'Saves', 'PCSX2', 'memcards', 'Mcd001.ps2'),
    );
    expect(m.limitedTo({'a'}).downloadOnly, isTrue);
  });
}

/// A [FakeRepo] whose downloads can be cut short or run code meanwhile.
class _HookRepo extends FakeRepo {
  void Function()? onBlob;
  bool cut = false;

  @override
  Future<Uint8List> blob(String sha) async {
    onBlob?.call();
    final b = await super.blob(sha);
    return cut ? Uint8List.sublistView(b, 0, b.length ~/ 2) : b;
  }
}
