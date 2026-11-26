/// RAR (.cbr) and 7z (.cb7) comics, unpacked page by page on Android
/// (MainActivity's ComicArchives: junrar and Apache Commons Compress).
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'book.dart';

const _channel = MethodChannel('xmb/android');

class NativeArchiveBook extends ComicBook {
  NativeArchiveBook._(super.path, this._pages);
  final List<String> _pages;

  /// Lists the book; reads its ComicInfo.xml if it has one.
  static Future<NativeArchiveBook> load(String path) async {
    final names = [
      for (final n
          in await _channel.invokeListMethod<String>('comicList', {
                'path': path,
              }) ??
              const <String>[])
        n,
    ];
    final book = NativeArchiveBook._(
      path,
      naturalSorted(names.where(isImageName)),
    );
    final info = names.where(
      (n) => n.split('/').last.toLowerCase() == 'comicinfo.xml',
    );
    if (info.isNotEmpty) {
      try {
        final f = await _channel.invokeMethod<String>('comicPage', {
          'path': path,
          'name': info.first,
        });
        if (f != null) book._applyInfoText(await File(f).readAsString());
      } catch (_) {}
    }
    return book;
  }

  void _applyInfoText(String info) {
    manga = mangaFromInfo(info);
    final t = infoField(info, 'Title');
    if (t.isNotEmpty) title = t;
  }

  @override
  int get pageCount => _pages.length;

  @override
  Future<PageData?> page(int i) async {
    if (i < 0 || i >= _pages.length) return null;
    final f = await _channel.invokeMethod<String>('comicPage', {
      'path': path,
      'name': _pages[i],
    });
    return f == null ? null : PageData.encoded(await File(f).readAsBytes());
  }
}

/// What a file really is, from its first bytes (a .cbr is often a zip).
String archiveKind(String path) {
  try {
    final raf = File(path).openSync();
    final b = raf.readSync(6);
    raf.closeSync();
    if (b.length >= 2 && b[0] == 0x50 && b[1] == 0x4B) return 'zip';
    if (b.length >= 4 && String.fromCharCodes(b.sublist(0, 4)) == 'Rar!') {
      return 'rar';
    }
    if (b.length >= 6 &&
        b[0] == 0x37 &&
        b[1] == 0x7A &&
        b[2] == 0xBC &&
        b[3] == 0xAF) {
      return '7z';
    }
  } catch (_) {}
  return '';
}
