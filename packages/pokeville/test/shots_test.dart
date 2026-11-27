// Pokéville at the PC's 1920×1080, the Retroid Pocket Classic's ~450×390 dp
// and a phone's 390×844, written to build/shots/ to look at: the Box, holding
// a Pokémon, Check (status, moves), the Box Dex, the menu, and the "no
// Pokéville yet" page. The bundled fonts are loaded so text isn't the test
// font. Sprites come from a fake fetcher (coloured placeholders), never the
// network; with POKEVILLE_REAL_SPRITES=1 the real PokeAPI sprites are
// downloaded instead (into a temp folder), for the shots only:
//
//   POKEVILLE_REAL_SPRITES=1 flutter test test/shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pokeville/pokeville.dart';

import 'fixtures.dart';

Future<void> loadFonts() async {
  for (final (family, file) in [
    ('PixelifySans', 'PixelifySans.ttf'),
    ('DotGothic16', 'DotGothic16-Regular.ttf'),
  ]) {
    final bytes = File(p.join('assets', 'fonts', file)).readAsBytesSync();
    final l = FontLoader('packages/pokeville/$family')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await l.load();
  }
}

const sizes = {
  'pc': (Size(1920, 1080), 1.0),
  'retroid': (Size(1240 / 2.75, 1080 / 2.75), 2.75),
  'phone': (Size(390, 844), 3.0),
};

void main() {
  late Directory temp;
  final real = Platform.environment['POKEVILLE_REAL_SPRITES'] == '1';

  setUpAll(() => temp = Directory.systemTemp.createTempSync('pokeville_shots'));
  tearDownAll(() => temp.deleteSync(recursive: true));

  testWidgets('shots', (tester) async {
    await tester.runAsync(loadFonts);
    if (real) HttpOverrides.global = null; // flutter_test blocks the network
    final sprites = PokeSprites(
      p.join(temp.path, 'sprites'),
      fetcher: real ? httpFetcher() : fakeFetcher,
    );
    final out = Directory(p.join('build', 'shots', real ? 'real' : ''))
      ..createSync(recursive: true);

    Future<void> shoot(
      String name,
      Widget child,
      String size, {
      void Function()? last,
    }) async {
      final (dp, dpr) = sizes[size]!;
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = dp * dpr;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(key: const Key('shot'), child: child),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (last != null) {
        last();
        await tester.pump();
      }
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('shot')),
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: dpr > 1 ? 2 : 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File(p.join(out.path, '${name}_$size.png'))
            .writeAsBytesSync(png!.buffer.asUint8List());
      });
      expect(tester.takeException(), isNull);
    }

    for (final (label, more) in [('example', false), ('box', true)]) {
      final dir = makePokeville(p.join(temp.path, label), more: more);
      final c = PokevilleController(PokevilleFolder(dir, runner: runHere));
      await c.open();
      final want = <(int, bool)>{
        for (var b = 0; b < c.pageCount; b++)
          for (var i = 0; i < PokeBoxStore.slots; i++)
            if (c.pageMon(b, i) case final m? when !m.egg) (m.species, m.shiny),
        // the Box Dex page the shots show (121-180) and Meowth's (1-60)
        for (var sp = 1; sp <= 60; sp++) (sp, false),
        for (var sp = 121; sp <= 180; sp++) (sp, false),
      };
      await tester.runAsync(() => sprites.preload(want));

      Widget screen() => PokevilleScreen(
        dir,
        temp.path,
        controller: c,
        sprites: sprites,
        onLeave: () {},
      );

      void reset() {
        while (c.cancel()) {}
        c.goToPage(0);
        c.select(more ? 7 : 0);
        c.setTab(0);
        c.clearNotice();
      }

      final shots = <String, Future<void> Function()>{
        label: () async {},
        if (more) ...{
          'holding': () async {
            c.goToPage(1);
            c.select(1);
            await c.confirm(); // Guts
            c.goToPage(0);
            c.select(10);
          },
          'check': () async {
            c.goToPage(1);
            c.select(1);
            c.check();
          },
          'moves': () async {
            c.goToPage(1);
            c.select(1);
            c.check();
            c.step(1, 0);
          },
          'dex': () async {
            c.goToPage(1);
            c.select(1);
            c.check();
            c.setTab(2); // wide: the Dex is always beside Check
          },
          'menu': () async {
            c.menu();
          },
          'notice': () async {
            c.select(23); // the egg
            c.check();
            await c.confirm(); // "Eggs can't be renamed or hold items"
          },
          'edit': () async {
            c.select(0); // Meowth (the PC's example)
            c.check();
            await c.confirm();
          },
          'keyboard': () async {
            c.select(0);
            c.check();
            await c.confirm();
            await c.confirm();
            c.typeText('Ka');
            c.step(0, 2);
            c.step(5, 0);
          },
          'items': () async {
            c.select(0);
            c.check();
            await c.confirm();
            c.step(0, 1);
            await c.confirm();
            for (var i = 0; i < 4; i++) {
              c.step(0, 1);
            }
          },
          'banner': () async {
            c.select(0);
            c.step(0, -1);
          },
        },
      };
      for (final size in sizes.keys) {
        for (final MapEntry(key: name, value: setUp) in shots.entries) {
          reset();
          await setUp();
          await shoot(name, screen(), size);
        }
      }
      reset();
      c.dispose();
    }
    // part B: the Games list, a game's boxes, the question, the transfer
    {
      final root = p.join(temp.path, 'games');
      final saves = makeGames(root, more: true);
      final dir = p.join(root, 'pokeville');
      var now = DateTime(2026, 11, 26, 12);
      final c = PokevilleController(
        PokevilleFolder(dir, runner: runHere),
        games: PokeGames([saves]),
        guard: SaveGuard.ask(now: () => now),
      );
      await c.open();
      await tester.runAsync(
        () => sprites.preload([
          for (final sp in [1, 152, 252, 52, 117, 85]) ...[
            (sp, false),
            (sp, true),
          ],
          (130, true),
        ]),
      );
      Widget screen() => PokevilleScreen(
        dir,
        temp.path,
        controller: c,
        sprites: sprites,
        onLeave: () {},
      );
      int game(String name) =>
          c.gameSaves.indexWhere((g) => g.fileName == name);
      Future<void> reset() async {
        while (c.cancel()) {}
        await Future<void>.delayed(Duration.zero);
        c.skipTransfer();
        c.skipTransfer();
        await c.showSource(-1);
        c.goToPage(0);
        c.select(0);
        c.clearNotice();
        now = now.add(const Duration(minutes: 5)); // ask again
      }

      double? at;
      final shots = <String, Future<void> Function()>{
        'games': () async {
          c.menu();
          c.step(0, 2);
        },
        'gamebox': () async {
          await c.showSource(game(crystal));
          c.select(2);
        },
        'party': () async {
          await c.showSource(game(crystal));
          c.goToPage(0);
          c.select(1);
        },
        'gamekeyboard': () async {
          await c.showSource(game(crystal));
          c.goToPage(0);
          c.select(0);
          c.check();
          await c.confirm();
          await c.confirm();
          c.step(0, 2);
          c.step(-1, 0); // the apostrophe: Crystal can't write it
        },
        'gbabox': () async {
          await c.showSource(game(leaf));
          c.select(3);
        },
        'gameholding': () async {
          await c.showSource(game(crystal));
          c.select(1);
          await c.confirm();
          await c.showSource(-1);
          c.select(12);
        },
        'question': () async {
          await c.showSource(game(red));
          c.select(0);
          await c.confirm();
          await c.showSource(-1);
          c.select(3);
          await c.confirm();
        },
        'transfer': () async {
          await c.showSource(game(red));
          c.select(0);
          await c.confirm();
          await c.showSource(-1);
          c.select(3);
          await c.confirm();
          await c.answer(1);
          at = 2.9;
        },
        'transfer_end': () async {
          c.select(3);
          await c.confirm(); // the one just moved in
          await c.showSource(game(red));
          c.select(10);
          await c.confirm();
          await c.answer(1);
          at = 5.6;
        },
      };
      for (final size in sizes.keys) {
        for (final MapEntry(key: name, value: setUp) in shots.entries) {
          await tester.runAsync(reset);
          at = null;
          await tester.runAsync(setUp);
          final t = at;
          await shoot(
            name,
            screen(),
            size,
            last: t == null
                ? null
                : () {
                    c.transfer?.t = t;
                    c.transfer?.clock = t;
                  },
          );
          // let it finish (the save has changed already)
          for (var i = 0; i < 4; i++) {
            c.skipTransfer();
          }
        }
      }
      await tester.runAsync(reset);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
    // no box.json yet
    final empty = Directory(p.join(temp.path, 'empty'))..createSync();
    for (final size in sizes.keys) {
      await shoot(
        'nobox',
        PokevilleHome(empty.path, temp.path, onLeave: () {}),
        size,
      );
    }
    await tester.pumpWidget(const SizedBox());
    sprites.dispose();
  });
}
