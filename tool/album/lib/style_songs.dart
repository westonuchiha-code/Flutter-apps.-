/// A song for each music video style (Puppet Stage's lib/src/mv), so each
/// video is judged with music that suits it. Three are boom bap (the
/// album's engine), three are band songs (band.dart).
library;

import 'dart:typed_data';

import 'album.dart';
import 'band.dart';
import 'song.dart';

/// Hard and serious: minor strings and horn stabs over a heavy beat.
const liberationSong = Song(
  title: 'Liberation',
  bpm: 92,
  seed: 606,
  chords: [
    [48, 51, 55, 58], // Cm7
    [44, 48, 51, 55], // Abmaj7
    [41, 44, 48, 51], // Fm7
    [43, 47, 50, 53], // G7
  ],
  bassRoots: [36, 32, 29, 31],
  keys: ['strings', 'horns'],
  drums: 'boom2',
  swing: 0.55,
  loopHz: 3800,
  scratchPhrase: 'stand up',
  scratchMc: lexicon,
  cuts: ['transform', 'stab', 'chirp', 'tear'],
  sections: [
    Section(Part.intro, 4),
    Section(Part.verse, 8, mc: lexicon),
    Section(Part.hook, 8),
    Section(Part.verse, 8, mc: lexicon),
    Section(Part.hook, 8),
    Section(Part.breakdown, 8),
    Section(Part.hook, 8),
    Section(Part.outro, 4),
  ],
);

/// Sunny and easy: Rhodes and flute, a lazy swung beat.
const backyardSong = Song(
  title: 'Backyard',
  bpm: 94,
  seed: 707,
  chords: [
    [53, 57, 60, 64], // Fmaj7
    [52, 55, 59, 62], // Em7
    [50, 53, 57, 60], // Dm7
    [48, 52, 55, 59], // Cmaj7
  ],
  bassRoots: [41, 40, 38, 36],
  keys: ['rhodes', 'flute'],
  drums: 'lazy',
  swing: 0.6,
  loopHz: 6500,
  scratchPhrase: 'back yard',
  scratchMc: vox,
  cuts: ['baby', 'chirp', 'flare', 'stab'],
  sections: [
    Section(Part.intro, 4),
    Section(Part.verse, 8, mc: lexicon),
    Section(Part.hook, 8),
    Section(Part.verse, 8, mc: lexicon),
    Section(Part.hook, 8),
    Section(Part.breakdown, 8),
    Section(Part.hook, 8),
    Section(Part.outro, 4),
  ],
);

/// A style's song: how to render it, its map, and the bars of its take.
typedef StyleTrack = ({
  String style,
  String title,
  Float32List Function() render,
  Map<String, Object?> Function() map,
  int from,
  int to,
});

List<StyleTrack> styleTracks() {
  final liquid = songs.firstWhere((s) => s.title == 'Liquid Logic');
  final undertow = undertowSong(), deadpan = deadpanSong();
  final mothership = mothershipSong();
  return [
    (
      style: 'liberation',
      title: 'Liberation',
      render: () => renderSong(liberationSong, vocals: false),
      map: () => songMapJson(liberationSong),
      from: 12,
      to: 24,
    ),
    (
      style: 'cipher',
      title: 'Liquid Logic',
      render: () => renderSong(liquid, vocals: false),
      map: () => songMapJson(liquid),
      from: 28,
      to: 39,
    ),
    (
      style: 'backyard',
      title: 'Backyard',
      render: () => renderSong(backyardSong, vocals: false),
      map: () => songMapJson(backyardSong),
      from: 12,
      to: 24,
    ),
    (
      style: 'undertow',
      title: 'Undertow',
      render: () => renderBand(undertow),
      map: () => bandMapJson(undertow),
      from: 12,
      to: 26,
    ),
    (
      style: 'deadpan',
      title: 'Deadpan',
      render: () => renderBand(deadpan),
      map: () => bandMapJson(deadpan),
      from: 10,
      to: 24,
    ),
    (
      style: 'mothership',
      title: 'Mothership',
      render: () => renderBand(mothership),
      map: () => bandMapJson(mothership),
      from: 10,
      to: 23,
    ),
  ];
}
