import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xmb_frontend/src/comics/book.dart';
import 'package:xmb_frontend/src/comics/bubbles.dart';
import 'package:xmb_frontend/src/comics/library.dart';
import 'package:xmb_frontend/src/comics/native_book.dart';
import 'package:xmb_frontend/src/comics/pdf_book.dart';
import 'package:xmb_frontend/src/comics/panels.dart';

/// A white page with [rects] filled grey-dark (art), w×h.
Uint8List _page(
  int w,
  int h,
  List<(int, int, int, int)> rects, {
  int bg = 245,
}) {
  final lum = Uint8List(w * h)..fillRange(0, w * h, bg);
  for (final (x, y, rw, rh) in rects) {
    for (var j = y; j < y + rh; j++) {
      for (var i = x; i < x + rw; i++) {
        lum[j * w + i] = ((i * 7 + j * 13) % 90) + 40;
      }
    }
  }
  return lum;
}

void main() {
  test('natural order and ComicInfo', () {
    expect(naturalSorted(['p10.jpg', 'p2.jpg', 'P1.jpg', 'p02b.jpg']), [
      'P1.jpg',
      'p2.jpg',
      'p02b.jpg',
      'p10.jpg',
    ]);
    expect(naturalSorted(['ch10/1.png', 'ch2/1.png']), [
      'ch2/1.png',
      'ch10/1.png',
    ]);
    expect(mangaFromInfo('<Manga>YesAndRightToLeft</Manga>'), 1);
    expect(mangaFromInfo('<Manga>No</Manga>'), 0);
    expect(mangaFromInfo(''), -1);
    expect(infoField('<Title>Hi there</Title>', 'Title'), 'Hi there');
    expect(isImageName('__MACOSX/._p1.jpg'), isFalse);
    expect(isImageName('.hidden.png'), isFalse);
    expect(isImageName('a/p1.webp'), isTrue);
  });

  test('a CBZ opens page by page, in order, with its ComicInfo', () async {
    final dir = Directory.systemTemp.createTempSync('cbz');
    final a = Archive()
      ..add(ArchiveFile.bytes('p10.jpg', [10]))
      ..add(ArchiveFile.bytes('p2.jpg', [2]))
      ..add(ArchiveFile.bytes('p1.jpg', [1]))
      ..add(ArchiveFile.bytes('__MACOSX/._p1.jpg', [9]))
      ..add(
        ArchiveFile.string(
          'ComicInfo.xml',
          '<ComicInfo><Title>Moon Diner</Title><Manga>YesAndRightToLeft</Manga></ComicInfo>',
        ),
      );
    final file = File(p.join(dir.path, 'book.cbz'))
      ..writeAsBytesSync(ZipEncoder().encode(a));
    final book = ComicBook.open(file.path)!;
    expect(book.pageCount, 3);
    expect(book.title, 'Moon Diner');
    expect(book.manga, 1);
    expect((await book.page(0))!.bytes, [1]);
    expect((await book.page(2))!.bytes, [10]);
    book.close();
    final err = <String>[];
    expect(ComicBook.open(p.join(dir.path, 'x.cbr'), err), isNull);
    expect(err.single, contains('Android'));
    // A .cbr that is really a zip opens like one.
    final cbr = File(p.join(dir.path, 'really zip.cbr'))
      ..writeAsBytesSync(file.readAsBytesSync());
    expect(archiveKind(cbr.path), 'zip');
    final viaCbr = (await openComic(cbr.path))!;
    expect(viaCbr.pageCount, 3);
    viaCbr.close();
    File(p.join(dir.path, 'r.cbr')).writeAsBytesSync('Rar!\x1a\x07'.codeUnits);
    expect(archiveKind(p.join(dir.path, 'r.cbr')), 'rar');
    dir.deleteSync(recursive: true);
  });

  test('panels come out in reading order (and right to left for manga)', () {
    const w = 320, h = 480;
    // Two rows: a wide panel; then two side by side.
    final lum = _page(w, h, [
      (10, 10, 300, 200),
      (10, 230, 140, 240),
      (170, 230, 140, 240),
    ]);
    final ltr = findPanels(lum, w, h);
    expect(ltr, hasLength(3));
    expect(ltr[0].y, lessThan(ltr[1].y));
    expect(ltr[1].x, lessThan(ltr[2].x));
    final rtl = findPanels(lum, w, h, rtl: true);
    expect(rtl[1].x, greaterThan(rtl[2].x));
    // A page with no gutters: no panels.
    expect(findPanels(_page(w, h, [(0, 0, w, h)]), w, h), isEmpty);
  });

  test('lettering is found as a balloon', () {
    const w = 640, h = 900;
    final lum = Uint8List(w * h)..fillRange(0, w * h, 90); // dark art
    // A white balloon with three lines of "letters".
    for (var y = 100; y < 200; y++) {
      for (var x = 200; x < 440; x++) {
        lum[y * w + x] = 250;
      }
    }
    for (final ly in [120, 145, 170]) {
      for (var cx = 220; cx < 420; cx += 9) {
        for (var y = ly; y < ly + 12; y++) {
          for (var x = cx; x < cx + 2; x++) {
            lum[y * w + x] = 20;
          }
          if (y == ly || y == ly + 6) {
            for (var x = cx; x < cx + 6; x++) {
              lum[y * w + x] = 20;
            }
          }
        }
      }
    }
    final found = findBubbles(lum, w, h);
    expect(found, isNotEmpty);
    final b = found.first;
    expect(b.x * w, lessThan(225));
    expect((b.x + b.w) * w, greaterThan(415));
    expect(b.y * h, inInclusiveRange(80, 125));
  });

  test('the library: series folders, image folders, places and manga', () {
    final root = Directory.systemTemp.createTempSync('comics').path;
    File(p.join(root, 'One Shot.cbz')).writeAsBytesSync([0]);
    Directory(p.join(root, 'Moon Diner')).createSync();
    File(p.join(root, 'Moon Diner', 'Vol 10.cbz')).writeAsBytesSync([0]);
    File(p.join(root, 'Moon Diner', 'Vol 2.cbz')).writeAsBytesSync([0]);
    Directory(p.join(root, 'Loose pages')).createSync();
    File(p.join(root, 'Loose pages', '01.jpg')).writeAsBytesSync([0]);
    Directory(p.join(root, 'Manga', 'Ch 1')).createSync(recursive: true);
    File(p.join(root, 'Manga', 'Ch 1', '1.png')).writeAsBytesSync([0]);
    final shelf = scanComics(root);
    expect(shelf.books.map(p.basename), ['One Shot.cbz', 'Loose pages']);
    expect(shelf.series.keys, containsAll(['Moon Diner', 'Manga']));
    expect(shelf.series['Moon Diner']!.map(p.basename), [
      'Vol 2.cbz',
      'Vol 10.cbz',
    ]);
    final prog = ComicProgress();
    final vol2 = shelf.series['Moon Diner']!.first;
    expect(prog.status(root, vol2), 'New');
    prog.pages[ComicProgress.key(root, vol2)] = (page: 4, of: 20);
    expect(prog.status(root, vol2), 'Page 5 of 20');
    expect(ComicProgress.key(root, vol2), 'moon diner/vol 2.cbz');
    expect(prog.guessRtl(root, shelf.series['Manga']!.first), isTrue);
    expect(prog.guessRtl(root, vol2), isFalse);
    prog.rtl[ComicProgress.seriesKey(root, vol2)] = true;
    final back = ComicProgress(prog.toJson());
    expect(back.guessRtl(root, vol2), isTrue);
    expect(back.status(root, vol2), 'Page 5 of 20');
    Directory(root).deleteSync(recursive: true);
  });
}
