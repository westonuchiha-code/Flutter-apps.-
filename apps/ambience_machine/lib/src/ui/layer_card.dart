import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../scene.dart';

const _noteNames = [
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
String noteName(int n) => '${_noteNames[n % 12]}${n ~/ 12 - 1}';

IconData layerIcon(LayerSpec l) => switch (l.kind) {
  LayerKind.sample => Icons.graphic_eq,
  LayerKind.synth => Icons.piano_outlined,
  LayerKind.noise => switch (l.noise) {
    NoiseType.wind => Icons.air,
    NoiseType.rain => Icons.water_drop_outlined,
    NoiseType.waves => Icons.waves,
    NoiseType.rumble => Icons.landscape_outlined,
  },
};

String layerTitle(LayerSpec l, String sampleName) => l.name.isNotEmpty
    ? l.name
    : switch (l.kind) {
        LayerKind.sample => sampleName.isEmpty ? 'Recording' : sampleName,
        LayerKind.synth => (l.sound['name'] as String?) ?? 'Notes',
        LayerKind.noise => l.noise.label,
      };

/// One layer: live level, mute, volume; expands to all its settings.
class LayerCard extends StatefulWidget {
  const LayerCard({
    super.key,
    required this.layer,
    required this.level,
    required this.sampleName,
    required this.missing,
    required this.onChanged,
    required this.onRemove,
    this.onChangeSound,
  });

  final LayerSpec layer;
  final double level;
  final String sampleName;

  /// The sample isn't loaded (not in the Asset Locker any more).
  final bool missing;
  final ValueChanged<LayerSpec> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onChangeSound;

  @override
  State<LayerCard> createState() => _LayerCardState();
}

class _LayerCardState extends State<LayerCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.layer;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void set(LayerSpec n) => widget.onChanged(n);
    String pct(double v) => '${(v * 100).round()}%';
    // Level meter: dB-ish so quiet layers still show movement.
    final meter =
        (1 + (widget.level <= 0 ? -1.0 : (0.3 * _log10(widget.level)))).clamp(
          0.0,
          1.0,
        );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  Icon(
                    layerIcon(l),
                    color: l.muted ? theme.disabledColor : scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          layerTitle(l, widget.sampleName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: l.muted ? theme.disabledColor : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: l.muted ? 0 : meter,
                            minHeight: 5,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                        if (widget.missing)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Sample missing from the Asset Locker',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l.muted ? 'Unmute' : 'Mute',
                    icon: Icon(l.muted ? Icons.volume_off : Icons.volume_up),
                    onPressed: () => set(l.copyWith(muted: !l.muted)),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Slider(
              value: l.volume,
              onChanged: (v) => set(l.copyWith(volume: v)),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  _Knob(
                    'Drift',
                    pct(l.drift),
                    l.drift,
                    0,
                    1,
                    (v) => set(l.copyWith(drift: v)),
                  ),
                  _Knob(
                    'Drift speed',
                    l.driftSpeed < 0.33
                        ? 'slow (minutes)'
                        : (l.driftSpeed < 0.66 ? 'medium' : 'fast (seconds)'),
                    l.driftSpeed,
                    0,
                    1,
                    (v) => set(l.copyWith(driftSpeed: v)),
                  ),
                  _Knob(
                    'Pan',
                    l.pan.abs() < 0.05
                        ? 'centre'
                        : (l.pan < 0
                              ? 'left ${pct(-l.pan)}'
                              : 'right ${pct(l.pan)}'),
                    l.pan,
                    -1,
                    1,
                    (v) => set(l.copyWith(pan: v)),
                  ),
                  _Knob(
                    'Tone',
                    l.tone > 0.97 ? 'open' : pct(l.tone),
                    l.tone,
                    0,
                    1,
                    (v) => set(l.copyWith(tone: v)),
                  ),
                  ..._kindControls(context, l, set),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove layer'),
                      onPressed: widget.onRemove,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static double _log10(double x) => math.log(x) / math.ln10;

  List<Widget> _kindControls(
    BuildContext context,
    LayerSpec l,
    void Function(LayerSpec) set,
  ) {
    switch (l.kind) {
      case LayerKind.sample:
        return [
          _Knob(
            'Pitch',
            '${l.pitch > 0 ? '+' : ''}${l.pitch.round()} semitones',
            l.pitch,
            -12,
            12,
            (v) => set(l.copyWith(pitch: v.roundToDouble())),
          ),
        ];
      case LayerKind.noise:
        return [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<NoiseType>(
              segments: [
                for (final t in NoiseType.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {l.noise},
              showSelectedIcon: false,
              onSelectionChanged: (s) => set(l.copyWith(noise: s.first)),
            ),
          ),
        ];
      case LayerKind.synth:
        return [
          Row(
            children: [
              const Expanded(child: Text('Lowest note')),
              DropdownButton<int>(
                value: l.root,
                items: [
                  for (var n = 24; n <= 84; n++)
                    DropdownMenuItem(value: n, child: Text(noteName(n))),
                ],
                onChanged: (v) => set(l.copyWith(root: v)),
              ),
            ],
          ),
          Row(
            children: [
              const Expanded(child: Text('Scale')),
              DropdownButton<ScaleKind>(
                value: l.scale,
                items: [
                  for (final s in ScaleKind.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => set(l.copyWith(scale: v)),
              ),
            ],
          ),
          _Knob(
            'Range',
            '${l.octaves} octave${l.octaves == 1 ? '' : 's'}',
            l.octaves.toDouble(),
            1,
            4,
            (v) => set(l.copyWith(octaves: v.round())),
            divisions: 3,
          ),
          _Knob(
            'Notes',
            '${l.density.round()} per minute',
            l.density,
            1,
            60,
            (v) => set(l.copyWith(density: v.roundToDouble())),
          ),
          _Knob(
            'Note length',
            '${l.noteLength.toStringAsFixed(1)} s',
            l.noteLength,
            0.2,
            10,
            (v) => set(l.copyWith(noteLength: v)),
          ),
          if (widget.onChangeSound != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: Text(
                  l.sound.isEmpty ? 'Use a Sound Lab sound…' : 'Change sound…',
                ),
                onPressed: widget.onChangeSound,
              ),
            ),
        ];
    }
  }
}

class _Knob extends StatelessWidget {
  const _Knob(
    this.label,
    this.value,
    this.v,
    this.min,
    this.max,
    this.onChanged, {
    this.divisions,
  });

  final String label, value;
  final double v, min, max;
  final ValueChanged<double> onChanged;
  final int? divisions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Slider(
          value: v.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
