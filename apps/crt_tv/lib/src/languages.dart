/// A language the TV can be told to prefer for sound or subtitles.
class Language {
  const Language(this.code, this.name, this.tags);

  /// What's saved in settings.
  final String code;
  final String name;

  /// The tags video files use for it (two- and three-letter codes).
  final List<String> tags;
}

const List<Language> kLanguages = [
  Language('en', 'English', ['en', 'eng']),
  Language('ja', 'Japanese', ['ja', 'jpn', 'jp']),
  Language('es', 'Spanish', ['es', 'spa']),
  Language('fr', 'French', ['fr', 'fre', 'fra']),
  Language('de', 'German', ['de', 'ger', 'deu']),
  Language('it', 'Italian', ['it', 'ita']),
  Language('pt', 'Portuguese', ['pt', 'por']),
  Language('ko', 'Korean', ['ko', 'kor']),
  Language('zh', 'Chinese', ['zh', 'chi', 'zho']),
  Language('ru', 'Russian', ['ru', 'rus']),
];

Language? languageByCode(String code) {
  for (final language in kLanguages) {
    if (language.code == code) return language;
  }
  return null;
}

/// One sound or subtitle track in a video file.
class TrackInfo {
  const TrackInfo(this.id, {this.language, this.title});

  final String id;

  /// The file's language tag, such as "eng". Often missing.
  final String? language;
  final String? title;

  /// Whether the file says what language this is at all.
  bool get hasLanguage {
    final tag = language?.trim().toLowerCase() ?? '';
    return tag.isNotEmpty && tag != 'und';
  }

  bool isIn(Language wanted) {
    final tag = language?.trim().toLowerCase() ?? '';
    // Tags can carry a region: "en-US", "pt_BR".
    final base = tag.split(RegExp('[-_]')).first;
    if (wanted.tags.contains(base)) return true;
    // Untagged tracks are often just named: "English 5.1".
    return !hasLanguage && (title?.toLowerCase().contains(wanted.name.toLowerCase()) ?? false);
  }
}

/// "2 ENGLISH", "1 COMMENTARY", "3".
String trackName(int index, TrackInfo track) {
  final tag = track.language?.trim().toLowerCase() ?? '';
  final base = tag.split(RegExp('[-_]')).first;
  String? name;
  for (final language in kLanguages) {
    if (language.tags.contains(base)) name = language.name;
  }
  name ??= track.hasLanguage ? tag : null;
  final title = track.title?.trim() ?? '';
  final text = name ?? (title.isNotEmpty ? title : '');
  return '${index + 1} $text'.trim().toUpperCase();
}

enum SubtitleMode {
  /// Whatever the video file itself asks for.
  fileDefault,
  off,
  on,

  /// Only when the video has no sound in the preferred language.
  auto,
}

/// What to switch to when a video starts. A null id means "leave it alone";
/// [noSubtitles] means subtitles off.
class TrackChoice {
  const TrackChoice({this.audioId, this.subtitleId});

  static const noSubtitles = 'no';

  final String? audioId;
  final String? subtitleId;
}

/// Picks the sound and subtitle tracks for a video from the saved defaults.
TrackChoice chooseTracks({
  required List<TrackInfo> audio,
  required List<TrackInfo> subtitles,
  required Language? audioLanguage,
  required Language? subtitleLanguage,
  required SubtitleMode mode,
}) {
  TrackInfo? first(List<TrackInfo> tracks, Language? wanted) {
    if (wanted == null) return null;
    for (final track in tracks) {
      if (track.isIn(wanted)) return track;
    }
    return null;
  }

  final sound = first(audio, audioLanguage);

  final bool show;
  switch (mode) {
    case SubtitleMode.fileDefault:
      return TrackChoice(audioId: sound?.id);
    case SubtitleMode.off:
      show = false;
    case SubtitleMode.on:
      show = true;
    case SubtitleMode.auto:
      // Untagged sound can't be judged, so it doesn't count as "foreign".
      show = audioLanguage != null && sound == null && audio.any((t) => t.hasLanguage);
  }
  if (!show) return TrackChoice(audioId: sound?.id, subtitleId: TrackChoice.noSubtitles);

  final text = subtitleLanguage == null
      ? (subtitles.isEmpty ? null : subtitles.first)
      : first(subtitles, subtitleLanguage);
  return TrackChoice(audioId: sound?.id, subtitleId: text?.id ?? TrackChoice.noSubtitles);
}
