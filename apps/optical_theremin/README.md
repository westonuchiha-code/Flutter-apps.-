# Optical Theremin

A light-controlled chiptune synthesizer. Shade the camera with your hands to
play: the phone's camera on Android, or a webcam on Windows (and Linux).

## Playing
- **Two zones** (default): the left half of the image controls pitch, the
  right half controls **volume** or the **sound shape** (duty cycle, filter,
  FM brightness, vowel… depending on the sound).
- **Calibrate**: sweep your hand from covering the camera to fully away.
- **Touch pad**: play without a camera (left/right = pitch, up/down = second control).
- Pitch range, scale snapping, glide.

## Sound chips (emulated live)
| Machine | Chip | Sounds |
|---|---|---|
| Game Boy | DMG APU | Pulse (duty), Wave (4-bit wavetables, 4 volume steps), Wave Bass, Noise |
| NES | Ricoh 2A03 | Pulse, Triangle (no volume control), Triangle Bass, Noise |
| Commodore 64 | MOS 6581 SID | Filter Saw, PWM Lead, Sync Lead, Ring Bell, Filter Bass, Noise Sweep |
| ZX Spectrum | AY-3-8910 | Square (+noise), Buzzer, Sync Buzz, Noise |
| Master System | SN76489 | Square (folds below 109 Hz), Buzz Bass, Noise |
| Atari 2600 | TIA | Shape Shifter, Square, Lead, Bass, Buzz, Rumble (32 pitches per waveform) |
| Arcade | Namco WSG | Wavetable, Siren, Organ Bass |
| Genesis | YM2612 | FM Brass, E-Piano, Slap Bass, Bell, Growl (4-operator FM) |
| Speech | TMS5220 | Singing Vowels, Whisper (only its pitch-table pitches) |

Like the hardware: pitch is quantized to each chip's frequency registers,
volume uses its own volume steps, registers update once per video frame
(so slides step), and each machine's output filter is applied. Wavetables,
FM patches and the speech excitation are original designs in the style of
the hardware, not ROM copies.

**Effects:** frame-stepped vibrato, chip-style arpeggio, ping-pong echo,
bitcrush (bit depth and sample rate). Master volume.

## Recording & export
**Record** captures the performance (pitch, volume and shape 100×/s plus the
sound settings). Recordings can be played back, renamed, **re-voiced with
any other chip/effects**, and exported as 48 kHz stereo **WAV** (share sheet
on Android, Save dialog on Windows/Linux).

## How it works
| Part | Android | Windows / Linux |
|------|---------|-----------------|
| Camera frames | `camera` plugin image stream | [`light_capture`](../../packages/light_capture) plugin |
| Sound | chip synth (`lib/src/synth`, pure Dart) in a background isolate → `flutter_soloud` real-time stream | same |

Code: `lib/src/synth` (chips, engine, WAV), `lib/src/recording` (takes),
`lib/src/core` (theremin logic), `lib/src/input` (cameras), `lib/src/audio`,
`lib/src/app` (controller, settings, export), `lib/src/ui`.

Dev tools: `dart run tool/render_check.dart` (level/speed of every sound),
`dart run tool/demo.dart out.wav` (demo render).
