// A sheet of every art widget, written to build/shots/ to compare with the
// PC's screenshots by eye. Real saves when SAVE_SAMPLES names a folder of
// memory cards (read only), else made-up ones.
//
//   SAVE_SAMPLES=/path/to/cards flutter test test/art_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';
import 'package:save_manager/src/art/art.dart';

import 'art_fixtures.dart';

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

({List<MemoryCard> cards, List<CardSave> saves}) _data() {
  final dir = Platform.environment['SAVE_SAMPLES'] ?? '';
  if (dir.isNotEmpty && Directory(dir).existsSync()) {
    final got = MemoryCards.readAll([dir]);
    if (got.saves.isNotEmpty) {
      // A mix: 3D PS2 icons first, then the other consoles.
      final ps2 = [
        for (final s in got.saves)
          if (s.icons[0] != null) s,
      ];
      final seen = <String>{};
      final rest = <CardSave>[];
      for (final s in got.saves) {
        if (s.icons[0] == null && seen.add('${s.system}:${s.displayName()}')) {
          rest.add(s);
        }
      }
      rest.sort(
        (a, b) =>
            CardSystems.rank(a.system).compareTo(CardSystems.rank(b.system)),
      );
      final picks = <CardSave>[...ps2.take(7)];
      // Round-robin the other consoles so each shows up.
      final by = <String, List<CardSave>>{};
      for (final s in rest) {
        (by[s.system] ??= []).add(s);
      }
      var i = 0;
      while (picks.length < 15 && by.values.any((l) => l.length > i)) {
        for (final l in by.values) {
          if (l.length > i && picks.length < 15) picks.add(l[i]);
        }
        i++;
      }
      picks.add(fakePs3Save());
      return (cards: got.cards, saves: picks);
    }
  }
  return (
    cards: [fakeCard('PS2'), fakeCard('PS1'), fakeCard('DC'), fakeCard('GC')],
    saves: [
      fakePs2Save(favorite: true),
      fakeFramesSave('PS1'),
      fakeFramesSave('DC', name: 'Hop DC'),
      fakeFramesSave('GC', name: 'Hop GC'),
      fakePs3Save(),
      for (final s in ['N64', 'SATURN', 'NEO GEO'])
        CardSave()
          ..system = s
          ..setId('X$s')
          ..frames.add(CardPictures.standIn(s, s)),
    ],
  );
}

Widget _label(String s, {double size = 15, Color color = Colors.white}) => Text(
  s,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  textAlign: TextAlign.center,
  style: TextStyle(fontFamily: _font, fontSize: size, color: color),
);

Widget _cardRow(MemoryCard c, bool selected, {CardSave? save}) => Container(
  width: 300,
  height: 110,
  margin: const EdgeInsets.only(bottom: 14),
  padding: const EdgeInsets.fromLTRB(13, 14, 13, 10),
  decoration: BoxDecoration(
    color: Look.panel,
    border: Border.all(color: selected ? Look.yellow : Look.edge, width: 3),
  ),
  child: Row(
    children: [
      CardArt(c, width: 62),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.name.isEmpty ? c.system : c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: _font,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
            Text(
              c.freeText(),
              style: const TextStyle(
                fontFamily: _font,
                fontSize: 14,
                color: Look.soft,
              ),
            ),
            const SizedBox(height: 8),
            BlockBar(c, save: save, height: 12),
          ],
        ),
      ),
    ],
  ),
);

Widget _sheet(List<MemoryCard> cards, List<CardSave> saves) {
  final grid = saves.take(15).toList();
  for (final s in grid) {
    debugPrint('DBG ${s.system} ${s.id} ${s.frames.length} ${[for (final f in s.frames) '${f.w}x${f.h} ${f.rgba.where((v) => v != 0).length}']}');
  }
  final looks = [
    for (final (i, (_, v)) in CardLooks.palette.indexed)
      if (i % 2 == 0 || v.contains('/'))
        fakeCard(
          CardSystems.order[i % CardSystems.order.length],
          color: v.isEmpty
              ? 0
              : 0xFF000000 | int.parse(v.split('/')[0], radix: 16),
          finish: v.contains('/') ? v.split('/')[1] : '',
          sticker: i == 2 ? fakeSticker() : null,
        ),
  ];
  return MemoryBackdrop(
    child: Stack(
      children: [
        const Positioned(
          left: 16,
          top: 10,
          child: PaintTitle('MEMORY CARDS', width: 330, height: 96),
        ),
        Positioned(
          left: 16,
          top: 120,
          child: Column(
            children: [
              for (final (i, c) in cards.take(5).indexed)
                _cardRow(
                  c,
                  i == 1,
                  save: i == 1 && saves.isNotEmpty ? saves.first : null,
                ),
            ],
          ),
        ),
        Positioned(
          left: 340,
          top: 110,
          width: 860,
          child: Wrap(
            children: [
              for (final (i, s) in grid.indexed)
                SizedBox(
                  width: 172,
                  height: 168,
                  child: Column(
                    children: [
                      if (i == 0 || s.favorite)
                        FavoriteSparkle(
                          size: 132,
                          child: SaveIcon(s, size: 132),
                        )
                      else
                        SaveIcon(s, size: 132, selected: i == 7),
                      _label(
                        s.cellName(),
                        color: i == 7 ? Look.yellow : Colors.white,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          left: 350,
          top: 860,
          child: Row(
            children: [
              for (final (i, l) in [
                'COPY',
                'MOVE',
                'BACK UP',
                'DELETE',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: PaintButton(
                    l,
                    seed: i + 1,
                    selected: i == 2,
                    width: 196,
                    height: 92,
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          left: 1220,
          top: 20,
          width: 370,
          child: Column(
            children: [
              _label('Opened PS2 save (list / copy / delete)', size: 14),
              SaveIcon(
                saves.firstWhere(
                  (s) => s.icons[0] != null,
                  orElse: () => saves.first,
                ),
                size: 250,
                selected: true,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final k in [0, 1, 2])
                    SaveIcon(
                      saves.firstWhere(
                        (s) => s.icons[0] != null,
                        orElse: () => saves.first,
                      ),
                      kind: k,
                      size: 96,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SaveIcon(saves.last, size: 200, wide: true, animate: false),
              _label('Card looks', size: 14),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [for (final c in looks) CardArt(c, width: 48)],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PaintButton('SMALL', seed: 5, width: 110, height: 40),
                  const SizedBox(width: 10),
                  PaintButton(
                    'OFF',
                    seed: 6,
                    width: 110,
                    height: 40,
                    enabled: false,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _opened(CardSave s) {
  final t = MemoryBackdrop.tintOf(s);
  return MemoryBackdrop(
    tint: t?.tint,
    tintAmount: t?.amount ?? 0,
    child: Stack(
      children: [
        Positioned(
          left: 40,
          top: 30,
          child: OutlinedText(s.displayName(), size: 44, color: Look.yellow),
        ),
        Positioned(
          left: 60,
          top: 120,
          child: SaveIcon(s, size: 520, selected: true),
        ),
        Positioned(
          left: 60,
          top: 640,
          child: Row(
            children: [
              for (final k in [0, 1, 2])
                Container(
                  width: 150,
                  height: 150,
                  margin: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Look.panel,
                    border: Border.all(color: Look.edge, width: 2),
                  ),
                  child: SaveIcon(s, kind: k, size: 146),
                ),
            ],
          ),
        ),
        Positioned(
          left: 40,
          top: 840,
          child: Row(
            children: [
              for (final (i, l) in [
                'START GAME',
                'COPY',
                'BACK UP',
                'DELETE',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 30),
                  child: PaintButton(
                    l,
                    seed: i + 1,
                    selected: i == 0,
                    width: 340,
                    height: 100,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> _shoot(WidgetTester tester, String name, Widget page) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: _font, color: Colors.white),
        child: RepaintBoundary(key: const Key('sheet'), child: page),
      ),
    ),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 33));
  }
  final b = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('sheet')),
  );
  await tester.runAsync(() async {
    final img = await b.toImage();
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = Directory('build/shots')..createSync(recursive: true);
    File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('art sheet', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = (await tester.runAsync(() async {
      await _loadFonts();
      final d = _data();
      await ArtImages.preload(d.saves, d.cards);
      for (var i = 0; i < 7; i++) {
        await ArtImages.load(PaintSplash.pixels(i));
      }
      return d;
    }))!;
    Look.fontFamily = _font;
    await _shoot(tester, 'art_sheet', _sheet(data.cards, data.saves));
    final ps2 = data.saves.firstWhere(
      (s) => s.icons[0] != null,
      orElse: () => fakePs2Save(),
    );
    await tester.runAsync(() => ArtImages.preload([ps2]));
    tester.view.physicalSize = const Size(1600, 1000);
    await _shoot(tester, 'art_opened', _opened(ps2));
    // The Retroid Pocket Classic's ~450×390 dp.
    tester.view.physicalSize = const Size(1240, 1080);
    tester.view.devicePixelRatio = 2.75;
    await _shoot(
      tester,
      'art_small',
      MemoryBackdrop(
        child: Wrap(
          children: [
            const PaintTitle('MEMORY CARDS', width: 170, height: 48),
            for (final s in data.saves.take(8)) SaveIcon(s, size: 64),
            for (final c in data.cards.take(3)) ...[
              CardArt(c, width: 36),
              SizedBox(width: 100, child: BlockBar(c, height: 7)),
            ],
            const PaintButton('COPY', width: 110, height: 40, selected: true),
            const PaintButton('DELETE', seed: 4, width: 110, height: 40),
          ],
        ),
      ),
    );
  });
}
