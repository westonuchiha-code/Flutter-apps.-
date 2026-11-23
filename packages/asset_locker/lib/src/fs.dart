import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// One entry in a locker folder.
class FsEntry {
  const FsEntry(this.name, {required this.isDir, this.size = 0, this.modified});

  final String name;
  final bool isDir;
  final int size;
  final DateTime? modified;
}

/// File access inside the locker. Paths are relative, '/'-separated.
abstract class LockerFs {
  Future<List<FsEntry>> list(String path);
  Future<Uint8List?> read(String path);
  Future<void> write(String path, List<int> bytes);
  Future<bool> delete(String path);
}

/// Plain folder on disk (Windows, Linux, tests).
class IoLockerFs implements LockerFs {
  IoLockerFs(this.root);

  final Directory root;

  String _abs(String path) =>
      p.joinAll([root.path, ...path.split('/').where((s) => s.isNotEmpty)]);

  @override
  Future<List<FsEntry>> list(String path) async {
    final dir = Directory(_abs(path));
    if (!await dir.exists()) return const [];
    final out = <FsEntry>[];
    await for (final e in dir.list()) {
      final stat = await e.stat();
      out.add(
        FsEntry(
          p.basename(e.path),
          isDir: stat.type == FileSystemEntityType.directory,
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
    return out;
  }

  @override
  Future<Uint8List?> read(String path) async {
    final f = File(_abs(path));
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String path, List<int> bytes) async {
    final f = File(_abs(path));
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<bool> delete(String path) async {
    final f = File(_abs(path));
    if (!await f.exists()) return false;
    await f.delete();
    return true;
  }
}

const _channel = MethodChannel('asset_locker');

/// A folder the user picked through Android's folder picker.
class SafLockerFs implements LockerFs {
  SafLockerFs(this.treeUri, {this.prefix = ''});

  final String treeUri;

  /// Sub-folder inside the picked folder ('' = the picked folder itself).
  final String prefix;

  String _p(String path) => prefix.isEmpty ? path : '$prefix/$path';

  static Future<String?> pickFolder() =>
      _channel.invokeMethod<String>('pickFolder', {
        // Open the picker at Documents.
        'initial': 'content://com.android.externalstorage.documents/document/primary%3ADocuments',
      });

  static Future<bool> hasAccess(String uri) async =>
      await _channel.invokeMethod<bool>('hasAccess', {'uri': uri}) ?? false;

  @override
  Future<List<FsEntry>> list(String path) async {
    final raw =
        await _channel.invokeListMethod<Map<Object?, Object?>>('list', {
          'uri': treeUri,
          'path': _p(path),
        }) ??
        const [];
    return [
      for (final m in raw)
        FsEntry(
          m['name']! as String,
          isDir: m['isDir']! as bool,
          size: (m['size'] as int?) ?? 0,
          modified: m['modified'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(m['modified']! as int),
        ),
    ];
  }

  @override
  Future<Uint8List?> read(String path) => _channel.invokeMethod<Uint8List>(
    'read',
    {'uri': treeUri, 'path': _p(path)},
  );

  @override
  Future<void> write(String path, List<int> bytes) =>
      _channel.invokeMethod<bool>('write', {
        'uri': treeUri,
        'path': _p(path),
        'bytes': Uint8List.fromList(bytes),
      });

  @override
  Future<bool> delete(String path) async =>
      await _channel.invokeMethod<bool>('delete', {
        'uri': treeUri,
        'path': _p(path),
      }) ??
      false;
}
