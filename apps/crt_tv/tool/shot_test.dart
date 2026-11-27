// Screenshots (look check) of every screen at three sizes: a 1080p TV, the
// Retroid Pocket Classic (1240×1080 at 2.75, ≈450×390 dp) and a phone held
// upright (1080×2340 at 2.625). The TV plays fake channels through a
// stand-in player (media_kit can't play in tests), with colour bars where
// the video would be.
//
//   flutter test tool/shot_test.dart --dart-define=OUT=/some/folder
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crt_tv/main.dart';
import 'package:crt_tv/src/android_storage.dart';
import 'package:crt_tv/src/app_store.dart';
import 'package:crt_tv/src/models.dart';
import 'package:crt_tv/src/tv_controller.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../test/fake_player.dart';

const sizes = [
  ('tv', Size(1920, 1080), 1.0),
  ('retroid', Size(1240, 1080), 2.75),
  ('phone', Size(1080, 2340), 2.625),
];

/// Android's answers, for a "device" whose internal storage is [root].
class FakeStorage extends AndroidStorage {
  const FakeStorage(this.root, {this.access = true});

  final String root;
  final bool access;

  @override
  Future<bool> hasAllFiles() async => access;

  @override
  Future<List<String>> storageRoots() async => [root];
}

/// A TV folder like the README's, in `<root>/XMB Frontend/TV`.
String makeLibrary(String root, Map<String, int> lengths) {
  final tv = defaultTvFolder(root);
  void video(String path, int seconds) {
    final f = File(p.join(tv, path))..createSync(recursive: true);
    lengths[f.path] = seconds * 1000;
  }

  for (var i = 1; i <= 3; i++) {
    video('Commercials/Cereal Ad $i.mp4', 30);
  }
  for (var e = 1; e <= 6; e++) {
    video('Channel 3 - Sitcoms/Season 1/Family Matters S01E0$e.mkv', 1320);
  }
  for (var e = 1; e <= 4; e++) {
    video('Channel 5 - Cartoons/Duck Tales S01E0$e.mp4', 1320);
  }
  video('Channel 5 - Cartoons/Commercials/Toy Ad.mp4', 30);
  video('Channel 8 - Movies/The Goonies (1985).mkv', 6840);
  video('Channel 8 - Movies/Back to the Future (1985).mkv', 6960);
  video('Channel Gojira/Godzilla vs Mothra (1964).avi', 5340);
  video('Channel Halloween [Oct]/Its the Great Pumpkin.mp4', 1500);
  Directory(p.join(tv, 'Channel 12 - Empty')).createSync();
  prepareTvFolder(tv);
  return tv;
}

class Shot {
  const Shot(
    this.name, {
    this.keys = const [],
    this.android = false,
    this.access = true,
    this.skin = SkinStyle.wood,
    this.tap = false,
  });

  final String name;

  /// Pressed in order once the TV is on.
  final List<LogicalKeyboardKey> keys;
  final bool android;
  final bool access;
  final SkinStyle skin;

  /// Tap the picture first (brings up the control bar).
  final bool tap;
}

const a = LogicalKeyboardKey.gameButtonA;
const down = LogicalKeyboardKey.arrowDown;

/// Start, then down to TV FOLDER.
const _toFolder = [
  LogicalKeyboardKey.gameButtonStart,
  down,
  down,
  down,
  down,
  down,
  down,
];

final shots = [
  const Shot('tv', tap: true),
  const Shot('tv_boombox', skin: SkinStyle.boombox),
  const Shot('tv_cyberpunk', skin: SkinStyle.cyberpunk),
  const Shot('tv_combo', skin: SkinStyle.combo),
  // The controller hints that come up when a pad is picked up (Android:
  // the Retroid's buttons arrive as keys).
  const Shot(
    'pad_hints',
    android: true,
    keys: [LogicalKeyboardKey.gameButtonLeft1],
  ),
  const Shot('menu', android: true, keys: [LogicalKeyboardKey.gameButtonStart]),
  const Shot(
    'guide',
    android: true,
    keys: [LogicalKeyboardKey.gameButtonRight1],
  ),
  const Shot(
    'themes',
    android: true,
    keys: [LogicalKeyboardKey.gameButtonSelect],
  ),
  // Menu > CONTROLS > CONTROLLER
  const Shot(
    'controls',
    android: true,
    keys: [
      LogicalKeyboardKey.gameButtonStart,
      down,
      down,
      down,
      down,
      a,
      down,
      a,
    ],
  ),
  // Menu > TV FOLDER
  const Shot('folder', android: true, keys: [..._toFolder, a]),
  // Menu > TV FOLDER > CHOOSE FOLDER (starts in the TV folder)
  const Shot('browse', android: true, keys: [..._toFolder, a, a]),
  // ... then UP ONE LEVEL three times: internal storage and SD cards.
  const Shot(
    'browse_top',
    android: true,
    keys: [..._toFolder, a, a, down, a, down, a, down, a],
  ),
  // First start on Android before "All files" access is given.
  const Shot('no_access', android: true, access: false),
];

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final shot in shots) {
    for (final (where, size, dpr) in sizes) {
      testWidgets(
        '${shot.name}_$where',
        (tester) => shoot(tester, out, '${shot.name}_$where', size, dpr, shot),
      );
    }
  }
}

Future<void> loadFonts() async {
  for (final (family, file) in [
    ('Roboto', '/usr/share/fonts/opentype/inter/Inter-Regular.otf'),
    ('monospace', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'),
    (
      'MaterialIcons',
      '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  ]) {
    if (!File(file).existsSync()) continue;
    final loader = FontLoader(family)
      ..addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    await loader.load();
  }
}

/// SMPTE-style colour bars: the stand-in for a playing video.
Widget colourBars(BuildContext context) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Expanded(
      flex: 3,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in [
            0xFFC0C0C0,
            0xFFC0C000,
            0xFF00C0C0,
            0xFF00C000,
            0xFFC000C0,
            0xFFC00000,
            0xFF0000C0,
          ])
            Expanded(child: ColoredBox(color: Color(c))),
        ],
      ),
    ),
    const Expanded(child: ColoredBox(color: Color(0xFF101030))),
  ],
);

Future<void> shoot(
  WidgetTester tester,
  String out,
  String name,
  Size size,
  double dpr,
  Shot shot,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final dir = Directory.systemTemp.createTempSync('crt_tv_shot');
  addTearDown(() => dir.deleteSync(recursive: true));

  final tv = (await tester.runAsync(() async {
    await loadFonts();
    final root = p.join(dir.path, 'storage');
    final store = AppStore.at(File(p.join(dir.path, 'tv_data.json')));
    final lengths = <String, int>{};
    final library = makeLibrary(root, lengths);
    store.durations.addAll(lengths);
    store.settings
      ..skin = shot.skin
      ..levelSound = false
      ..staticSound = false
      ..lastChannel = 3
      ..libraryPath = shot.access ? library : null;
    final tv = await TvController.forTesting(
      store: store,
      player: FakePlayer.new,
      android: shot.android,
      storage: FakeStorage(root, access: shot.access),
      pictureStandIn: colourBars,
    );
    // Wait for the channels and the first video.
    for (var i = 0; i < 200 && shot.access && tv.nowPlaying == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return tv;
  }))!;

  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('s'),
      child: CrtTvApp(controller: tv),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (shot.tap) {
    await tester.tapAt(tester.view.physicalSize.center(Offset.zero) / dpr);
    await tester.pump(const Duration(milliseconds: 300));
  }
  for (final key in shot.keys) {
    await tester.sendKeyEvent(key);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('s')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: dpr);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    tv.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  // Let the on-screen timers (channel number, hints) run out.
  await tester.pump(const Duration(seconds: 30));
}
