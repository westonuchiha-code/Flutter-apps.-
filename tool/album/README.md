# Twelve-Bit Science (The Allophones)

A 90s boom bap album made entirely with this repo's code, now
instrumental (the owner dropped the chip-voice raps: `VOCALS=1` still
renders them, and `bin/sample.dart` makes short vocal test takes):
synthesized "sampled" jazz loops (Rhodes, vibes, horns, strings,
piano, flute) put through a record player and an SP-1200 (wow and flutter,
26.04 kHz / 12-bit, crackle), swung drums, upright bass, and DJ Crossfade's
synthesized turntable scratches (baby, chirp, transformer, flare, tear,
scribble, stab). Original words and music, inspired by Artifacts and
Hieroglyphics.

    dart run bin/make_album.dart out          # all tracks (WAV + 320 kbps MP3)
    dart run bin/make_album.dart out 6        # one track
    dart run bin/check.dart out               # levels, clipping, gaps
    dart run bin/stems.dart out 3             # a song's beat / vocals / DJ stems

`lib/`: `dsp.dart` (filters, SP-1200, vinyl, room, compressor),
`instruments.dart`, `scratch.dart`, `rap.dart` (words fitted to the 16th
grid), `song.dart` (arrangement and mix), `album.dart` (the songs and
lyrics). CI (`.github/workflows/album.yml`) renders it into the
`album-latest` release.

## Songs for the music video styles

`lib/style_songs.dart` gives each Puppet Stage video style its own song:
Liberation and Backyard (new boom bap beats), Cipher (Liquid Logic), and
three band songs from `lib/band.dart`, a bar-by-bar engine with new
synthesized instruments (plucked and distorted guitar, synth and slap
bass, wah clavinet, trumpet, synth whistle, toms, claps) in any meter:
Undertow (7/8 prog-metal), Deadpan (dry alt-rock with trumpet), Mothership
(space funk).

    dart run bin/style_takes.dart out [style ...]   # song WAV/MP3, songmap, 30 s take MP3
