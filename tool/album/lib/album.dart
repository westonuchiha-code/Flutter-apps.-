/// "Twelve-Bit Science" by The Allophones: three speech chips and a DJ.
/// Original words and music (in the spirit of 90s jazz-sampling boom bap).
library;

import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';

import 'beeps.dart';
import 'dsp.dart';
import 'instruments.dart';
import 'rap.dart';
import 'scratch.dart';
import 'song.dart';

const albumTitle = 'Twelve-Bit Science';
const artist = 'The Allophones';

/// The crew.
const lexicon = Mc('Lexicon', SpeechChip.tms5220, 88); // deep, LPC grit
const sputnik = Mc(
  'Sputnik',
  SpeechChip.sp0256,
  112,
  gain: 0.95,
); // jumpy allophones
const vox = Mc('Vox', SpeechChip.votrax, 100, gain: 0.9); // analog glide
const crew = [lexicon, sputnik, vox];

Section intro([int bars = 4]) => Section(Part.intro, bars);
Section outro([int bars = 4]) => Section(Part.outro, bars);
Section breakdown([int bars = 8]) => Section(Part.breakdown, bars);
Section verse(Mc mc, List<String> lines) =>
    Section(Part.verse, lines.length, mc: mc, lines: lines);
Section hook(List<String> lines, [List<Mc> mcs = crew]) =>
    Section(Part.hook, lines.length * 2, lines: lines, mcs: mcs);

final songs = <Song>[
  Song(
    title: 'Twelve-Bit Science',
    bpm: 92,
    seed: 101,
    chords: const [
      [50, 53, 57, 60, 64], // Dm9
      [43, 53, 57, 59, 64], // G13
      [48, 52, 55, 59, 62], // Cmaj9
      [45, 49, 55, 58, 61], // A7(b9)
    ],
    bassRoots: const [38, 31, 36, 33],
    keys: const ['rhodes'],
    drums: 'boom',
    scratchPhrase: 'twelve bit science',
    scratchMc: lexicon,
    sections: [
      intro(),
      verse(lexicon, const [
        'I was born in a box with a speaker and a grill',
        'eight kilohertz voice but I am rhyming with skill',
        'filter on the lips and the frames on the beat',
        'twenty five milliseconds every word is complete',
        'they put me in a toy so the children could spell',
        'now I am in the cipher and I do it so well',
        'low pitch table and a chirp for a heart',
        'Lexicon the scholar I was smart from the start',
      ]),
      hook(const [
        'twelve bit science dropped from the crates',
        'three little chips with the voice of the greats',
        'the needle hits the groove and the rhythm relates',
        'Allophones word up we keep it straight',
      ]),
      verse(sputnik, const [
        'Sputnik on the mic with the allophone kit',
        'sixty four sounds and I build every bit',
        'no smoothing in the frame so I jump when I speak',
        'ten milliseconds and I hit you on the peak',
        'dusty little chip from a cartridge in the shed',
        'a kid found me later and he plugged me in instead',
        'now the beat is knocking and the people are amazed',
        'Sputnik with the science from the cartridge days',
      ]),
      hook(const [
        'twelve bit science dropped from the crates',
        'three little chips with the voice of the greats',
        'the needle hits the groove and the rhythm relates',
        'Allophones word up we keep it straight',
      ]),
      verse(vox, const [
        'Votrax on the vocals with the analog glide',
        'four steps of pitch but I swing with the stride',
        'clock goes up and my voice gets young',
        'clock goes down and the wisdom is sung',
        'formant filters warm like a record in the sun',
        'three chips one mission we are second to none',
        'Crossfade on the decks with the baby and the chirp',
        'Allophones forever now let the needle work',
      ]),
      hook(const [
        'twelve bit science dropped from the crates',
        'three little chips with the voice of the greats',
        'the needle hits the groove and the rhythm relates',
        'Allophones word up we keep it straight',
      ]),
      outro(),
    ],
  ),
  Song(
    title: 'Dusty Fingers',
    bpm: 90,
    seed: 202,
    chords: const [
      [52, 55, 59, 62], // Em7
      [57, 60, 64, 67], // Am7
      [50, 54, 57, 60], // D7
      [55, 59, 62, 66], // Gmaj7
    ],
    bassRoots: const [40, 33, 38, 31],
    keys: const ['vibes', 'strings'],
    drums: 'lazy',
    swing: 0.6,
    scratchPhrase: 'dusty fingers',
    scratchMc: sputnik,
    cuts: const ['baby', 'chirp', 'flare', 'tear'],
    sections: [
      intro(),
      verse(sputnik, const [
        'Saturday morning at the swap meet tent',
        'every single quarter in my pocket gets spent',
        'jazz records warped and the covers are torn',
        'but the drum break in the middle got the beat reborn',
        'blow off the dust and I check the run out',
        'vibes and a bassline that is what it is about',
        'chop it on the twelve bit filter on the low',
        'Sputnik with the crates and the patience to grow',
      ]),
      hook(
        const [
          'dusty fingers in the crates all day',
          'dollar bin gold that they threw away',
          'flip a little loop and we let it play',
          'dusty fingers that is the way',
        ],
        const [sputnik, vox],
      ),
      verse(vox, const [
        'I dig in the basement where the water got in',
        'found a funky record with a hole in the skin',
        'needle on the wax and it crackles like rain',
        'the horns came in sweet like a sunset in Spain',
        'sample it slow and I pitch it to the key',
        'loop it four bars and it talks back to me',
        'nobody knew what the treasure would be',
        'dusty fingers Vox the archaeology',
      ]),
      hook(
        const [
          'dusty fingers in the crates all day',
          'dollar bin gold that they threw away',
          'flip a little loop and we let it play',
          'dusty fingers that is the way',
        ],
        const [sputnik, vox],
      ),
      verse(lexicon, const [
        'history pressed in a circle of black',
        'every groove a story I am bringing it back',
        'the label is faded but the sound is alive',
        'ninety beats a minute and we let it arrive',
        'respect to the players who recorded the songs',
        'the session got paid and the music lives on',
        'we dig with respect and we flip it with love',
        'dusty fingers sending it up to the clouds above',
      ]),
      hook(const [
        'dusty fingers in the crates all day',
        'dollar bin gold that they threw away',
        'flip a little loop and we let it play',
        'dusty fingers that is the way',
      ]),
      outro(),
    ],
  ),
  Song(
    title: 'Cipher in the Park',
    bpm: 94,
    seed: 303,
    chords: const [
      [53, 57, 60, 64], // Fmaj7
      [52, 55, 59, 62], // Em7
      [50, 53, 57, 60], // Dm7
      [48, 52, 55, 58], // C7
    ],
    bassRoots: const [41, 40, 38, 36],
    keys: const ['rhodes', 'flute'],
    drums: 'bounce',
    scratchPhrase: 'cipher in the park',
    scratchMc: vox,
    cuts: const ['chirp', 'transform', 'baby', 'stab'],
    sections: [
      intro(),
      verse(vox, const [
        'swings in the playground and a game on the court',
        'a crowd in a circle and the rhymes are the sport',
        'somebody beatboxing with his hand on his jaw',
        'I step in the middle and I tell what I saw',
        'pigeons on the wire and the ice cream bell',
        'every little story that the summer can tell',
        'freestyle off the top with the breeze in my face',
        'Vox in the circle and I hold my place',
      ]),
      hook(const [
        'cipher in the park when the sun goes low',
        'boom box on the bench and the people in a row',
        'everybody waiting for the next one to go',
        'cipher in the park let the flow flow',
      ]),
      verse(lexicon, const [
        'Lexicon next and the circle gets tight',
        'the street lights flicker as the day turns night',
        'I rhyme about the corner and the bakery smell',
        'the bus going by and the old school bell',
        'no microphone needed just a voice and a beat',
        'the rhythm of the city coming up from the street',
        'pass it to the left and the cipher keeps turning',
        'Lexicon teaching while the sky is still burning',
      ]),
      hook(const [
        'cipher in the park when the sun goes low',
        'boom box on the bench and the people in a row',
        'everybody waiting for the next one to go',
        'cipher in the park let the flow flow',
      ]),
      verse(sputnik, const [
        'Sputnik with the closer and I keep it in the pocket',
        'energy rising like a homemade rocket',
        'everybody clapping on the two and the four',
        'the circle getting bigger and they all want more',
        'no battle tonight it is love in the air',
        'strangers become friends when the music is there',
        'one more round and we call it a night',
        'cipher in the park and the future is bright',
      ]),
      hook(const [
        'cipher in the park when the sun goes low',
        'boom box on the bench and the people in a row',
        'everybody waiting for the next one to go',
        'cipher in the park let the flow flow',
      ]),
      outro(),
    ],
  ),
  Song(
    title: 'Liquid Logic',
    chorus: liquidChorus,
    bpm: 86,
    seed: 404,
    chords: const [
      [45, 48, 52, 55], // Am7
      [45, 48, 52, 55],
      [41, 45, 48, 52], // Fmaj7
      [40, 44, 47, 50], // E7
    ],
    bassRoots: const [33, 33, 29, 28],
    keys: const ['strings', 'piano'],
    drums: 'dark',
    swing: 0.54,
    loopHz: 4200,
    scratchPhrase: 'liquid logic',
    scratchMc: lexicon,
    cuts: const ['transform', 'scribble', 'chirp', 'tear'],
    sections: [
      intro(),
      verse(lexicon, const [
        'sixty four squares and a single candle lit',
        'I study every angle till the pieces all fit',
        'pawn to the center and the bishop in the shade',
        'patience is a weapon and the plan is well made',
        'rain on the window like a drum in the dark',
        'the opening is silent but the middle is the spark',
        'knight on the rim but the move is a lure',
        'Lexicon in focus and the logic is pure',
      ]),
      hook(
        const [
          'liquid logic move like water on the board',
          'mind sharp like the edge of a sword',
          'every single bar is a move toward',
          'checkmate quiet no need to roar',
        ],
        const [lexicon, vox],
      ),
      verse(vox, const [
        'monk on the mountain with a blade in the sheath',
        'a calm on the surface and a storm underneath',
        'I bow to the master then I step in the ring',
        'the silence is louder than the words that I bring',
        'water takes the shape of whatever it fills',
        'the mind is the dojo and the verses are drills',
        'one cut clean and the lesson is done',
        'Vox in the shadow I am never on the run',
      ]),
      hook(
        const [
          'liquid logic move like water on the board',
          'mind sharp like the edge of a sword',
          'every single bar is a move toward',
          'checkmate quiet no need to roar',
        ],
        const [lexicon, vox],
      ),
      breakdown(),
      verse(sputnik, const [
        'Sputnik on the board with a queen in disguise',
        'the trap is set and it is right before your eyes',
        'tick of the clock and the pressure is real',
        'cold like the morning on a blade of steel',
        'every move echoes in the hall of the mind',
        'leave the noise of the world and the fear behind',
        'king in the corner and the game is complete',
        'liquid logic dripping on the beat',
      ]),
      hook(const [
        'liquid logic move like water on the board',
        'mind sharp like the edge of a sword',
        'every single bar is a move toward',
        'checkmate quiet no need to roar',
      ]),
      outro(),
    ],
  ),
  Song(
    title: 'Brick City Breaks',
    bpm: 95,
    seed: 505,
    chords: const [
      [48, 51, 55, 58], // Cm7
      [48, 51, 55, 58],
      [53, 56, 60, 63], // Fm7
      [55, 59, 62, 65], // G7
    ],
    bassRoots: const [36, 36, 41, 31],
    keys: const ['horns', 'piano'],
    drums: 'boom2',
    scratchPhrase: 'brick city',
    scratchMc: sputnik,
    cuts: const ['stab', 'chirp', 'flare', 'baby'],
    sections: [
      intro(),
      verse(sputnik, const [
        'red brick buildings and a fire escape',
        'the mixtape playing on a worn out tape',
        'subway rumble underneath my feet',
        'the whole block nodding to the same old beat',
        'graffiti on the wall in a color you can taste',
        'the corner store owner never lets it go to waste',
        'horns from a record that my uncle used to play',
        'Sputnik from the bricks and I am here to stay',
      ]),
      hook(const [
        'brick city breaks hear the horns go',
        'from the rooftop down to the radio',
        'kick on the boom and the snare hits so',
        'brick city breaks that is the show',
      ]),
      verse(lexicon, const [
        'stoop full of neighbors and a game of chess',
        'the old men talking about the city and its stress',
        'kids at the hydrant when the summer gets hot',
        'everybody shining with whatever they got',
        'the bass from a car shaking windows on the street',
        'a b boy spinning on a piece of cardboard sheet',
        'history in the mortar every brick has a name',
        'Lexicon reporting from the heart of the game',
      ]),
      hook(const [
        'brick city breaks hear the horns go',
        'from the rooftop down to the radio',
        'kick on the boom and the snare hits so',
        'brick city breaks that is the show',
      ]),
      breakdown(),
      hook(const [
        'brick city breaks hear the horns go',
        'from the rooftop down to the radio',
        'kick on the boom and the snare hits so',
        'brick city breaks that is the show',
      ]),
      outro(),
    ],
  ),
  Song(
    title: 'Midnight Transit',
    bpm: 88,
    seed: 606,
    chords: const [
      [49, 52, 56, 59], // C#m7
      [47, 50, 54, 57], // Bm7
      [45, 49, 52, 56], // Amaj7
      [44, 48, 51, 54], // G#7
    ],
    bassRoots: const [37, 35, 33, 32],
    keys: const ['rhodes', 'strings'],
    drums: 'lazy',
    swing: 0.58,
    loopHz: 4600,
    scratchPhrase: 'midnight transit',
    scratchMc: vox,
    cuts: const ['baby', 'transform', 'chirp', 'scribble'],
    sections: [
      intro(),
      verse(vox, const [
        'last train leaving at a quarter to one',
        'the platform empty and the day is done',
        'a sax man playing by the turnstile gate',
        'his case is open and the hour is late',
        'the tunnel lights flash like a film reel',
        'every single stop has a story to reveal',
        'a sleeping stranger and a book on her knee',
        'Vox on the transit the city and me',
      ]),
      hook(
        const [
          'midnight transit riding through the town',
          'window full of lights as the city winds down',
          'headphones on and the world is a sound',
          'midnight transit underground',
        ],
        const [vox, sputnik],
      ),
      verse(sputnik, const [
        'the doors slide open with a sigh and a chime',
        'the conductor calling out the stops on time',
        'I write in my notebook as the rails sing low',
        'the rhymes come easy when the train is slow',
        'a city of dreamers in the dark below',
        'every face a chapter of a story I know',
        'the river goes by in the silver of the moon',
        'Sputnik on the transit I will be home soon',
      ]),
      hook(
        const [
          'midnight transit riding through the town',
          'window full of lights as the city winds down',
          'headphones on and the world is a sound',
          'midnight transit underground',
        ],
        const [vox, sputnik],
      ),
      breakdown(),
      hook(const [
        'midnight transit riding through the town',
        'window full of lights as the city winds down',
        'headphones on and the world is a sound',
        'midnight transit underground',
      ]),
      outro(),
    ],
  ),
  Song(
    title: 'The Wordsmiths',
    bpm: 93,
    seed: 707,
    chords: const [
      [46, 50, 53, 57], // Bbmaj7
      [45, 48, 52, 55], // Am7
      [43, 46, 50, 53], // Gm7
      [45, 49, 52, 55], // A7
    ],
    bassRoots: const [34, 33, 31, 33],
    keys: const ['piano'],
    drums: 'boom',
    scratchPhrase: 'wordsmiths',
    scratchMc: lexicon,
    cuts: const ['chirp', 'flare', 'transform', 'tear'],
    sections: [
      intro(),
      verse(lexicon, const [
        'I fold the metaphor like a blade in the forge',
        'heat it in the flame from the mountain to the gorge',
        'temper every rhyme in the water of the mind',
        'a sharp little line with a double meaning behind',
        'you bring a butter knife to a dictionary fight',
        'I bring the whole library I am reading all night',
        'syllables stacking like a tower in a storm',
        'Lexicon the wordsmith I am staying in form',
      ]),
      hook(const [
        'wordsmiths hammer on the anvil of the verse',
        'sparks fly out when the syllables burst',
        'forged in the fire and the beat is rehearsed',
        'wordsmiths we come first',
      ]),
      verse(sputnik, const [
        'Sputnik with the rhythm and I bend it like steel',
        'internal rhyme patterns with the many syllable feel',
        'you rhyme cat with hat and you think you are slick',
        'I rhyme in triangles the geometry is thick',
        'alliteration rattling a radical reaction',
        'every bar of mine is a fraction of an action',
        'bring a thesaurus it will not save you',
        'Sputnik the wordsmith with the words I made new',
      ]),
      hook(const [
        'wordsmiths hammer on the anvil of the verse',
        'sparks fly out when the syllables burst',
        'forged in the fire and the beat is rehearsed',
        'wordsmiths we come first',
      ]),
      verse(vox, const [
        'Vox with the vowels and the consonants clean',
        'the sharpest little robot that the cipher has seen',
        'I tinker with the tongue like a watchmaker would',
        'every gear clicking like a good word should',
        'rhyme in the morning rhyme in the dark',
        'every single syllable leaving a mark',
        'three chips forging on the anvil of sound',
        'wordsmiths the hammer comes down',
      ]),
      hook(const [
        'wordsmiths hammer on the anvil of the verse',
        'sparks fly out when the syllables burst',
        'forged in the fire and the beat is rehearsed',
        'wordsmiths we come first',
      ]),
      outro(),
    ],
  ),
  Song(
    title: 'Pocket of Time',
    bpm: 84,
    seed: 808,
    chords: const [
      [51, 55, 58, 62], // Ebmaj7
      [50, 53, 57, 60], // Dm7
      [48, 51, 55, 58], // Cm7
      [53, 57, 60, 63], // F7
    ],
    bassRoots: const [39, 38, 36, 41],
    keys: const ['vibes', 'strings'],
    drums: 'lazy',
    swing: 0.6,
    loopHz: 4800,
    scratchPhrase: 'pocket of time',
    scratchMc: vox,
    cuts: const ['baby', 'chirp', 'baby', 'transform'],
    sections: [
      intro(),
      verse(lexicon, const [
        'I remember the days of the cassette deck',
        'pause button mixing on a tape that would wreck',
        'waiting by the radio to catch the new jam',
        'writing every lyric in a notebook by hand',
        'summer on the porch and the crickets in the yard',
        'the music playing loud from a neighbor in the yard',
        'we did not have much but the rhythm was free',
        'Lexicon remembering the way it used to be',
      ]),
      hook(
        const [
          'pocket of time let it ride slow',
          'every little moment that we used to know',
          'vinyl keeps turning and the memories glow',
          'pocket of time let it go',
        ],
        const [lexicon, vox],
      ),
      verse(vox, const [
        'the needle slows down at the end of the side',
        'a little bit of crackle where the memories hide',
        'the friends that we had and the places we ran',
        'the corner the court and the ice cream van',
        'time is a record and it spins one way',
        'so I hold every groove of the songs that we play',
        'if you ever feel lost in the speed of the night',
        'find a pocket of time and the rhythm is right',
      ]),
      hook(
        const [
          'pocket of time let it ride slow',
          'every little moment that we used to know',
          'vinyl keeps turning and the memories glow',
          'pocket of time let it go',
        ],
        const [lexicon, vox],
      ),
      breakdown(),
      hook(const [
        'pocket of time let it ride slow',
        'every little moment that we used to know',
        'vinyl keeps turning and the memories glow',
        'pocket of time let it go',
      ]),
      outro(8),
    ],
  ),
];

/// A short track: a few bars of drums and a loop under the DJ.
Float32List _djTrack(
  Song base,
  List<List<String>> routines,
  Float32List sample, {
  List<(double, String, Mc)> talk = const [],
}) {
  final beat = 60 / base.bpm, bar = beat * 4;
  final bars = routines.length;
  final mix = Mix(bars * bar + 2);
  final loop = makeLoop(base);
  final k = kick(seed: base.seed),
      s = snare(seed: base.seed),
      h = hat(seed: base.seed);
  for (var i = 0; i < bars; i++) {
    final t = i * bar;
    final lb = i % base.chords.length;
    mix.addWide(
      Float32List.sublistView(
        loop,
        (lb * bar * sr).round(),
        ((lb + 1) * bar * sr).round(),
      ),
      t,
      0.7,
    );
    if (i > 0) {
      for (var st = 0; st < 16; st++) {
        final sw = st.isOdd ? (base.swing - 0.5) * beat / 2 : 0.0;
        if ('x.....x...x.....'[st] == 'x')
          mix.add(k, t + st * beat / 4 + sw, 1);
        if ('....x.......x...'[st] == 'x')
          mix.add(s, t + st * beat / 4 + sw, 0.85);
        if (st.isEven) mix.add(h, t + st * beat / 4 + sw, 0.4, 0.25);
      }
    }
    mix.add(
      routine(sample, routines[i], base.bpm, seed: i + 40),
      t,
      0.9,
      i.isEven ? -0.3 : 0.3,
    );
  }
  for (final (at, text, mc) in talk) {
    mix.add(phrase(text, mc), at, 1.0);
  }
  return master(mix, seconds: bars * bar + 1);
}

/// The whole album in running order: (title, renderer). Songs have an
/// instrumental too.
List<(String, Float32List Function())> tracks({bool vocals = true}) => [
  (
    'Needle Drop (Intro)',
    () {
      final s = songs[0];
      return _djTrack(
        s,
        [
          ['forward', 'forward', 'baby', 'baby'],
          ['chirp', 'chirp', 'transform', 'stab'],
          ['baby', 'tear', 'flare', 'scribble'],
          ['transform', 'chirp', 'stab', 'stab'],
        ],
        phrase('twelve bit science', lexicon, speed: 0.9),
        talk: vocals
            ? [
                (0.3, 'ladies and gentlemen', lexicon),
                (1.7, 'three little chips', sputnik),
                (3.0, 'one turntable', vox),
              ]
            : const [],
      );
    },
  ),
  for (final s in songs.take(3)) (s.title, () => renderSong(s, vocals: vocals)),
  (
    'Crossfade Kata (Interlude)',
    () => _djTrack(songs[2], [
      ['baby', 'baby', 'chirp', 'chirp'],
      ['transform', 'transform', 'flare', 'stab'],
      ['tear', 'tear', 'scribble', 'scribble'],
      ['chirp', 'flare', 'transform', 'stab'],
      ['baby', 'chirp', 'tear', 'flare'],
      ['transform', 'scribble', 'chirp', 'stab'],
    ], ahh(seed: 77)),
  ),
  for (final s in songs.sublist(3, 6))
    (s.title, () => renderSong(s, vocals: vocals)),
  (
    'Transformer (Interlude)',
    () => _djTrack(songs[4], [
      ['transform', 'transform', 'transform', 'stab'],
      ['transform', 'chirp', 'transform', 'chirp'],
      ['flare', 'transform', 'flare', 'transform'],
      ['transform', 'transform', 'scribble', 'stab'],
    ], horns(const [60, 63, 67], 0.5)),
  ),
  for (final s in songs.sublist(6))
    (s.title, () => renderSong(s, vocals: vocals)),
  (
    'Run-Out Groove (Outro)',
    () {
      final s = songs[7];
      final beat = 60 / s.bpm;
      final loop = makeLoop(s);
      // The needle locks in the run-out groove: two beats, round and round.
      final lock = Float32List.sublistView(loop, 0, (beat * 2 * sr).round());
      final mix = Mix(beat * 2 * 16 + 4);
      for (var i = 0; i < 16; i++) {
        mix.addWide(lock, i * beat * 2, 0.8 * (1 - i / 16));
      }
      mix.add(vinyl(beat * 32 + 3, 9, crackle: 3, hiss: 2), 0, 1);
      if (vocals) {
        mix.add(phrase('thank you for listening', vox), beat * 4, 1);
        mix.add(phrase('keep digging', lexicon), beat * 10, 1);
        mix.add(phrase('peace', sputnik), beat * 14, 1);
      }
      return master(mix, seconds: beat * 32 + 2);
    },
  ),
];

/// The lyric sheet (every song, who raps what).
String lyricSheet() {
  final b = StringBuffer()
    ..writeln('$albumTitle - $artist')
    ..writeln()
    ..writeln(
      'Lexicon (TI TMS5220), Sputnik (GI SP0256), Vox (Votrax SC-01): three speech chips.',
    )
    ..writeln('DJ Crossfade on the turntables. Original words and music.')
    ..writeln();
  for (final (i, t) in tracks().indexed) {
    b.writeln('${(i + 1).toString().padLeft(2, '0')}. ${t.$1}');
  }
  for (final s in songs) {
    b
      ..writeln()
      ..writeln('=' * 60)
      ..writeln('${s.title}  (${s.bpm.round()} BPM)')
      ..writeln('=' * 60);
    var hookDone = false;
    for (final sec in s.sections) {
      switch (sec.part) {
        case Part.verse:
          b
            ..writeln()
            ..writeln('[${sec.mc!.name}]');
          for (final l in sec.lines) {
            b.writeln(l);
          }
        case Part.hook:
          b
            ..writeln()
            ..writeln(
              '[Hook: ${sec.mcs.map((m) => m.name).join(', ')}, DJ Crossfade cutting "${s.scratchPhrase}"]',
            );
          if (!hookDone) {
            for (final l in sec.lines) {
              b.writeln(l);
            }
            hookDone = true;
          } else {
            b.writeln('(repeat)');
          }
        case Part.breakdown:
          b
            ..writeln()
            ..writeln('[DJ Crossfade: scratch break]');
        default:
      }
    }
  }
  return b.toString();
}
