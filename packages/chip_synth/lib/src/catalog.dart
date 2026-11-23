// The list of chips and sounds shown in the app.
import 'chips.dart';

/// One playable sound on a chip.
class PatchInfo {
  const PatchInfo({
    required this.id,
    required this.name,
    this.shape,
    this.transpose = 0,
    this.note,
  });

  /// Stored in settings and recordings; never rename.
  final String id;
  final String name;

  /// What the shape control does, or null if this sound has none.
  final String? shape;

  /// Semitones added to the played pitch (bass sounds play lower).
  final int transpose;

  /// Hardware quirk worth knowing, shown under the sound list.
  final String? note;
}

/// One emulated chip.
class ChipInfo {
  const ChipInfo({
    required this.id,
    required this.name,
    required this.chip,
    required this.fps,
    required this.highPassHz,
    required this.lowPassHz,
    required this.patches,
    required this.create,
  });

  final String id;

  /// Machine name, e.g. "Game Boy".
  final String name;

  /// Chip description, e.g. "DMG APU · 4-bit".
  final String chip;

  /// Video frame rate: the sound driver updates the chip once per frame.
  final double fps;

  /// Output stage of the machine.
  final double highPassHz;
  final double lowPassHz;

  final List<PatchInfo> patches;
  final ChipVoice Function(String patchId, double sampleRate) create;

  PatchInfo patch(String id) =>
      patches.firstWhere((p) => p.id == id, orElse: () => patches.first);
}

final List<ChipInfo> chipCatalog = [
  ChipInfo(
    id: 'gb',
    name: 'Game Boy',
    chip: 'DMG APU · pulse / 4-bit wave / noise',
    fps: 59.73,
    highPassHz: 20,
    lowPassHz: 12000,
    patches: const [
      PatchInfo(id: 'pulse', name: 'Pulse', shape: 'Duty cycle'),
      PatchInfo(
        id: 'wave',
        name: 'Wave',
        shape: 'Wavetable',
        note: 'The wave channel only has 4 volume levels.',
      ),
      PatchInfo(
        id: 'wavebass',
        name: 'Wave Bass',
        shape: 'Wavetable',
        transpose: -12,
      ),
      PatchInfo(id: 'noise', name: 'Noise', shape: 'Metallic mode'),
    ],
    create: (id, sr) => switch (id) {
      'wave' || 'wavebass' => GbWave(sr),
      'noise' => GbNoise(sr),
      _ => GbPulse(sr),
    },
  ),
  ChipInfo(
    id: 'nes',
    name: 'NES',
    chip: 'Ricoh 2A03 · pulse / triangle / noise',
    fps: 60.10,
    highPassHz: 90,
    lowPassHz: 14000,
    patches: const [
      PatchInfo(id: 'pulse', name: 'Pulse', shape: 'Duty cycle'),
      PatchInfo(
        id: 'triangle',
        name: 'Triangle',
        note: 'The triangle has no volume control: it is only on or off.',
      ),
      PatchInfo(
        id: 'tribass',
        name: 'Triangle Bass',
        transpose: -12,
        note: 'The triangle has no volume control: it is only on or off.',
      ),
      PatchInfo(id: 'noise', name: 'Noise', shape: 'Metallic mode'),
    ],
    create: (id, sr) => switch (id) {
      'triangle' || 'tribass' => NesTriangle(sr),
      'noise' => NesNoise(sr),
      _ => NesPulse(sr),
    },
  ),
  ChipInfo(
    id: 'sid',
    name: 'Commodore 64',
    chip: 'MOS 6581 SID · filter, sync, ring mod',
    fps: 50.125,
    highPassHz: 15,
    lowPassHz: 15000,
    patches: const [
      PatchInfo(id: 'saw', name: 'Filter Saw', shape: 'Filter cutoff'),
      PatchInfo(id: 'pwm', name: 'PWM Lead', shape: 'Pulse width'),
      PatchInfo(id: 'sync', name: 'Sync Lead', shape: 'Sync ratio'),
      PatchInfo(id: 'ring', name: 'Ring Bell', shape: 'Ring ratio'),
      PatchInfo(
        id: 'bass',
        name: 'Filter Bass',
        shape: 'Filter cutoff',
        transpose: -12,
      ),
      PatchInfo(id: 'noise', name: 'Noise Sweep', shape: 'Filter cutoff'),
    ],
    create: (id, sr) => SidVoice(sr, switch (id) {
      'pwm' => SidPatch.pwm,
      'sync' => SidPatch.sync,
      'ring' => SidPatch.ring,
      'bass' => SidPatch.filterBass,
      'noise' => SidPatch.noise,
      _ => SidPatch.saw,
    }),
  ),
  ChipInfo(
    id: 'ay',
    name: 'ZX Spectrum',
    chip: 'AY-3-8910 · squares, noise, envelope buzz',
    fps: 50.08,
    highPassHz: 20,
    lowPassHz: 12000,
    patches: const [
      PatchInfo(id: 'square', name: 'Square', shape: 'Noise mix'),
      PatchInfo(
        id: 'buzz',
        name: 'Buzzer',
        shape: 'Saw / triangle',
        note: 'Envelope sounds ignore the volume register: on or off only.',
      ),
      PatchInfo(
        id: 'syncbuzz',
        name: 'Sync Buzz',
        shape: 'Tone ratio',
        note: 'Envelope sounds ignore the volume register: on or off only.',
      ),
      PatchInfo(id: 'noise', name: 'Noise'),
    ],
    create: (id, sr) => AyVoice(sr, switch (id) {
      'buzz' => AyPatch.buzz,
      'syncbuzz' => AyPatch.syncBuzz,
      'noise' => AyPatch.noise,
      _ => AyPatch.square,
    }),
  ),
  ChipInfo(
    id: 'sms',
    name: 'Master System',
    chip: 'SN76489 · squares, periodic noise',
    fps: 59.92,
    highPassHz: 20,
    lowPassHz: 12000,
    patches: const [
      PatchInfo(
        id: 'square',
        name: 'Square',
        note: 'Cannot play below about 109 Hz: low notes fold up an octave.',
      ),
      PatchInfo(id: 'buzz', name: 'Buzz Bass', transpose: -12),
      PatchInfo(id: 'noise', name: 'Noise'),
    ],
    create: (id, sr) => SnVoice(sr, switch (id) {
      'buzz' => SnPatch.buzzBass,
      'noise' => SnPatch.noise,
      _ => SnPatch.square,
    }),
  ),
  ChipInfo(
    id: 'tia',
    name: 'Atari 2600',
    chip: 'TIA · 32 pitches per waveform',
    fps: 59.92,
    highPassHz: 20,
    lowPassHz: 10000,
    patches: const [
      PatchInfo(
        id: 'shift',
        name: 'Shape Shifter',
        shape: 'Waveform',
        note: 'Only 32 pitches per waveform, so notes are often way off.',
      ),
      PatchInfo(id: 'square', name: 'Square'),
      PatchInfo(id: 'lead', name: 'Lead'),
      PatchInfo(id: 'bass', name: 'Bass', transpose: -12),
      PatchInfo(id: 'buzz', name: 'Buzz'),
      PatchInfo(id: 'noise', name: 'Rumble'),
    ],
    create: (id, sr) => TiaVoice(sr, fixedPattern: id == 'shift' ? null : id),
  ),
  ChipInfo(
    id: 'wsg',
    name: 'Arcade',
    chip: 'Namco WSG · 4-bit wavetables',
    fps: 60.61,
    highPassHz: 20,
    lowPassHz: 9000,
    patches: const [
      PatchInfo(id: 'wave', name: 'Wavetable', shape: 'Wavetable'),
      PatchInfo(id: 'siren', name: 'Siren', shape: 'Siren depth'),
      PatchInfo(id: 'bass', name: 'Organ Bass', transpose: -12),
    ],
    create: (id, sr) => switch (id) {
      'siren' => WsgVoice(sr, fixedWave: 0, siren: true),
      'bass' => WsgVoice(sr, fixedWave: 3),
      _ => WsgVoice(sr),
    },
  ),
  ChipInfo(
    id: 'fm',
    name: 'Genesis',
    chip: 'Yamaha YM2612 · 4-operator FM',
    fps: 59.92,
    highPassHz: 20,
    lowPassHz: 3400,
    patches: const [
      PatchInfo(id: 'brass', name: 'FM Brass', shape: 'Brightness'),
      PatchInfo(id: 'epiano', name: 'E-Piano', shape: 'Brightness'),
      PatchInfo(
        id: 'bass',
        name: 'Slap Bass',
        shape: 'Brightness',
        transpose: -12,
      ),
      PatchInfo(id: 'bell', name: 'Bell', shape: 'Brightness'),
      PatchInfo(id: 'growl', name: 'Growl', shape: 'Brightness'),
    ],
    create: (id, sr) => FmVoice(sr, fmPatches[id] ?? fmPatches['brass']!),
  ),
  ChipInfo(
    id: 'speech',
    name: 'Speech',
    chip: 'TI TMS5220 · LPC speech, 8 kHz',
    fps: 40,
    highPassHz: 60,
    lowPassHz: 3800,
    patches: const [
      PatchInfo(
        id: 'vowels',
        name: 'Singing Vowels',
        shape: 'Vowel (oo → ee)',
        note: 'Only the pitches in the chip\'s pitch table can be sung.',
      ),
      PatchInfo(id: 'whisper', name: 'Whisper', shape: 'Vowel (oo → ee)'),
    ],
    create: (id, sr) => SpeechVoice(sr, whisper: id == 'whisper'),
  ),
];

ChipInfo chipById(String id) =>
    chipCatalog.firstWhere((c) => c.id == id, orElse: () => chipCatalog.first);
