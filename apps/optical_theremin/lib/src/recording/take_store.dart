import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'take.dart';

/// Where recordings are kept.
abstract class TakeStore {
  Future<List<Take>> list();
  Future<void> save(Take take);
  Future<void> delete(String id);
}

/// Stores each take as a JSON file in [directory].
class FileTakeStore implements TakeStore {
  FileTakeStore(this.directory);

  final Directory directory;

  File _file(String id) => File(p.join(directory.path, '$id.json'));

  @override
  Future<List<Take>> list() async {
    if (!await directory.exists()) return [];
    final takes = <Take>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        takes.add(
          Take.fromJson(
            (jsonDecode(await entity.readAsString()) as Map)
                .cast<String, Object?>(),
          ),
        );
      } catch (_) {
        // Skip unreadable files rather than failing the whole list.
      }
    }
    takes.sort((a, b) => b.created.compareTo(a.created));
    return takes;
  }

  @override
  Future<void> save(Take take) async {
    await directory.create(recursive: true);
    final file = _file(take.id);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(take.toJson()));
    await temp.rename(file.path);
  }

  @override
  Future<void> delete(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
  }
}

/// In-memory store (tests, or when no storage directory is available).
class MemoryTakeStore implements TakeStore {
  final Map<String, Take> takes = {};

  @override
  Future<List<Take>> list() async =>
      takes.values.toList()..sort((a, b) => b.created.compareTo(a.created));

  @override
  Future<void> save(Take take) async => takes[take.id] = take;

  @override
  Future<void> delete(String id) async => takes.remove(id);
}
