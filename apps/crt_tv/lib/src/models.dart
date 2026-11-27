// Plain data classes shared by the scanner, the channel engine and the UI.

import 'languages.dart';

/// One channel, built from a folder such as "Channel 3" or "Channel 5 - Cartoons".
class Channel {
  Channel({
    required this.number,
    required this.name,
    required this.folderName,
    required this.folderPath,
    required this.programs,
    required this.commercials,
    this.months = const {},
  });

  final int number;

  /// The months (1-12) this channel is on the air, from a tag such as
  /// "[Oct]" in its folder name. Empty means all year.
  final Set<int> months;

  /// The part of the folder name after the number ("Cartoons"), or ''.
  final String name;

  /// The folder's own name. Used as the key for saved settings and progress.
  final String folderName;
  final String folderPath;

  /// Shows and movies, in natural order (Episode 2 before Episode 10).
  final List<String> programs;

  /// Commercials from this channel's own "Commercials" subfolder.
  final List<String> commercials;

  String get label => name.isEmpty ? 'Channel $number' : name;
}

/// Everything found in the TV folder.
class TvLibrary {
  TvLibrary({
    required this.rootPath,
    required this.channels,
    required this.globalCommercials,
    this.warnings = const [],
  });

  final String rootPath;

  /// Sorted by channel number.
  final List<Channel> channels;

  /// Commercials from the top-level "Commercials" folder. They play on every
  /// channel that has no commercials of its own.
  final List<String> globalCommercials;

  /// Problems worth showing in Settings (unreadable folders, duplicate numbers).
  final List<String> warnings;

  Channel? channel(int number) {
    for (final c in channels) {
      if (c.number == number) return c;
    }
    return null;
  }

  int get videoCount =>
      channels.fold<int>(
        0,
        (sum, c) => sum + c.programs.length + c.commercials.length,
      ) +
      globalCommercials.length;

  bool get isEmpty => channels.isEmpty;
}

enum CrtEffect { off, subtle, strong }

enum SkinStyle {
  none,
  wood,
  black,
  silver,
  crt95,
  cyberpunk,
  wasteland,
  atomic,
  memphis,
  boombox,
  portable,
  combo,
  clear,
}

enum VideoFit { fit, stretch, zoom }

/// Commercial-break setting. -1 means "random, 1 to 3".
const int kRandomBreak = -1;

String breakLabel(int perBreak) {
  switch (perBreak) {
    case 0:
      return 'Off';
    case 1:
      return '1 commercial';
    case kRandomBreak:
      return 'Random (1–3)';
    default:
      return '$perBreak commercials';
  }
}

const List<int> kBreakChoices = [0, 1, 2, 3, kRandomBreak];

/// Per-channel settings, keyed by the channel's folder name.
class ChannelOverride {
  ChannelOverride({this.shuffle = false, this.commercialsPerBreak});

  /// Play the folder in a random order instead of in order.
  bool shuffle;

  /// null = use the global setting.
  int? commercialsPerBreak;

  Map<String, Object?> toJson() => {
    'shuffle': shuffle,
    if (commercialsPerBreak != null) 'perBreak': commercialsPerBreak,
  };

  static ChannelOverride fromJson(Object? json) {
    if (json is! Map) return ChannelOverride();
    final perBreak = json['perBreak'];
    return ChannelOverride(
      shuffle: json['shuffle'] == true,
      commercialsPerBreak: perBreak is num ? perBreak.toInt() : null,
    );
  }
}

T _enumFrom<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// App-wide settings. Saved to disk by [AppStore].
class AppSettings {
  String? libraryPath;
  int commercialsPerBreak = 2;

  /// true: channels keep playing while you watch something else, like real TV.
  /// false: each channel waits where you left it.
  bool liveMode = true;
  CrtEffect crtEffect = CrtEffect.subtle;
  SkinStyle skin = SkinStyle.wood;
  VideoFit videoFit = VideoFit.fit;
  bool staticOnChange = true;
  bool staticSound = true;
  bool showTitles = true;

  /// Preferred sound and subtitle languages ([Language.code]); '' = none.
  String audioLanguage = '';
  String subtitleLanguage = '';
  SubtitleMode subtitleMode = SubtitleMode.fileDefault;

  /// Turn each video up or down so they all play at about the same loudness.
  bool levelSound = false;

  /// Show seasonal channels all year instead of only in their months.
  bool seasonalAlways = false;
  double volume = 80;
  bool muted = false;
  int? lastChannel;
  final Map<String, ChannelOverride> overrides = {};

  /// Changed controls only, by action name: a key id (0 = no key), and a
  /// controller button name ('' = no button). See [Bindings].
  final Map<String, int> keyOverrides = {};
  final Map<String, String> padOverrides = {};

  ChannelOverride overrideFor(String folderName) =>
      overrides.putIfAbsent(folderName, () => ChannelOverride());

  int perBreakFor(String folderName) =>
      overrides[folderName]?.commercialsPerBreak ?? commercialsPerBreak;

  bool shuffleFor(String folderName) => overrides[folderName]?.shuffle ?? false;

  Map<String, Object?> toJson() => {
    'libraryPath': libraryPath,
    'commercialsPerBreak': commercialsPerBreak,
    'liveMode': liveMode,
    'crtEffect': crtEffect.name,
    'skin': skin.name,
    'videoFit': videoFit.name,
    'staticOnChange': staticOnChange,
    'staticSound': staticSound,
    'showTitles': showTitles,
    'audioLanguage': audioLanguage,
    'subtitleLanguage': subtitleLanguage,
    'subtitleMode': subtitleMode.name,
    'levelSound': levelSound,
    'seasonalAlways': seasonalAlways,
    'volume': volume,
    'muted': muted,
    'lastChannel': lastChannel,
    'overrides': {for (final e in overrides.entries) e.key: e.value.toJson()},
    'keyOverrides': keyOverrides,
    'padOverrides': padOverrides,
  };

  void loadJson(Object? json) {
    if (json is! Map) return;
    final path = json['libraryPath'];
    libraryPath = path is String && path.isNotEmpty ? path : null;
    final perBreak = json['commercialsPerBreak'];
    if (perBreak is num) commercialsPerBreak = perBreak.toInt();
    liveMode = json['liveMode'] != false;
    crtEffect = _enumFrom(
      CrtEffect.values,
      json['crtEffect'],
      CrtEffect.subtle,
    );
    skin = _enumFrom(SkinStyle.values, json['skin'], SkinStyle.wood);
    videoFit = _enumFrom(VideoFit.values, json['videoFit'], VideoFit.fit);
    staticOnChange = json['staticOnChange'] != false;
    staticSound = json['staticSound'] != false;
    showTitles = json['showTitles'] != false;
    final audioLang = json['audioLanguage'];
    audioLanguage = audioLang is String ? audioLang : '';
    final subtitleLang = json['subtitleLanguage'];
    subtitleLanguage = subtitleLang is String ? subtitleLang : '';
    subtitleMode = _enumFrom(
      SubtitleMode.values,
      json['subtitleMode'],
      SubtitleMode.fileDefault,
    );
    levelSound = json['levelSound'] == true;
    seasonalAlways = json['seasonalAlways'] == true;
    final vol = json['volume'];
    if (vol is num) {
      final v = vol.toDouble();
      volume = v < 0.0 ? 0.0 : (v > 100.0 ? 100.0 : v);
    }
    muted = json['muted'] == true;
    final last = json['lastChannel'];
    lastChannel = last is num ? last.toInt() : null;
    overrides.clear();
    final saved = json['overrides'];
    if (saved is Map) {
      for (final e in saved.entries) {
        overrides[e.key.toString()] = ChannelOverride.fromJson(e.value);
      }
    }
    keyOverrides.clear();
    final keys = json['keyOverrides'];
    if (keys is Map) {
      for (final e in keys.entries) {
        final id = e.value;
        if (id is num) keyOverrides[e.key.toString()] = id.toInt();
      }
    }
    padOverrides.clear();
    final pad = json['padOverrides'];
    if (pad is Map) {
      for (final e in pad.entries) {
        padOverrides[e.key.toString()] = e.value.toString();
      }
    }
  }
}
