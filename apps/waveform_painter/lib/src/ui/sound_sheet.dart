import 'package:chip_synth/chip_synth.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';

/// The synth settings that shape how the drawn wave sounds.
Future<void> showSoundSheet(BuildContext context, PainterController c) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => ListenableBuilder(
          listenable: c,
          builder: (context, _) => _SoundList(c: c, scroll: scroll),
        ),
      ),
    );

class _SoundList extends StatelessWidget {
  const _SoundList({required this.c, required this.scroll});

  final PainterController c;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final s = c.spec;
    void set(PolySpec next) => c.setSpec(next);
    String pct(double v) => '${(v * 100).round()}%';
    String ms(double sec) =>
        sec < 1 ? '${(sec * 1000).round()} ms' : '${sec.toStringAsFixed(1)} s';
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Sound', style: Theme.of(context).textTheme.titleLarge),
        _Knob(
          'Attack',
          ms(s.attack),
          s.attack,
          0.001,
          2,
          (v) => set(s.copyWith(attack: v)),
        ),
        _Knob(
          'Release',
          ms(s.release),
          s.release,
          0.01,
          4,
          (v) => set(s.copyWith(release: v)),
        ),
        _Knob(
          'Glide',
          '${s.glideMs.round()} ms',
          s.glideMs,
          0,
          500,
          (v) => set(s.copyWith(glideMs: v)),
        ),
        _Knob(
          'Filter',
          pct(s.cutoff),
          s.cutoff,
          0,
          1,
          (v) => set(s.copyWith(cutoff: v)),
        ),
        _Knob(
          'Resonance',
          pct(s.resonance),
          s.resonance,
          0,
          0.95,
          (v) => set(s.copyWith(resonance: v)),
        ),
        _Knob(
          'Sub octave',
          pct(s.sub),
          s.sub,
          0,
          1,
          (v) => set(s.copyWith(sub: v)),
        ),
        _Knob(
          'Drive',
          pct(s.drive),
          s.drive,
          0,
          1,
          (v) => set(s.copyWith(drive: v)),
        ),
        _Knob(
          'Vibrato',
          '${s.vibratoCents.round()} cents',
          s.vibratoCents,
          0,
          60,
          (v) => set(s.copyWith(vibratoCents: v)),
        ),
        _Knob(
          'Echo',
          pct(s.delayMix),
          s.delayMix,
          0,
          0.8,
          (v) => set(s.copyWith(delayMix: v)),
        ),
        _Knob(
          'Reverb',
          pct(s.reverbMix),
          s.reverbMix,
          0,
          0.8,
          (v) => set(s.copyWith(reverbMix: v)),
        ),
        _Knob(
          'Volume',
          pct(s.master),
          s.master,
          0,
          1,
          (v) => set(s.copyWith(master: v)),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => set(defaultSpec),
            child: const Text('Reset sound'),
          ),
        ),
      ],
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob(
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
    padding: const EdgeInsets.only(top: 6),
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
