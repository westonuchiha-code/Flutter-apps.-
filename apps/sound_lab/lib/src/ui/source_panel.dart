import 'package:chip_synth/chip_synth.dart';
import 'package:fx_kit/fx_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';

const noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
String noteName(int n) => '${noteNames[n % 12]}${n ~/ 12 - 1}';

/// Choose and shape the sound source.
class SourcePanel extends StatelessWidget {
  const SourcePanel({
    super.key,
    required this.c,
    required this.onLoadWave,
    required this.onLoadSample,
  });

  final LabController c;
  final VoidCallback onLoadWave;
  final VoidCallback onLoadSample;

  @override
  Widget build(BuildContext context) {
    final s = c.spec;
    final text = Theme.of(context).textTheme;
    void set(PolySpec n) => c.setSpec(n);
    String pct(double v) => '${(v * 100).round()}%';
    String secs(double v) =>
        v < 1 ? '${(v * 1000).round()} ms' : '${v.toStringAsFixed(1)} s';
    final envelope = [
      _Slider(
        'Attack',
        secs(s.attack),
        s.attack,
        0.001,
        2,
        (v) => set(s.copyWith(attack: v)),
      ),
      _Slider(
        'Release',
        secs(s.release),
        s.release,
        0.01,
        4,
        (v) => set(s.copyWith(release: v)),
      ),
    ];
    final filter = [
      _Slider(
        'Filter',
        pct(s.cutoff),
        s.cutoff,
        0,
        1,
        (v) => set(s.copyWith(cutoff: v)),
      ),
      _Slider(
        'Resonance',
        pct(s.resonance),
        s.resonance,
        0,
        0.95,
        (v) => set(s.copyWith(resonance: v)),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        SegmentedButton<SourceKind>(
          segments: const [
            ButtonSegment(value: SourceKind.analog, label: Text('Analog')),
            ButtonSegment(value: SourceKind.chip, label: Text('Chip')),
            ButtonSegment(value: SourceKind.wavetable, label: Text('Wave')),
            ButtonSegment(value: SourceKind.sample, label: Text('Sample')),
          ],
          selected: {c.source},
          showSelectedIcon: false,
          onSelectionChanged: (v) {
            final k = v.first;
            if (k == SourceKind.wavetable && c.waves.isEmpty) {
              onLoadWave();
            } else if (k == SourceKind.sample && c.sample == null) {
              onLoadSample();
            } else {
              c.setSource(k);
            }
          },
        ),
        const SizedBox(height: 8),
        ...switch (c.source) {
          SourceKind.analog => [
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Wave 1 '),
                    _OscPicker(
                      value: s.osc1,
                      onChanged: (o) => set(s.copyWith(osc1: o)),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Wave 2 '),
                    _OscPicker(
                      value: s.osc2,
                      onChanged: (o) => set(s.copyWith(osc2: o)),
                    ),
                  ],
                ),
              ],
            ),
            _Slider(
              'Wave 2 level',
              pct(s.osc2Mix),
              s.osc2Mix,
              0,
              1,
              (v) => set(s.copyWith(osc2Mix: v)),
            ),
            _Slider(
              'Detune',
              '${s.detune.round()} cents',
              s.detune,
              0,
              50,
              (v) => set(s.copyWith(detune: v)),
            ),
            _Slider(
              'Sub octave',
              pct(s.sub),
              s.sub,
              0,
              1,
              (v) => set(s.copyWith(sub: v)),
            ),
            _Slider(
              'Noise',
              pct(s.noise),
              s.noise,
              0,
              1,
              (v) => set(s.copyWith(noise: v)),
            ),
            ...filter,
            ...envelope,
            _Slider(
              'Glide',
              '${s.glideMs.round()} ms',
              s.glideMs,
              0,
              500,
              (v) => set(s.copyWith(glideMs: v)),
            ),
          ],
          SourceKind.chip => [
            DropdownButton<String>(
              isExpanded: true,
              value: chipById(s.chipId).id,
              items: [
                for (final ch in chipCatalog)
                  DropdownMenuItem(
                    value: ch.id,
                    child: Text(
                      '${ch.name} · ${ch.chip}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id != null) {
                  set(
                    s.copyWith(
                      chipId: id,
                      patchId: chipById(id).patches.first.id,
                    ),
                  );
                }
              },
            ),
            DropdownButton<String>(
              isExpanded: true,
              value: chipById(s.chipId).patch(s.patchId).id,
              items: [
                for (final p in chipById(s.chipId).patches)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (id) {
                if (id != null) set(s.copyWith(patchId: id));
              },
            ),
            if (chipById(s.chipId).patch(s.patchId).note case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(note, style: text.bodySmall),
              ),
            _Slider(
              'Release',
              secs(s.release),
              s.release,
              0.01,
              4,
              (v) => set(s.copyWith(release: v)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Chip sounds keep their machine\'s own pitch steps, volume steps and '
                'output filter; add effects after them.',
                style: text.bodySmall,
              ),
            ),
          ],
          SourceKind.wavetable => [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.waves),
              title: Text(c.waveName.isEmpty ? 'Drawn wave' : c.waveName),
              subtitle: Text(
                '${c.waves.length} wave${c.waves.length == 1 ? '' : 's'} from Waveform Painter',
              ),
              trailing: TextButton(
                onPressed: onLoadWave,
                child: const Text('Change'),
              ),
            ),
            if (c.waves.length > 1)
              _Slider('Morph', pct(c.morph), c.morph, 0, 1, c.setMorph),
            ...filter,
            ...envelope,
          ],
          SourceKind.sample => [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.graphic_eq),
              title: Text(c.sampleName.isEmpty ? 'Sample' : c.sampleName),
              subtitle: Text(
                '${((c.sample?.length ?? 0) / 48000).toStringAsFixed(1)} s',
              ),
              trailing: TextButton(
                onPressed: onLoadSample,
                child: const Text('Change'),
              ),
            ),
            Row(
              children: [
                const Expanded(child: Text('Plays at its own pitch on')),
                DropdownButton<int>(
                  value: c.sampleRoot,
                  items: [
                    for (var n = 36; n <= 84; n++)
                      DropdownMenuItem(value: n, child: Text(noteName(n))),
                  ],
                  onChanged: (n) {
                    if (n != null) c.setSampleRoot(n);
                  },
                ),
              ],
            ),
            ...envelope,
          ],
        },
      ],
    );
  }
}

class _OscPicker extends StatelessWidget {
  const _OscPicker({required this.value, required this.onChanged});
  final Osc value;
  final ValueChanged<Osc> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<Osc>(
    value: value,
    items: const [
      DropdownMenuItem(value: Osc.saw, child: Text('Saw')),
      DropdownMenuItem(value: Osc.square, child: Text('Square')),
      DropdownMenuItem(value: Osc.triangle, child: Text('Triangle')),
      DropdownMenuItem(value: Osc.sine, child: Text('Sine')),
    ],
    onChanged: (o) {
      if (o != null) onChanged(o);
    },
  );
}

class _Slider extends StatelessWidget {
  const _Slider(
    this.label,
    this.value,
    this.v,
    this.min,
    this.max,
    this.onChanged,
  );

  final String label, value;
  final double v, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value),
          ],
        ),
        Slider(
          value: v.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
