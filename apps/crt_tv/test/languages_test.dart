import 'package:crt_tv/src/languages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final english = languageByCode('en')!;
  final japanese = languageByCode('ja')!;

  const dual = [
    TrackInfo('1', language: 'jpn'),
    TrackInfo('2', language: 'eng', title: 'Dub'),
  ];
  const japaneseOnly = [TrackInfo('1', language: 'jpn')];
  const untagged = [TrackInfo('1')];
  const subs = [
    TrackInfo('1', language: 'spa'),
    TrackInfo('2', language: 'en-US', title: 'Full'),
  ];

  test('language tags, regions and plain titles are recognised', () {
    expect(const TrackInfo('1', language: 'ENG').isIn(english), isTrue);
    expect(const TrackInfo('1', language: 'en-US').isIn(english), isTrue);
    expect(const TrackInfo('1', title: 'English 5.1').isIn(english), isTrue);
    expect(const TrackInfo('1', language: 'und', title: 'English').isIn(english), isTrue);
    expect(const TrackInfo('1', language: 'jpn', title: 'English staff commentary').isIn(english), isFalse);
    expect(const TrackInfo('1').isIn(english), isFalse);
  });

  test('tracks are named for the menu', () {
    expect(trackName(1, const TrackInfo('2', language: 'eng', title: 'Dub')), '2 ENGLISH');
    expect(trackName(0, const TrackInfo('1', title: 'Commentary')), '1 COMMENTARY');
    expect(trackName(0, const TrackInfo('1', language: 'swe')), '1 SWE');
    expect(trackName(2, const TrackInfo('3')), '3');
  });

  test('preferred audio is chosen when the video has it', () {
    final choice = chooseTracks(
      audio: dual,
      subtitles: subs,
      audioLanguage: english,
      subtitleLanguage: english,
      mode: SubtitleMode.fileDefault,
    );
    expect(choice.audioId, '2');
    expect(choice.subtitleId, isNull, reason: 'file default leaves subtitles alone');

    final none = chooseTracks(
      audio: japaneseOnly,
      subtitles: subs,
      audioLanguage: english,
      subtitleLanguage: null,
      mode: SubtitleMode.off,
    );
    expect(none.audioId, isNull, reason: 'no English sound, so keep what the file plays');
    expect(none.subtitleId, TrackChoice.noSubtitles);
  });

  test('subtitles on: the preferred language, or off if the video lacks it', () {
    expect(
      chooseTracks(audio: dual, subtitles: subs, audioLanguage: null, subtitleLanguage: english, mode: SubtitleMode.on)
          .subtitleId,
      '2',
    );
    expect(
      chooseTracks(audio: dual, subtitles: subs, audioLanguage: null, subtitleLanguage: japanese, mode: SubtitleMode.on)
          .subtitleId,
      TrackChoice.noSubtitles,
    );
    expect(
      chooseTracks(audio: dual, subtitles: subs, audioLanguage: null, subtitleLanguage: null, mode: SubtitleMode.on)
          .subtitleId,
      '1',
      reason: 'no language chosen means the first one',
    );
  });

  test('automatic subtitles appear only when the sound is in another language', () {
    TrackChoice auto(List<TrackInfo> audio) => chooseTracks(
          audio: audio,
          subtitles: subs,
          audioLanguage: english,
          subtitleLanguage: english,
          mode: SubtitleMode.auto,
        );
    expect(auto(dual).subtitleId, TrackChoice.noSubtitles, reason: 'English dub is there');
    expect(auto(dual).audioId, '2');
    expect(auto(japaneseOnly).subtitleId, '2', reason: 'Japanese only: show English subtitles');
    expect(auto(untagged).subtitleId, TrackChoice.noSubtitles, reason: "can't tell, so don't guess");
  });
}
