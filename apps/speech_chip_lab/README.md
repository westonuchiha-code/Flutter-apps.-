# Speech Chip Lab

Windows, Android, Linux. Built on `app_shell`, `audio_kit` and
`chip_synth` (speech engine in `packages/chip_synth/lib/src/speech/`).

- Type text; see each word's sounds and tap a word to fix them by hand.
  `[HH EH L OW]` in the text gives exact sounds; the sounds list explains
  every code.
- Three speech chips, recreated from public descriptions of the hardware
  (not copies of their internal speech data):
  - TI TMS5220: 8 kHz, 25 ms frames with smooth steps, its pitch table,
    16 loudness steps, chirp excitation, 8-bit output.
  - GI SP0256: 10 kHz, 10 ms frames that jump, pulse excitation, 8-bit
    filter numbers, 7-bit output.
  - Votrax SC-01: smooth analog formants, only 4 pitch steps; the clock sets
    pitch, voice size and speed together.
- Pitch (Votrax: clock), speed, flat/statement/question, whisper.
- Sing: each key on the keyboard sings the next word at that note and holds
  its vowel while held; slide to bend.
- Save to the Asset Locker (Samples) for Sample Pad, Sound Lab and Ambience
  Machine, or export a WAV.
