/// PDF comics, drawn page by page with pdfrx (Google's PDFium), as the PC
/// notes suggest for Android. Pages are drawn about 2200 pixels tall (wide
/// spreads capped), sharp enough to zoom into.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'book.dart';
import 'native_book.dart';

class PdfBook extends ComicBook {
  PdfBook._(super.path, this._doc);
  final PdfDocument _doc;

  static const pageHeight = 2200;

  static Future<PdfBook> load(String path) async {
    await pdfrxFlutterInitialize();
    return PdfBook._(path, await PdfDocument.openFile(path));
  }

  @override
  int get pageCount => _doc.pages.length;

  @override
  Future<PageData?> page(int i) async {
    if (i < 0 || i >= _doc.pages.length) return null;
    final pg = _doc.pages[i];
    final scale = math.min(pageHeight / pg.height, pageHeight * 1.5 / pg.width);
    final w = (pg.width * scale).round(), h = (pg.height * scale).round();
    final img = await pg.render(
      width: w,
      height: h,
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
      backgroundColor: 0xFFFFFFFF,
    );
    if (img == null) return null;
    final data = PageData.bgra(
      Uint8List.fromList(img.pixels),
      img.width,
      img.height,
    );
    img.dispose();
    return data;
  }

  @override
  void close() {
    _doc.dispose();
  }
}

/// Opens any comic (PDFs need a moment); null and [error] set if it can't.
Future<ComicBook?> openComic(String path, [List<String>? error]) async {
  if (path.toLowerCase().endsWith('.pdf')) {
    try {
      final b = await PdfBook.load(path);
      if (b.pageCount == 0) {
        error?.add('This PDF has no pages');
        b.close();
        return null;
      }
      return b;
    } catch (e) {
      error?.add("Couldn't read this PDF ($e)");
      return null;
    }
  }
  final e = path.toLowerCase().split('.').last;
  if (laterExts.contains(e)) {
    final kind = archiveKind(path);
    if (kind == 'zip') return ComicBook.open(path, error, true);
    try {
      final b = await NativeArchiveBook.load(path);
      if (b.pageCount == 0) {
        error?.add('No pages in it');
        return null;
      }
      return b;
    } catch (e) {
      error?.add(
        '$e'.contains('rar5')
            ? 'This .cbr is RAR 5, which the reader can\'t unpack yet'
            : "Couldn't unpack this file ($e)",
      );
      return null;
    }
  }
  return ComicBook.open(path, error);
}
