/// The Comics row: every comic under the comics folder, one menu folder
/// per series folder, books in natural order, and where you're up to in
/// each. Also which series read right to left (manga). Ported from the PC's
/// ComicLibrary.gd; your place is keyed by the path inside the comics
/// folder (lower case, '/'), so it can follow you between devices later.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'book.dart';

class ComicShelf {
  const ComicShelf(this.books, this.series);

  /// Loose books (files, or folders of images).
  final List<String> books;

  /// Series folder name → its books.
  final Map<String, List<String>> series;
}

bool _isImageBook(String dir) {
  try {
    return Directory(dir)
        .listSync()
        .any((e) => e is File && isImageName(p.basename(e.path)));
  } catch (_) {
    return false;
  }
}

/// The books in a series folder: comic files, and sub-folders of images.
List<String> booksIn(String dir) {
  final out = <String>[];
  for (final e in Directory(dir).listSync()) {
    final name = p.basename(e.path);
    if (name.startsWith('.')) continue;
    if (e is File && isBookFile(e.path)) {
      out.add(e.path);
    } else if (e is Directory) {
      if (_isImageBook(e.path)) {
        out.add(e.path);
      } else {
        out.addAll(booksIn(e.path));
      }
    }
  }
  return naturalSorted(out);
}

ComicShelf scanComics(String dir) {
  final loose = <String>[];
  final series = <String, List<String>>{};
  final d = Directory(dir);
  if (!d.existsSync()) return ComicShelf(loose, series);
  final entries = d.listSync();
  for (final f in naturalSorted([
    for (final e in entries)
      if (e is File && isBookFile(e.path)) e.path,
  ])) {
    loose.add(f);
  }
  for (final sub in naturalSorted([
    for (final e in entries)
      if (e is Directory && !p.basename(e.path).startsWith('.')) e.path,
  ])) {
    final books = booksIn(sub);
    if (books.isNotEmpty) {
      series[p.basename(sub)] = books;
    } else if (_isImageBook(sub)) {
      loose.add(sub);
    }
  }
  return ComicShelf(loose, series);
}

/// Your place in every book, and the series you set to read right to left.
class ComicProgress {
  ComicProgress([Map<String, Object?>? json]) {
    final pg = json?['pages'];
    if (pg is Map) {
      pg.forEach((k, v) {
        if (v is Map) {
          pages['$k'] = (
            page: ((v['page'] as num?) ?? 0).toInt(),
            of: ((v['of'] as num?) ?? 0).toInt(),
          );
        }
      });
    }
    final r = json?['rtl'];
    if (r is Map) r.forEach((k, v) => rtl['$k'] = v == true);
  }

  final pages = <String, ({int page, int of})>{};
  final rtl = <String, bool>{};

  Map<String, Object?> toJson() => {
    'pages': {
      for (final e in pages.entries)
        e.key: {'page': e.value.page, 'of': e.value.of},
    },
    'rtl': rtl,
  };

  /// A book's key: its path inside [root], lower case, '/' separators.
  static String key(String root, String book) =>
      p.relative(book, from: root).replaceAll(r'\', '/').toLowerCase();

  static String seriesKey(String root, String book) =>
      p.dirname(key(root, book));

  /// Manga or not before the book's ComicInfo.xml has its say: your
  /// setting for the series, else the names ("manga", "[JP]", Japanese).
  bool guessRtl(String root, String book) {
    final s = seriesKey(root, book);
    if (rtl.containsKey(s)) return rtl[s]!;
    final name = book.toLowerCase();
    if (RegExp(
      r'manga|manhua|\[jp\]|\(jp\)|\braw\b|tankoubon|\bvol(ume)?\.?\s*\d+.*\bch',
    ).hasMatch(name)) {
      return true;
    }
    return RegExp(r'[぀-ヿ一-鿿]').hasMatch(book);
  }

  /// "New", "Page 3 of 24" or "Finished".
  String status(String root, String book) {
    final pl = pages[key(root, book)];
    if (pl == null) return 'New';
    return pl.of > 0 && pl.page + 1 >= pl.of
        ? 'Finished'
        : 'Page ${pl.page + 1} of ${pl.of}';
  }
}
