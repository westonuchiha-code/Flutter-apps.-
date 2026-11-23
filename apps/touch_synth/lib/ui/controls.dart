import 'package:chip_synth/chip_synth.dart';
import 'package:material_ui/material_ui.dart';

import '../app/synth_controller.dart';
import 'style.dart';

const _names = [
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
String noteName(int midi) => '${_names[midi % 12]}${midi ~/ 12 - 1}';

/// Tabbed sound controls beside the pad.
class ControlsPanel extends StatelessWidget {
  const ControlsPanel({super.key, required this.controller});

  final SynthController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: ColoredBox(
        color: Ui.panel,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Sound'),
                Tab(text: 'Filter'),
                Tab(text: 'Effects'),
                Tab(text: 'Pad'),
              ],
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final c = controller;
                  final s = c.spec;
                  void set(PolySpec n) => c.setSpec(n);
                  final analog = s.engine == EngineKind.analog;
                  return TabBarView(
                    children: [
                      _Page([
                        if (analog) ...[
                          _Row(
                            'Osc 1',
                            _Waves(s.osc1, (o) => set(s.copyWith(osc1: o))),
                          ),
                          _Row(
                            'Osc 2',
                            _Waves(s.osc2, (o) => set(s.copyWith(osc2: o))),
                          ),
                          _Slider(
                            'Osc 2 level',
                            s.osc2Mix,
                            (v) => set(s.copyWith(osc2Mix: v)),
                          ),
                          _Slider(
                            'Detune',
                            s.detune / 50,
                            (v) => set(s.copyWith(detune: v * 50)),
                            text: '${s.detune.round()} ct',
                          ),
                          _Slider(
                            'Sub osc',
                            s.sub,
                            (v) => set(s.copyWith(sub: v)),
                          ),
                          _Slider(
                            'Noise',
                            s.noise,
                            (v) => set(s.copyWith(noise: v)),
                          ),
                        ] else ...[
                          _Row(
                            'Chip',
                            DropdownButton<String>(
                              isExpanded: true,
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              value: s.chipId,
                              items: [
                                for (final chip in chipCatalog)
                                  DropdownMenuItem(
                                    value: chip.id,
                                    child: Text(chip.name),
                                  ),
                              ],
                              onChanged: (id) => set(
                                s.copyWith(
                                  chipId: id,
                                  patchId: chipById(id!).patches.first.id,
                                ),
                              ),
                            ),
                          ),
                          _Row(
                            'Sound',
                            DropdownButton<String>(
                              isExpanded: true,
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              value: chipById(s.chipId).patch(s.patchId).id,
                              items: [
                                for (final p in chipById(s.chipId).patches)
                                  DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.name),
                                  ),
                              ],
                              onChanged: (id) => set(s.copyWith(patchId: id)),
                            ),
                          ),
                          _Note(chipById(s.chipId).chip),
                        ],
                        _Slider(
                          'Glide',
                          s.glideMs / 300,
                          (v) => set(s.copyWith(glideMs: v * 300)),
                          text: '${s.glideMs.round()} ms',
                        ),
                      ]),
                      _Page([
                        if (analog) ...[
                          _Slider(
                            'Cutoff',
                            s.cutoff,
                            (v) => set(s.copyWith(cutoff: v)),
                          ),
                          _Slider(
                            'Resonance',
                            s.resonance,
                            (v) => set(s.copyWith(resonance: v)),
                          ),
                        ] else
                          const _Note(
                            'The chip engine has no filter. Finger height controls the sound shape instead.',
                          ),
                        _Slider(
                          'Attack',
                          s.attack / 2,
                          (v) => set(s.copyWith(attack: v * 2)),
                          text: '${(s.attack * 1000).round()} ms',
                        ),
                        _Slider(
                          'Release',
                          s.release / 3,
                          (v) => set(s.copyWith(release: v * 3)),
                          text: '${(s.release * 1000).round()} ms',
                        ),
                        if (analog)
                          _Row(
                            'Pad height',
                            SegmentedButton<YTarget>(
                              segments: const [
                                ButtonSegment(
                                  value: YTarget.filter,
                                  label: Text('Filter'),
                                ),
                                ButtonSegment(
                                  value: YTarget.volume,
                                  label: Text('Volume'),
                                ),
                                ButtonSegment(
                                  value: YTarget.both,
                                  label: Text('Both'),
                                ),
                              ],
                              selected: {s.yTarget},
                              showSelectedIcon: false,
                              onSelectionChanged: (v) =>
                                  set(s.copyWith(yTarget: v.first)),
                            ),
                          ),
                      ]),
                      _Page([
                        _Slider(
                          'Vibrato',
                          s.vibratoCents / 50,
                          (v) => set(s.copyWith(vibratoCents: v * 50)),
                          text: '${s.vibratoCents.round()} ct',
                        ),
                        _Slider(
                          'Vib. rate',
                          s.vibratoRate / 12,
                          (v) => set(s.copyWith(vibratoRate: v * 12)),
                          text: '${s.vibratoRate.toStringAsFixed(1)} Hz',
                        ),
                        _Slider(
                          'Drive',
                          s.drive,
                          (v) => set(s.copyWith(drive: v)),
                        ),
                        _Slider(
                          'Delay',
                          s.delayMix,
                          (v) => set(s.copyWith(delayMix: v)),
                        ),
                        _Slider(
                          'Delay time',
                          s.delayMs / 1000,
                          (v) => set(
                            s.copyWith(delayMs: (v * 1000).clamp(40, 1000)),
                          ),
                          text: '${s.delayMs.round()} ms',
                        ),
                        _Slider(
                          'Feedback',
                          s.delayFeedback / 0.9,
                          (v) => set(s.copyWith(delayFeedback: v * 0.9)),
                        ),
                        _Slider(
                          'Reverb',
                          s.reverbMix,
                          (v) => set(s.copyWith(reverbMix: v)),
                        ),
                      ]),
                      _Page([
                        _Slider(
                          'Lowest note',
                          (c.lowNote - 24) / 60,
                          (v) => c.setRange(low: 24 + (v * 60).round()),
                          text: noteName(c.lowNote),
                        ),
                        _Slider(
                          'Octaves',
                          (c.octaves - 1) / 4,
                          (v) => c.setRange(oct: 1 + (v * 4).round()),
                          text: '${c.octaves}',
                        ),
                        _Note(
                          'Range: ${noteName(c.lowNote)} – ${noteName(c.lowNote + c.octaves * 12)}. Up to $maxVoices fingers at once.',
                        ),
                      ]),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    children: children,
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.child);
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Ui.dim),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _Slider extends StatelessWidget {
  const _Slider(this.label, this.value, this.onChanged, {this.text});
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 84,
        child: Text(label, style: const TextStyle(fontSize: 13, color: Ui.dim)),
      ),
      Expanded(
        child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
      ),
      SizedBox(
        width: 52,
        child: Text(
          text ?? '${(value * 100).round()}',
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 12,
            color: Ui.text,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: const TextStyle(fontSize: 12, color: Ui.dim)),
  );
}

class _Waves extends StatelessWidget {
  const _Waves(this.value, this.onChanged);
  final Osc value;
  final ValueChanged<Osc> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<Osc>(
    segments: const [
      ButtonSegment(value: Osc.saw, label: Text('Saw')),
      ButtonSegment(value: Osc.square, label: Text('Sqr')),
      ButtonSegment(value: Osc.triangle, label: Text('Tri')),
      ButtonSegment(value: Osc.sine, label: Text('Sin')),
    ],
    selected: {value},
    showSelectedIcon: false,
    onSelectionChanged: (v) => onChanged(v.first),
  );
}
