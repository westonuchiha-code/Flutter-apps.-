// Screenshots of the comic reader (look check) on a made-up comic, at the
// Retroid Pocket Classic's size and a phone's.
//   flutter test tool/comic_shot_test.dart --dart-define=OUT=<dir>
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xmb_frontend/src/comics/book.dart';
import 'package:xmb_frontend/src/ui/comic_reader.dart';

const _lines = [
  ['The diner on the', 'moon never closes.'],
  ['Coffee?', ''],
  ['Black. Like', 'the sky out there.'],
  ['Suit yourself.', ''],
];

/// A page: three panels with painted "art" and speech balloons.
Future<List<int>> _page(int n) async {
  const w = 1200.0, h = 1800.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()..color = const Color(0xFFF8F6F0),
  );
  final panels = [
    const Rect.fromLTWH(40, 40, 1120, 760),
    const Rect.fromLTWH(40, 840, 540, 920),
    const Rect.fromLTWH(620, 840, 540, 920),
  ];
  final r = math.Random(n);
  for (final (i, p) in panels.indexed) {
    c.drawRect(
      p,
      Paint()
        ..shader = ui.Gradient.linear(p.topLeft, p.bottomRight, [
          Color.fromARGB(
            255,
            30 + r.nextInt(60),
            40 + r.nextInt(80),
            90 + r.nextInt(100),
          ),
          Color.fromARGB(
            255,
            120 + r.nextInt(100),
            60 + r.nextInt(80),
            40 + r.nextInt(60),
          ),
        ]),
    );
    // Some shapes (a moon, a counter, a figure).
    c.drawCircle(
      p.topRight + Offset(-p.width * 0.2, p.height * 0.25),
      p.width * 0.08,
      Paint()..color = const Color(0xFFF0E6B0),
    );
    c.drawRect(
      Rect.fromLTWH(
        p.left,
        p.bottom - p.height * 0.25,
        p.width,
        p.height * 0.25,
      ),
      Paint()..color = const Color(0xFF3A2A20),
    );
    c.drawOval(
      Rect.fromCenter(
        center: p.bottomCenter + Offset(0, -p.height * 0.42),
        width: p.width * 0.18,
        height: p.height * 0.32,
      ),
      Paint()..color = const Color(0xFF20222A),
    );
    c.drawRect(
      p,
      Paint()
        ..color = const Color(0xFF111111)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    // A balloon with lettering.
    final text = _lines[(n * 3 + i) % _lines.length];
    final bw = i == 0 ? 420.0 : 330.0;
    final b = Rect.fromLTWH(p.left + 40, p.top + 40, bw, 150);
    c.drawOval(b, Paint()..color = Colors.white);
    c.drawOval(
      b,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: text.where((t) => t.isNotEmpty).join('\n'),
        style: const TextStyle(
          color: Colors.black,
          fontSize: 34,
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bw - 60);
    tp.paint(c, b.center - Offset(tp.width / 2, tp.height / 2));
  }
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final (name, size, dpr, keys) in [
    (
      'comic_retroid_page',
      const Size(1240, 1080),
      2.75,
      <LogicalKeyboardKey>[],
    ),
    (
      'comic_retroid_panel',
      const Size(1240, 1080),
      2.75,
      [LogicalKeyboardKey.gameButtonA],
    ),
    (
      'comic_retroid_panel2',
      const Size(1240, 1080),
      2.75,
      [LogicalKeyboardKey.gameButtonA, LogicalKeyboardKey.arrowRight],
    ),
    (
      'comic_retroid_balloon',
      const Size(1240, 1080),
      2.75,
      [LogicalKeyboardKey.gameButtonA, LogicalKeyboardKey.gameButtonX],
    ),
    ('comic_phone_page', const Size(1080, 2340), 2.75, <LogicalKeyboardKey>[]),
    (
      'comic_phone_manga',
      const Size(1080, 2340),
      2.75,
      [LogicalKeyboardKey.gameButtonStart, LogicalKeyboardKey.gameButtonA],
    ),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final book = (await tester.runAsync(() async {
        final l = FontLoader('Roboto');
        for (final w in ['Regular', 'SemiBold']) {
          l.addFont(
            Future.value(
              ByteData.sublistView(
                File('/usr/share/fonts/opentype/inter/Inter-$w.otf')
                    .readAsBytesSync(),
              ),
            ),
          );
        }
        await l.load();
        final a = Archive();
        for (var i = 0; i < 3; i++) {
          a.add(ArchiveFile.bytes('page${i + 1}.png', await _page(i)));
        }
        final dir = Directory.systemTemp.createTempSync('comic_shot');
        final f = File('${dir.path}/Moon Diner.cbz')
          ..writeAsBytesSync(ZipEncoder().encode(a));
        return ComicBook.open(f.path)!;
      }))!;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('s'),
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            home: ComicReader(
              book: book,
              startPage: 0,
              rtl: false,
              onPlace: (_, _) {},
              onDirection: (_) {},
            ),
          ),
        ),
      );
      // Let the page decode and the panel / balloon finders run.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (final k in keys) {
        await tester.sendKeyEvent(k);
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('s')),
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
