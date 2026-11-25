# mp3_kit

Pure-Dart MP3 encoder: MPEG-1 Layer III, 44.1 kHz, mono or stereo
(mid/side when it helps), constant bitrate 32-320 kbps, ID3v2.3 tags.
Works everywhere (no native code).

```dart
final mp3 = encodeMp3(pcm16, channels: 2, kbps: 320,
    tags: const Mp3Tags(title: 'Liquid Logic', artist: 'The Allophones'));
```

How it is built:

- The Huffman codes are generated (`tool/gen_tables.dart`) from the
  tables of dr_mp3, the decoder flutter_soloud ships; the subband filter
  and IMDCT are ported from it (`synth.dart`). The encoder probes them and
  applies their transposes, so encode → decode reconstructs within -88 dB
  before quantization.
- Quantization: one global gain per granule shared by both channels
  (binary search to fill the frame), scalefactors that let the noise
  follow part of the spectrum, best Huffman tables and region split.
- Simplifications: long blocks only (no short blocks, so sharp attacks can
  pre-echo a little), no bit reservoir, nothing above 19.5 kHz.

`lib/src/check_decoder.dart` decodes what the encoder writes (for tests and
`tool/check.dart song.wav [kbps] [out.mp3]`, which prints SNR and speed:
about 4× real time for stereo here).
