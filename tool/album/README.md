# Twelve-Bit Science (The Allophones)

A 90s boom bap album made entirely with this repo's code: three speech
chips from `chip_synth` (TMS5220 "Lexicon", SP0256 "Sputnik", Votrax "Vox")
rap over synthesized "sampled" jazz loops (Rhodes, vibes, horns, strings,
piano, flute) put through a record player and an SP-1200 (wow and flutter,
26.04 kHz / 12-bit, crackle), swung drums, upright bass, and DJ Crossfade's
synthesized turntable scratches (baby, chirp, transformer, flare, tear,
scribble, stab). Original words and music, inspired by Artifacts and
Hieroglyphics.

    dart run bin/make_album.dart out          # all tracks + instrumentals + Lyrics.txt
    dart run bin/make_album.dart out 6        # one track
    dart run bin/check.dart out               # levels, clipping, gaps
    dart run bin/stems.dart out 3             # a song's beat / vocals / DJ stems

`lib/`: `dsp.dart` (filters, SP-1200, vinyl, room, compressor),
`instruments.dart`, `scratch.dart`, `rap.dart` (words fitted to the 16th
grid), `song.dart` (arrangement and mix), `album.dart` (the songs and
lyrics). CI (`.github/workflows/album.yml`) renders it into the
`album-latest` release.
