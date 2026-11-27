import 'dart:io';
import 'dart:math' as math;

import 'models.dart';
import 'season.dart';

/// File types the player can handle. mpv plays almost anything, so this
/// list is generous.
const Set<String> kVideoExtensions = {
  'mp4', 'm4v', 'mkv', 'avi', 'mov', 'wmv', 'webm', 'mpg', 'mpeg', 'mpe',
  'm2v', 'm2ts', 'mts', 'ts', 'flv', '3gp', 'ogv', 'vob', 'divx', 'asf',
  'rm', 'rmvb', 'f4v', 'qt',
};

const Set<String> _commercialFolderNames = {
  'commercials', 'commercial', 'ads', 'adverts', 'advertisements',
};

final RegExp _channelPattern = RegExp(
  r'^(?:channel|chan|ch)?[\s._#-]*(\d{1,4})(?:[\s._:-]+(.*))?$',
  caseSensitive: false,
);

final RegExp _separators = RegExp(r'[\\/]');

String baseName(String path) {
  final parts = path.split(_separators).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

bool isVideoFile(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return false;
  return kVideoExtensions.contains(fileName.substring(dot + 1).toLowerCase());
}

bool isCommercialFolder(String folderName) =>
    _commercialFolderNames.contains(folderName.trim().toLowerCase());

final RegExp _namedChannelPattern = RegExp(
  r'^(?:channel|chan|ch)[\s._:-]+(\S.*)$',
  caseSensitive: false,
);

final RegExp _wholeParens = RegExp(r'^\(([^()]*)\)$');

/// "Channel 5 - Cartoons" → (5, "Cartoons"). "Ch3" → (3, "").
/// "Channel Gojira" → (null, "Gojira"): the scanner picks its number.
/// Others → null.
(int?, String)? parseChannelFolder(String folderName) {
  final trimmed = folderName.trim();
  final match = _channelPattern.firstMatch(trimmed);
  if (match != null) {
    var name = (match.group(2) ?? '').trim();
    name = _wholeParens.firstMatch(name)?.group(1)?.trim() ?? name;
    return (int.parse(match.group(1)!), name);
  }
  final named = _namedChannelPattern.firstMatch(trimmed);
  if (named == null) return null;
  return (null, named.group(1)!.trim());
}

/// "Show.Name.S01E02.mkv" → "Show Name S01E02".
String titleFromPath(String path) {
  var name = baseName(path);
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  if (!name.contains(' ')) name = name.replaceAll(RegExp(r'[._]+'), ' ');
  return name.replaceAll(RegExp(r'\s+'), ' ').trim();
}

final RegExp _chunk = RegExp(r'\d+|\D+');

bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

/// Compares strings so that "Episode 2" sorts before "Episode 10".
int naturalCompare(String a, String b) {
  final ca = _chunk.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final cb = _chunk.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  final n = math.min(ca.length, cb.length);
  for (var i = 0; i < n; i++) {
    final x = ca[i];
    final y = cb[i];
    int c;
    if (_isDigit(x.codeUnitAt(0)) && _isDigit(y.codeUnitAt(0))) {
      final xs = x.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final ys = y.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      c = xs.length.compareTo(ys.length);
      if (c == 0) c = xs.compareTo(ys);
      if (c == 0) c = x.length.compareTo(y.length);
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  return ca.length.compareTo(cb.length);
}

List<FileSystemEntity> _list(Directory dir, List<String> warnings) {
  try {
    final entries = dir.listSync(followLinks: true);
    entries.sort((a, b) => naturalCompare(a.path, b.path));
    return entries;
  } on FileSystemException catch (e) {
    warnings.add('Could not read "${dir.path}": ${e.message}');
    return const [];
  }
}

void _collectVideos(
  Directory dir,
  List<String> out,
  List<String> warnings, {
  bool skipCommercialFolders = false,
  int depth = 0,
}) {
  if (depth > 8) return;
  for (final entry in _list(dir, warnings)) {
    final name = baseName(entry.path);
    if (name.startsWith('.')) continue;
    if (entry is Directory) {
      if (skipCommercialFolders && isCommercialFolder(name)) continue;
      _collectVideos(entry, out, warnings, depth: depth + 1);
    } else if (entry is File && isVideoFile(name)) {
      out.add(entry.path);
    }
  }
}

/// Reads the TV folder. Runs in a background isolate, so it only uses dart:io.
///
/// Layout:
///   TV folder/
///     Commercials/            plays on every channel without its own
///     Channel 3/              shows and movies (subfolders are fine)
///       Commercials/          only plays on channel 3
///     Channel 5 - Cartoons/
TvLibrary scanLibrarySync(String rootPath) {
  final warnings = <String>[];
  final root = Directory(rootPath);
  if (!root.existsSync()) {
    return TvLibrary(
      rootPath: rootPath,
      channels: const [],
      globalCommercials: const [],
      warnings: ['The folder "$rootPath" was not found.'],
    );
  }

  final channels = <Channel>[];
  final globalCommercials = <String>[];
  final usedNumbers = <int, String>{};
  final numbered = <(Directory, int, String)>[];
  final unnumbered = <(Directory, String)>[];
  final seasons = <String, Set<int>>{};

  for (final entry in _list(root, warnings)) {
    if (entry is! Directory) continue;
    final folderName = baseName(entry.path);
    if (folderName.startsWith('.')) continue;

    if (isCommercialFolder(folderName)) {
      _collectVideos(entry, globalCommercials, warnings);
      continue;
    }

    // "Channel Halloween [Oct]": the tag says when it's on, the rest names it.
    final (plainName, months) = splitSeasonTag(folderName);
    final parsed = parseChannelFolder(plainName);
    if (parsed == null) continue;
    seasons[folderName] = months;
    final (number, name) = parsed;
    if (number == null) {
      unnumbered.add((entry, name));
      continue;
    }
    final existing = usedNumbers[number];
    if (existing != null) {
      warnings.add('"$existing" and "$folderName" are both channel $number. '
          'Only "$existing" is used.');
      continue;
    }
    usedNumbers[number] = folderName;
    numbered.add((entry, number, name));
  }

  // Folders without a number take the lowest free ones, in name order.
  // Seasonal ones go last, so adding one never renumbers the usual lineup.
  bool seasonal((Directory, String) folder) => seasons[baseName(folder.$1.path)]?.isNotEmpty ?? false;
  final inOrder = [...unnumbered.where((f) => !seasonal(f)), ...unnumbered.where(seasonal)];
  var next = 1;
  for (final (entry, name) in inOrder) {
    while (usedNumbers.containsKey(next)) {
      next++;
    }
    usedNumbers[next] = baseName(entry.path);
    numbered.add((entry, next, name));
  }

  for (final (entry, number, name) in numbered) {
    final folderName = baseName(entry.path);
    final programs = <String>[];
    final commercials = <String>[];
    _collectVideos(entry, programs, warnings, skipCommercialFolders: true);
    for (final sub in _list(entry, warnings)) {
      if (sub is Directory && isCommercialFolder(baseName(sub.path))) {
        _collectVideos(sub, commercials, warnings);
      }
    }
    programs.sort(naturalCompare);

    channels.add(Channel(
      number: number,
      name: name,
      folderName: folderName,
      folderPath: entry.path,
      programs: programs,
      commercials: commercials,
      months: seasons[folderName] ?? const {},
    ));
  }

  channels.sort((a, b) => a.number.compareTo(b.number));
  return TvLibrary(
    rootPath: rootPath,
    channels: channels,
    globalCommercials: globalCommercials,
    warnings: warnings,
  );
}
