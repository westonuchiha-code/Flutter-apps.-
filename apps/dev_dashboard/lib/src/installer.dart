import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'github.dart';

/// The release file for the platform this is running on.
FileKind get currentFileKind => Platform.isAndroid
    ? FileKind.android
    : Platform.isWindows
    ? FileKind.windows
    : FileKind.linux;

/// Downloads release files and hands APKs to Android's installer.
class Installer {
  Installer({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _channel = MethodChannel('dev_dashboard/install');

  Future<Directory> _targetDir() async {
    if (Platform.isAndroid) {
      // Matches the FileProvider "cache-path apk/" entry.
      return Directory(p.join((await getTemporaryDirectory()).path, 'apk'));
    }
    final dl = await getDownloadsDirectory();
    return dl ?? await getApplicationDocumentsDirectory();
  }

  /// Downloads [file], reporting progress 0..1.
  Future<File> download(
    ReleaseFile file, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _targetDir();
    await dir.create(recursive: true);
    final out = File(p.join(dir.path, file.name));
    final tmp = File('${out.path}.part');
    final res = await _http.send(http.Request('GET', Uri.parse(file.url)));
    if (res.statusCode != 200) {
      throw HttpException('Download failed (${res.statusCode})');
    }
    final total = res.contentLength ?? file.size;
    var got = 0;
    final sink = tmp.openWrite();
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
    } finally {
      await sink.close();
    }
    if (await out.exists()) await out.delete();
    return tmp.rename(out.path);
  }

  /// Android: opens the installer. Returns false if Android first needs the
  /// "install unknown apps" permission (its settings page is opened).
  Future<bool> installApk(File apk) async {
    final r = await _channel.invokeMethod<String>('installApk', {
      'path': apk.path,
    });
    return r == 'started';
  }

  /// Desktop: shows the downloaded file in the file manager.
  Future<void> reveal(File file) async {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', file.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [file.parent.path]);
    }
  }
}
