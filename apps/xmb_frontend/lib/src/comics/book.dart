/// One comic or manga: its pages in reading order and which way it reads.
/// Ported from the PC XMB Frontend's ComicBook.gd: a folder of images, a
/// zip-family file (.cbz / .zip / .epub) or a tar (.cbt) read page by page
/// as shown (big omnibus files open at once), or a PDF (drawn page by page
/// by pdfrx; see pdf_book.dart). RAR / 7z come later (Android side).
///
/// Reading direction: a ComicInfo.xml inside the book
/// (`<Manga>YesAndRightToLeft</Manga>`) decides; else the library's guess.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

const imageExts = {'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'};
const zipExts = {'cbz', 'zip', 'epub'};
const tarExts = {'cbt', 'tar'};
const laterExts = {'cbr', 'rar', 'cb7', '7z'};

String _ext(String path) =>
    p.extension(path).toLowerCase().replaceFirst('.', '');

bool isBookFile(String path) {
  final e = _ext(path);
  return zipExts.contains(e) ||
      tarExts.contains(e) ||
      laterExts.contains(e) ||
      e == 'pdf';
}

bool isImageName(String name) {
  final base = name.split('/').last;
  return imageExts.contains(_ext(name)) &&
      !base.startsWith('.') &&
      !name.contains('__MACOSX');
}

/// Natural order: "page2" before "page10" (numbers compared as numbers),
/// case ignored; folders compare part by part.
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final ma = re.allMatches(a.toLowerCase()).toList();
  final mb = re.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < ma.length && i < mb.length; i++) {
    final x = ma[i].group(0)!, y = mb[i].group(0)!;
    final nx = ma[i].group(1) != null, ny = mb[i].group(1) != null;
    int c;
    if (nx && ny) {
      c = BigInt.parse(x).compareTo(BigInt.parse(y));
      if (c == 0) c = x.length.compareTo(y.length);
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  return ma.length.compareTo(mb.length);
}

List<String> naturalSorted(Iterable<String> names) =>
    names.toList()..sort(naturalCompare);

/// 1 right to left, 0 left to right, -1 it doesn't say.
int mangaFromInfo(String info) {
  final v = infoField(info, 'Manga').toLowerCase();
  if (v == 'yesandrighttoleft') return 1;
  if (v == 'no' || v == 'yes') return v == 'no' ? 0 : -1;
  return -1;
}

String infoField(String info, String field) {
  final m = RegExp('<$field>([^<]*)</$field>').firstMatch(info);
  return m == null ? '' : m.group(1)!.trim();
}

/// A page's picture: encoded (jpg/png/...) or raw BGRA (PDF).
class PageData {
  const PageData.encoded(this.bytes) : width = null, height = null;
  const PageData.bgra(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int? width, height;
  bool get raw => width != null;
}

abstract class ComicBook {
  ComicBook(this.path);
  final String path;
  late String title = FileSystemEntity.isDirectorySync(path)
      ? p.basename(path)
      : p.basenameWithoutExtension(path);

  /// 1 right to left, 0 left to right, -1 unknown (see [mangaFromInfo]).
  int manga = -1;
  int get pageCount;

  Future<PageData?> page(int i);
  void close() {}

  /// Opens [path] (null and [error] set if it can't).
  static ComicBook? open(String path, [List<String>? error]) {
    try {
      final e = _ext(path);
      ComicBook book;
      if (FileSystemEntity.isDirectorySync(path)) {
        book = FolderBook(path);
      } else if (zipExts.contains(e) || tarExts.contains(e)) {
        book = ArchiveBook(path, tar: tarExts.contains(e));
      } else if (laterExts.contains(e)) {
        error?.add('RAR and 7z comics (.cbr / .cb7) come in the next update');
        return null;
      } else {
        error?.add('Not a comic');
        return null;
      }
      if (book.pageCount == 0) {
        error?.add('No pages in it');
        return null;
      }
      return book;
    } catch (e) {
      error?.add("Couldn't open this file ($e)");
      return null;
    }
  }

  void _applyInfo(String info) {
    manga = mangaFromInfo(info);
    final t = infoField(info, 'Title');
    if (t.isNotEmpty) title = t;
  }
}

/// The images under a folder (sub-folders in order), as one book.
List<String> imagesUnder(String dir) {
  final out = <String>[];
  for (final e in Directory(dir).listSync(recursive: true)) {
    if (e is File) {
      final rel = p.relative(e.path, from: dir).replaceAll(r'\', '/');
      if (isImageName(rel)) out.add(rel);
    }
  }
  return [
    for (final r in naturalSorted(out)) p.joinAll([dir, ...r.split('/')]),
  ];
}

class FolderBook extends ComicBook {
  FolderBook(super.path) : pages = imagesUnder(path) {
    final info = File(p.join(path, 'ComicInfo.xml'));
    if (info.existsSync()) _applyInfo(info.readAsStringSync());
  }
  final List<String> pages;
  @override
  int get pageCount => pages.length;
  @override
  Future<PageData?> page(int i) async => i < 0 || i >= pages.length
      ? null
      : PageData.encoded(await File(pages[i]).readAsBytes());
}

/// A .cbz / .zip / .epub, or a .cbt / .tar: only the directory is read when
/// it opens; each page is read when it's shown.
class ArchiveBook extends ComicBook {
  ArchiveBook(super.path, {bool tar = false}) {
    _input = InputFileStream(path);
    _archive = tar
        ? TarDecoder().decodeStream(_input)
        : ZipDecoder().decodeStream(_input);
    final byName = <String, ArchiveFile>{};
    for (final f in _archive.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll(r'\', '/');
      if (isImageName(name)) {
        byName[name] = f;
      } else if (name.split('/').last.toLowerCase() == 'comicinfo.xml') {
        _applyInfo(
          utf8.decode(f.readBytes() ?? const [], allowMalformed: true),
        );
      }
    }
    _pages = [for (final n in naturalSorted(byName.keys)) byName[n]!];
  }
  late final InputFileStream _input;
  late final Archive _archive;
  late final List<ArchiveFile> _pages;

  @override
  int get pageCount => _pages.length;

  @override
  Future<PageData?> page(int i) async {
    if (i < 0 || i >= _pages.length) return null;
    final b = _pages[i].readBytes();
    return b == null ? null : PageData.encoded(b);
  }

  @override
  void close() {
    _input.closeSync();
  }
}
