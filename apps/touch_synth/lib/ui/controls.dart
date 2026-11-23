import 'package:chip_synth/chip_synth.dart';
import 'package:material_ui/material_ui.dart';

import '../app/synth_controller.dart';

const _noteNames = [
  'C',
  'C♯',
  'D',
  'D♯',
  'E',
  'F',
  'F♯',
  'G',
  'G♯',
  'A',
  'A♯',
  'B',
];
String noteName(int midi) => '${_noteNames[midi % 12]}${midi ~/ 12 - 1}';

/// Sound-shaping panel beside the pad.
class ControlsPanel extends StatelessWidget {
  const ControlsPanel({super.key, required this.controller});

  final SynthController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final s = c.spec;
        void set(PolySpec n) => c.setSpec(n);
        final analog = s.engine == EngineKind.analog;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            if (c.audioError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  c.audioError!,
                  style: const TextStyle(color: Color(0xFFFF6B6B)),
                ),
              ),
            _Header('Presets'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in polyPresets.entries)
                  ActionChip(label: Text(e.key), onPressed: () => set(e.value)),
              ],
            ),
            _Header('Engine'),
            SegmentedButton<EngineKind>(
              segments: const [
                ButtonSegment(value: EngineKind.analog, label: Text('Analog')),
                ButtonSegment(value: EngineKind.chip, label: Text('Chip')),
              ],
              selected: {s.engine},
              showSelectedIcon: false,
              onSelectionChanged: (v) => set(s.copyWith(engine: v.first)),
            ),
            if (analog) ...[
              _Header('Oscillators'),
              _OscPicker('Osc 1', s.osc1, (o) => set(s.copyWith(osc1: o))),
              _OscPicker('Osc 2', s.osc2, (o) => set(s.copyWith(osc2: o))),
              _Knob('Osc 2 mix', s.osc2Mix, (v) => set(s.copyWith(osc2Mix: v))),
              _Knob(
                'Detune',
                s.detune / 50,
                (v) => set(s.copyWith(detune: v * 50)),
                label: '${s.detune.round()} ¢',
              ),
              _Knob('Sub', s.sub, (v) => set(s.copyWith(sub: v))),
              _Knob('Noise', s.noise, (v) => set(s.copyWith(noise: v))),
              _Header('Filter & envelope'),
              _Knob('Cutoff', s.cutoff, (v) => set(s.copyWith(cutoff: v))),
              _Knob(
                'Resonance',
                s.resonance,
                (v) => set(s.copyWith(resonance: v)),
              ),
              _Knob(
                'Attack',
                s.attack / 2,
                (v) => set(s.copyWith(attack: v * 2)),
                label: '${(s.attack * 1000).round()} ms',
              ),
            ] else ...[
              _Header('Chip'),
              DropdownButton<String>(
                isExpanded: true,
                value: s.chipId,
                items: [
                  for (final chip in chipCatalog)
                    DropdownMenuItem(
                      value: chip.id,
                      child: Text(
                        '${chip.name} · ${chip.chip.split(' ·').first}',
                      ),
                    ),
                ],
                onChanged: (id) => set(
                  s.copyWith(
                    chipId: id,
                    patchId: chipById(id!).patches.first.id,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in chipById(s.chipId).patches)
                    ChoiceChip(
                      label: Text(p.name),
                      selected: p.id == s.patchId,
                      onSelected: (_) => set(s.copyWith(patchId: p.id)),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Finger height controls the sound shape.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9AA3B0)),
                ),
              ),
            ],
            _Knob(
              'Release',
              s.release / 3,
              (v) => set(s.copyWith(release: v * 3)),
              label: '${(s.release * 1000).round()} ms',
            ),
            _Knob(
              'Glide',
              s.glideMs / 300,
              (v) => set(s.copyWith(glideMs: v * 300)),
              label: '${s.glideMs.round()} ms',
            ),
            if (analog) ...[
              const SizedBox(height: 6),
              const Text(
                'Finger height controls',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              SegmentedButton<YTarget>(
                segments: const [
                  ButtonSegment(value: YTarget.filter, label: Text('Filter')),
                  ButtonSegment(value: YTarget.volume, label: Text('Volume')),
                  ButtonSegment(value: YTarget.both, label: Text('Both')),
                ],
                selected: {s.yTarget},
                showSelectedIcon: false,
                onSelectionChanged: (v) => set(s.copyWith(yTarget: v.first)),
              ),
            ],
            _Header('Effects'),
            _Knob(
              'Vibrato',
              s.vibratoCents / 50,
              (v) => set(s.copyWith(vibratoCents: v * 50)),
              label: '${s.vibratoCents.round()} ¢',
            ),
            if (s.vibratoCents > 0)
              _Knob(
                'Vibrato speed',
                s.vibratoRate / 12,
                (v) => set(s.copyWith(vibratoRate: v * 12)),
                label: '${s.vibratoRate.toStringAsFixed(1)} Hz',
              ),
            _Knob('Drive', s.drive, (v) => set(s.copyWith(drive: v))),
            _Knob('Delay', s.delayMix, (v) => set(s.copyWith(delayMix: v))),
            if (s.delayMix > 0) ...[
              _Knob(
                'Delay time',
                s.delayMs / 1000,
                (v) => set(s.copyWith(delayMs: (v * 1000).clamp(40, 1000))),
                label: '${s.delayMs.round()} ms',
              ),
              _Knob(
                'Delay repeats',
                s.delayFeedback / 0.9,
                (v) => set(s.copyWith(delayFeedback: v * 0.9)),
              ),
            ],
            _Knob('Reverb', s.reverbMix, (v) => set(s.copyWith(reverbMix: v))),
            _Header('Pad range'),
            _Knob(
              'Lowest note',
              (c.lowNote - 24) / 60,
              (v) => c.setRange(low: 24 + (v * 60).round()),
              label: noteName(c.lowNote),
            ),
            _Knob(
              'Octaves',
              (c.octaves - 1) / 4,
              (v) => c.setRange(oct: 1 + (v * 4).round()),
              label: '${c.octaves}',
            ),
            _Header('Master'),
            _Knob('Volume', s.master, (v) => set(s.copyWith(master: v))),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        letterSpacing: 1.6,
        fontSize: 12,
        color: Color(0xFF39E0FF),
      ),
    ),
  );
}

class _Knob extends StatelessWidget {
  const _Knob(this.name, this.value, this.onChanged, {this.label});
  final String name;
  final double value;
  final ValueChanged<double> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 92,
        child: Text(name, style: const TextStyle(fontSize: 13)),
      ),
      Expanded(
        child: SliderTheme(
          data: const SliderThemeData(
            trackHeight: 3,
            overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
        ),
      ),
      SizedBox(
        width: 56,
        child: Text(
          label ?? '${(value * 100).round()}%',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
}

class _OscPicker extends StatelessWidget {
  const _OscPicker(this.name, this.value, this.onChanged);
  final String name;
  final Osc value;
  final ValueChanged<Osc> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(name, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: SegmentedButton<Osc>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: Osc.saw, label: Text('Saw')),
              ButtonSegment(value: Osc.square, label: Text('Sqr')),
              ButtonSegment(value: Osc.triangle, label: Text('Tri')),
              ButtonSegment(value: Osc.sine, label: Text('Sin')),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: (v) => onChanged(v.first),
          ),
        ),
      ],
    ),
  );
}
