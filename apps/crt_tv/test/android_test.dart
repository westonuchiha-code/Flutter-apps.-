// Android: controller buttons arriving as keys, the default TV folder and
// how folders are named, and the TV picking its folder by itself.
import 'dart:io';

import 'package:crt_tv/src/android_storage.dart';
import 'package:crt_tv/src/app_store.dart';
import 'package:crt_tv/src/folder_browser.dart';
import 'package:crt_tv/src/gamepad.dart';
import 'package:crt_tv/src/tv_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_player.dart';

KeyEvent press(LogicalKeyboardKey key, int ms) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.gameButtonA,
  logicalKey: key,
  timeStamp: Duration(milliseconds: ms),
);

KeyEvent held(LogicalKeyboardKey key, int ms) => KeyRepeatEvent(
  physicalKey: PhysicalKeyboardKey.gameButtonA,
  logicalKey: key,
  timeStamp: Duration(milliseconds: ms),
);

KeyEvent release(LogicalKeyboardKey key, int ms) => KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.gameButtonA,
  logicalKey: key,
  timeStamp: Duration(milliseconds: ms),
);

class FakeStorage extends AndroidStorage {
  FakeStorage(this.root, {this.access = true});

  final String root;
  bool access;

  @override
  Future<bool> hasAllFiles() async => access;

  @override
  Future<List<String>> storageRoots() async => [root];
}

void main() {
  group('controller buttons as keys', () {
    test('every button of the Retroid Pocket maps to its place', () {
      final keys = PadKeys(android: true);
      final expected = {
        LogicalKeyboardKey.gameButtonA: PadButton.south,
        LogicalKeyboardKey.gameButtonB: PadButton.east,
        LogicalKeyboardKey.gameButtonX: PadButton.west,
        LogicalKeyboardKey.gameButtonY: PadButton.north,
        LogicalKeyboardKey.gameButtonLeft1: PadButton.l1,
        LogicalKeyboardKey.gameButtonRight1: PadButton.r1,
        LogicalKeyboardKey.gameButtonLeft2: PadButton.l2,
        LogicalKeyboardKey.gameButtonRight2: PadButton.r2,
        LogicalKeyboardKey.gameButtonStart: PadButton.start,
        LogicalKeyboardKey.gameButtonSelect: PadButton.select,
        LogicalKeyboardKey.gameButtonThumbLeft: PadButton.l3,
        LogicalKeyboardKey.gameButtonThumbRight: PadButton.r3,
        LogicalKeyboardKey.arrowUp: PadButton.up,
        LogicalKeyboardKey.arrowDown: PadButton.down,
        LogicalKeyboardKey.arrowLeft: PadButton.left,
        LogicalKeyboardKey.arrowRight: PadButton.right,
        LogicalKeyboardKey.select: PadButton.south,
      };
      expected.forEach((key, button) {
        expect(keys.buttonFor(key), button, reason: key.debugName);
      });
      expect(keys.buttonFor(LogicalKeyboardKey.keyS), isNull);
      expect(keys.buttonFor(LogicalKeyboardKey.digit5), isNull);
    });

    test('on desktop the arrows stay keyboard keys', () {
      final keys = PadKeys(android: false);
      expect(keys.buttonFor(LogicalKeyboardKey.arrowUp), isNull);
      expect(keys.buttonFor(LogicalKeyboardKey.gameButtonA), PadButton.south);
    });

    test('a press fires once; releases and held buttons do not', () {
      final keys = PadKeys(android: true);
      const a = LogicalKeyboardKey.gameButtonA;
      expect(keys.read(press(a, 0)), (button: PadButton.south, fire: true));
      expect(keys.read(held(a, 600)), (button: PadButton.south, fire: false));
      expect(keys.read(release(a, 700)), (
        button: PadButton.south,
        fire: false,
      ));
      expect(keys.read(press(LogicalKeyboardKey.keyM, 800)), isNull);
    });

    test('a held d-pad repeats at the controller pace, not Android\'s', () {
      final keys = PadKeys(android: true);
      const up = LogicalKeyboardKey.arrowUp;
      final fired = <int>[];
      void at(KeyEvent e) {
        if (keys.read(e)!.fire) fired.add(e.timeStamp.inMilliseconds);
      }

      at(press(up, 0));
      // Android repeats every 50 ms after half a second.
      for (var ms = 500; ms <= 1200; ms += 50) {
        at(held(up, ms));
      }
      at(release(up, 1210));
      at(held(up, 1250)); // a stray repeat after letting go
      expect(fired, [0, 450 + 50, 750, 1000]);
    });
  });

  group('folders', () {
    test('the default TV folder sits in the XMB Frontend folder', () {
      expect(
        defaultTvFolder('/storage/emulated/0'),
        p.join('/storage/emulated/0', 'XMB Frontend', 'TV'),
      );
    });

    test('folders are named the way My Files names them', () {
      expect(
        myFilesPath('/storage/emulated/0/XMB Frontend/TV'),
        'Internal storage › XMB Frontend › TV',
      );
      expect(myFilesPath('/storage/emulated/0'), 'Internal storage');
      expect(myFilesPath('/storage/1A2B-3C4D/Movies'), 'SD card › Movies');
      expect(myFilesPath('/sdcard/TV'), 'Internal storage › TV');
      expect(myFilesPath('/data/local'), '/data/local');
      expect(
        myFilesPath('/mnt/x/TV/Channel 3', roots: ['/mnt/x', '/mnt/sd']),
        'Internal storage › TV › Channel 3',
      );
      expect(
        myFilesPath('/mnt/sd/TV', roots: ['/mnt/x', '/mnt/sd']),
        'SD card › TV',
      );
    });

    test('with access and no folder yet, the TV makes and uses its own', () {
      final root = Directory.systemTemp.createTempSync('crt_tv_root');
      addTearDown(() => root.deleteSync(recursive: true));
      final roots = [root.path];
      expect(startFolder(chosen: null, access: false, roots: roots), isNull);
      expect(
        startFolder(chosen: '/somewhere', access: true, roots: roots),
        isNull,
      );
      expect(startFolder(chosen: null, access: true, roots: const []), isNull);

      final dir = startFolder(chosen: null, access: true, roots: roots)!;
      expect(dir, defaultTvFolder(root.path));
      final guide = File(p.join(dir, howToFileName));
      expect(guide.readAsStringSync(), contains('Channel 3'));
      // A guide the owner edited is left alone.
      guide.writeAsStringSync('mine');
      expect(prepareTvFolder(dir), isTrue);
      expect(guide.readAsStringSync(), 'mine');
    });

    test(
      'browsing on Android starts in the TV folder; the top lists storage',
      () {
        final root = Directory.systemTemp.createTempSync('crt_tv_root');
        addTearDown(() => root.deleteSync(recursive: true));
        final roots = [root.path, '/no/sd/card'];
        final tv = defaultTvFolder(root.path);
        expect(browseStart(null, roots: roots, defaultFolder: tv), root.path);
        prepareTvFolder(tv);
        expect(browseStart(null, roots: roots, defaultFolder: tv), tv);
        final windows = Platform.isWindows;
        expect(parentFolder(root.path, windows: windows, roots: roots), '');
        expect(
          parentFolder(
            '${root.path}${p.separator}',
            windows: windows,
            roots: roots,
          ),
          '',
        );
        expect(parentFolder(tv, windows: windows, roots: roots), p.dirname(tv));
        expect(listFolders('', roots: roots), roots);
      },
    );
  });

  group('the TV on Android', () {
    Future<(TvController, FakeStorage, Directory)> makeTv({
      required bool access,
    }) async {
      final dir = Directory.systemTemp.createTempSync('crt_tv_android');
      final storage = FakeStorage(p.join(dir.path, 'storage'), access: access);
      Directory(storage.root).createSync();
      final store = AppStore.at(File(p.join(dir.path, 'tv_data.json')));
      store.settings.levelSound = false;
      final tv = await TvController.forTesting(
        store: store,
        player: FakePlayer.new,
        android: true,
        storage: storage,
      );
      return (tv, storage, dir);
    }

    test('first start with access: the TV folder is made and chosen', () async {
      final (tv, storage, dir) = await makeTv(access: true);
      addTearDown(() {
        tv.dispose();
        _tidy(dir);
      });
      final tvDir = defaultTvFolder(storage.root);
      expect(tv.settings.libraryPath, tvDir);
      expect(File(p.join(tvDir, howToFileName)).existsSync(), isTrue);
      expect(tv.folderLabel(tvDir), 'Internal storage › XMB Frontend › TV');
      expect(tv.permissionProblem, isNull);
    });

    test(
      'without access it waits, then sets up once access is given',
      () async {
        final (tv, storage, dir) = await makeTv(access: false);
        addTearDown(() {
          tv.dispose();
          _tidy(dir);
        });
        expect(tv.settings.libraryPath, isNull);
        expect(tv.allFilesAccess, isFalse);
        expect(tv.permissionProblem, isNotNull);

        storage.access = true; // given in Android's Settings, then back
        await tv.onResumed();
        expect(tv.allFilesAccess, isTrue);
        expect(tv.permissionProblem, isNull);
        expect(tv.settings.libraryPath, defaultTvFolder(storage.root));
        expect(tv.library, isNotNull);
      },
    );
  });
}

/// Windows won't delete a file something still has open (the settings
/// store can still be closing): a temp folder left behind is harmless.
void _tidy(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // left for the system to clear
  }
}
