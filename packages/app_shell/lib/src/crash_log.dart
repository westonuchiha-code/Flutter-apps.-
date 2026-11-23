import 'dart:convert';

import 'storage.dart';

/// One recorded error.
class CrashEntry {
  CrashEntry({
    required this.time,
    required this.error,
    required this.stack,
    this.context,
    this.fatal = false,
  });

  final DateTime time;
  final String error;
  final String stack;
  final String? context;
  final bool fatal;

  Map<String, Object?> toJson() => {
    'time': time.toIso8601String(),
    'error': error,
    'stack': stack,
    'context': context,
    'fatal': fatal,
  };

  factory CrashEntry.fromJson(Map<String, Object?> j) => CrashEntry(
    time: DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime(1970),
    error: j['error'] as String? ?? '',
    stack: j['stack'] as String? ?? '',
    context: j['context'] as String?,
    fatal: j['fatal'] == true,
  );
}

/// Keeps the most recent errors in `crashes.json` (the Dev Dashboard will
/// read these files from every app).
class CrashLog {
  CrashLog(
    this.storage, {
    this.maxEntries = 50,
    this.fileName = 'crashes.json',
  });

  final AppStorage storage;
  final int maxEntries;
  final String fileName;

  /// Called after the log changes (used to publish it to the Asset Locker).
  Future<void> Function(List<CrashEntry> entries)? onChanged;

  Future<List<CrashEntry>> entries() async {
    final json = await storage.readJson(fileName);
    if (json is! List) return [];
    return [
      for (final e in json)
        if (e is Map) CrashEntry.fromJson(e.cast<String, Object?>()),
    ];
  }

  Future<void> record(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) async {
    final list = await entries();
    list.add(
      CrashEntry(
        time: DateTime.now(),
        error: error.toString(),
        stack: (stack ?? StackTrace.current).toString(),
        context: context,
        fatal: fatal,
      ),
    );
    final trimmed = list.length > maxEntries
        ? list.sublist(list.length - maxEntries)
        : list;
    await storage.writeJson(fileName, [for (final e in trimmed) e.toJson()]);
    await _notify(trimmed);
  }

  Future<void> clear() async {
    await storage.delete(fileName);
    await _notify(const []);
  }

  Future<void> _notify(List<CrashEntry> list) async {
    try {
      await onChanged?.call(list);
    } catch (_) {
      // Publishing is best-effort; never fail while logging an error.
    }
  }

  /// Plain-text report for sharing.
  Future<String> report(String appName, String version) async {
    final b = StringBuffer('$appName $version — error report\n\n');
    for (final e in (await entries()).reversed) {
      b
        ..writeln(
          '[${e.time.toIso8601String()}]${e.fatal ? ' FATAL' : ''}'
          '${e.context == null ? '' : ' (${e.context})'}',
        )
        ..writeln(e.error)
        ..writeln(e.stack)
        ..writeln();
    }
    return b.toString();
  }

  static String encode(List<CrashEntry> e) =>
      jsonEncode([for (final x in e) x.toJson()]);
}
