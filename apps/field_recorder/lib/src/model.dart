import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const sampleRateSetting = ChoiceSetting(
  key: 'sampleRate',
  title: 'Sample rate',
  defaultValue: '48000',
  choices: {'44100': '44.1 kHz', '48000': '48 kHz'},
  section: 'Recording',
);

const micSourceSetting = ChoiceSetting(
  key: 'micSource',
  title: 'Microphone processing (Android)',
  defaultValue: 'unprocessed',
  choices: {
    'unprocessed': 'Raw (no phone processing)',
    'generic': 'Phone default',
    'camcorder': 'Camcorder',
    'voice': 'Voice (noise reduction)',
  },
  section: 'Recording',
);

const defaultTagsSetting = TextSetting(
  key: 'defaultTags',
  title: 'Tags for new recordings',
  subtitle: 'Comma separated, e.g. outdoors, birds',
  section: 'Recording',
);

/// Where in-progress recordings live until saved (survives a crash).
class Takes {
  Takes(this.dir);

  final Directory dir;

  static Future<Takes> open() async {
    final tmp = await getApplicationSupportDirectory();
    return Takes(Directory(p.join(tmp.path, 'takes')));
  }

  File newFile() => File(
    p.join(dir.path, 'take-${DateTime.now().millisecondsSinceEpoch}.wav'),
  );

  /// Unsaved takes left behind (e.g. the app was closed mid-recording).
  Future<List<File>> leftovers() async {
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.wav')) files.add(e);
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// A scratch copy for editing a saved recording.
  File scratchFile() => File(p.join(dir.path, 'edit', 'scratch.wav'));
}

/// The trimmed range and the markers inside it, shifted to start at 0.
({double start, double end, List<double> markers}) trimMarkers(
  List<double> markers,
  double start,
  double end,
) => (
  start: start,
  end: end,
  markers: [
    for (final m in markers)
      if (m >= start && m <= end) double.parse((m - start).toStringAsFixed(3)),
  ]..sort(),
);

List<String> parseTags(String s) => {
  for (final t in s.split(','))
    if (t.trim().isNotEmpty) t.trim().toLowerCase(),
}.toList();

/// "Recording 23 Nov 14:05"
String defaultName(DateTime t) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Recording ${t.day} ${months[t.month - 1]} ${two(t.hour)}:${two(t.minute)}';
}
