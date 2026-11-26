// Every page and dialog at the PC's 1920×1080, the Retroid Pocket
// Classic's ~450×390 dp and a phone's 390×844, written to build/shots/
// to look at. Real saves when SAVE_SAMPLES names a folder of memory cards
// (copied to a temp folder first: the samples are never written to), else
// made-up ones.
//
//   SAVE_SAMPLES=/path/to/cards flutter test test/screens_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:save_manager/src/art/art.dart';
import 'package:save_manager/src/controller.dart';
import 'package:save_manager/src/flow.dart';
import 'package:save_manager/src/state.dart';
import 'package:save_manager/src/ui/access_page.dart';
import 'package:save_manager/src/ui/screen.dart';

import 'screen_fixtures.dart';

const _font = 'Inter';

Future<void> _loadFonts() async {
  final l = FontLoader(_font);
  for (final w in ['Regular', 'Bold', 'Black']) {
    final f = File('/usr/share/fonts/opentype/inter/Inter-$w.otf');
    if (f.existsSync()) {
      l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await l.load();
}

const _sizes = {
  'pc': (Size(1920, 1080), 1.0, true),
  'retroid': (Size(1240 / 2.75, 1080 / 2.75), 2.75, true),
  'phone': (Size(390, 844), 3.0, false),
};

void main() {
  late Directory temp;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('save_manager_shots');
    final samples = Platform.environment['SAVE_SAMPLES'] ?? '';
    if (samples.isNotEmpty && Directory(samples).existsSync()) {
      copyTree(samples, p.join(temp.path, 'cards'));
    } else {
      makeCards(temp.path);
    }
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  testWidgets('screens', (tester) async {
    await tester.runAsync(_loadFonts);
    Look.fontFamily = _font;
    final c = SaveManagerController(testConfig(temp.path), runner: runNow);
    c.open();
    await c.settled();
    final st = c.state;
    await tester.runAsync(() async {
      await ArtImages.preload(st.allSaves, st.cards);
      for (var i = 0; i < 8; i++) {
        await ArtImages.load(PaintSplash.pixels(i));
      }
    });
    // a couple of favorites, and a PS2 save with a 3D icon to stand on
    final ps2 = st.saves.indexWhere((s) => s.icons[0] != null);
    final start = ps2 >= 0 ? ps2 : 0;
    for (final i in [start + 1, start + 3]) {
      if (i < st.saves.length) {
        c.selectSave(i);
        c.toggleFavorite();
      }
    }
    c.selectSave(start);
    c.clearNotice();
    final out = Directory('build/shots')..createSync(recursive: true);

    void back() {
      c.flow.cancel(); // Customize puts the card's look back
      c.flow.close();
      c.asking = null;
      for (var i = 0; i < 4 && st.mode != Mode.list; i++) {
        c.cancel();
      }
      st.cardI = -1;
      st.button = -1;
      st.clearSelection();
      c.selectSave(start);
      c.clearNotice();
    }

    final shots = <String, void Function()>{
      'list': () {},
      'options': c.toggleOptions,
      'opened': c.confirm,
      'copy': () {
        c.selectListButton(0);
        c.confirm();
      },
      'delete': () {
        c.confirm();
        c.selectPageButton(3);
        c.confirm();
      },
      'card': () {
        c.selectCard(st.column().indexOf(st.current()!.card!));
        c.confirm();
      },
      'customize': () {
        c.selectCard(st.column().indexOf(st.current()!.card!));
        c.confirm();
        c.selectPageButton(0);
        c.confirm();
        c.step(1, 0);
        c.step(0, 1);
      },
      'pick': () {
        c.flow.begin('format', st.cards, [], st.current());
        c.clearNotice();
      },
      'closed': () {
        c.asking = ClosedQuestion(
          const FlowJob('copy'),
          'RetroArch and DuckStation',
        );
      },
      'working': () {
        c.flow.begin('back_up_all', st.cards, [], null);
      },
      'select': () {
        st.startSelecting();
        c.selectSave(start);
        c.mark();
        c.selectSave(start + 2);
        c.mark();
      },
    };

    for (final MapEntry(key: size, value: (dp, dpr, hints)) in _sizes.entries) {
      setView(tester, dp, dpr: dpr);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(fontFamily: _font),
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: const Key('shot'),
              child: DefaultTextStyle(
                style: const TextStyle(fontFamily: _font, color: Colors.white),
                child: SaveManagerScreen(
                  controller: c,
                  showHints: hints,
                  actions: [
                    IconButton(
                      onPressed: () {},
                      color: Look.soft,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      for (final MapEntry(key: name, value: setUp) in shots.entries) {
        back();
        setUp();
        c.showNotice(name == 'list' ? 'Sorted: newest first' : '');
        if (name != 'list') c.clearNotice();
        for (var i = 0; i < 24; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
        final b = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('shot')),
        );
        await tester.runAsync(() async {
          final img = await b.toImage(pixelRatio: dpr > 1 ? 2 : 1);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File(p.join(out.path, 'screen_${name}_$size.png'))
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      back();
      // Android without all-files access
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RepaintBoundary(
              key: const Key('shot'),
              child: AccessPage(onAllow: () {}, onCheck: () {}),
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('shot')),
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: dpr > 1 ? 2 : 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File(p.join(out.path, 'screen_access_$size.png'))
            .writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
    c.dispose();
  });
}
