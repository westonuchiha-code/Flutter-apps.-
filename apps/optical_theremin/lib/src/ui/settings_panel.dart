import 'package:material_ui/material_ui.dart';

import '../app/theremin_controller.dart';
import '../core/music.dart';
import '../core/settings.dart';
import '../input/camera_backend.dart';

import 'package:chip_synth/chip_synth.dart';

import 'sound_picker.dart';

/// All theremin settings, as a scrollable list.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.controller});

  final ThereminController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildList(context),
    );
  }

  Widget _buildList(BuildContext context) {
    final c = controller;
    final s = c.settings;
    final sound = s.sound;
    void update(ThereminSettings next) => c.updateSettings(next);
    void updateSound(SoundSpec next) => c.updateSound(next);
    final patch = chipById(sound.chipId).patch(sound.patchId);
    final text = Theme.of(context).textTheme;
    Widget header(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: text.titleSmall),
    );
    final secondIsShape = s.secondControl == SecondControl.shape;
    final shapeFixed = !secondIsShape || (!s.twoZones && !c.usingTouch);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        header('Sound chip'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SoundPicker(spec: sound, onChanged: updateSound),
        ),
        _SliderTile(
          label: patch.shape == null
              ? 'Sound shape (not used by this sound)'
              : 'Sound shape: ${patch.shape}',
          valueLabel: shapeFixed
              ? '${(s.shape * 100).round()}%'
              : 'second hand',
          child: Slider(
            value: s.shape,
            onChanged: shapeFixed && patch.shape != null
                ? (v) => update(s.copyWith(shape: v))
                : null,
          ),
        ),
        _SliderTile(
          label: 'Master volume',
          valueLabel: '${(sound.master * 100).round()}%',
          child: Slider(
            value: sound.master,
            onChanged: (v) => updateSound(sound.copyWith(master: v)),
          ),
        ),
        header('Effects'),
        _SliderTile(
          label: 'Vibrato depth',
          valueLabel: sound.vibratoCents == 0
              ? 'Off'
              : '${sound.vibratoCents.round()} cents',
          child: Slider(
            value: sound.vibratoCents,
            max: 100,
            divisions: 20,
            onChanged: (v) => updateSound(sound.copyWith(vibratoCents: v)),
          ),
        ),
        if (sound.vibratoCents > 0)
          _SliderTile(
            label: 'Vibrato speed',
            valueLabel: '${sound.vibratoRate.toStringAsFixed(1)} Hz',
            child: Slider(
              value: sound.vibratoRate,
              min: 1,
              max: 12,
              onChanged: (v) => updateSound(sound.copyWith(vibratoRate: v)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Expanded(child: Text('Arpeggio')),
              DropdownButton<String>(
                value: sound.arp,
                items: [
                  for (final e in arpLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => updateSound(sound.copyWith(arp: v)),
              ),
            ],
          ),
        ),
        if (sound.arp != 'off')
          _SliderTile(
            label: 'Arpeggio speed',
            valueLabel:
                '${sound.arpFrames} frame${sound.arpFrames == 1 ? '' : 's'} '
                'per note',
            child: Slider(
              value: sound.arpFrames.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              onChanged: (v) =>
                  updateSound(sound.copyWith(arpFrames: v.round())),
            ),
          ),
        _SliderTile(
          label: 'Echo',
          valueLabel: sound.echoMix == 0
              ? 'Off'
              : '${(sound.echoMix * 100).round()}%',
          child: Slider(
            value: sound.echoMix,
            onChanged: (v) => updateSound(sound.copyWith(echoMix: v)),
          ),
        ),
        if (sound.echoMix > 0) ...[
          _SliderTile(
            label: 'Echo time',
            valueLabel: '${sound.echoMs.round()} ms',
            child: Slider(
              value: sound.echoMs,
              min: 60,
              max: 900,
              onChanged: (v) => updateSound(sound.copyWith(echoMs: v)),
            ),
          ),
          _SliderTile(
            label: 'Echo repeats',
            valueLabel: '${(sound.echoFeedback / 0.85 * 100).round()}%',
            child: Slider(
              value: sound.echoFeedback,
              max: 0.85,
              onChanged: (v) => updateSound(sound.copyWith(echoFeedback: v)),
            ),
          ),
        ],
        _SliderTile(
          label: 'Bitcrush: bit depth',
          valueLabel: sound.crushBits == 0 ? 'Off' : '${sound.crushBits}-bit',
          child: Slider(
            // 0 = off, then 8 down to 2 bits (more crush to the right).
            value: sound.crushBits == 0 ? 0 : (9 - sound.crushBits).toDouble(),
            max: 7,
            divisions: 7,
            onChanged: (v) => updateSound(
              sound.copyWith(crushBits: v == 0 ? 0 : 9 - v.round()),
            ),
          ),
        ),
        _SliderTile(
          label: 'Bitcrush: sample rate',
          valueLabel: sound.crushHold <= 1 ? 'Off' : '÷${sound.crushHold}',
          child: Slider(
            value: sound.crushHold.toDouble(),
            min: 1,
            max: 16,
            divisions: 15,
            onChanged: (v) => updateSound(sound.copyWith(crushHold: v.round())),
          ),
        ),
        header('Controller'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButton<CameraOption?>(
            isExpanded: true,
            value: c.camera,
            items: [
              for (final camera in c.cameras)
                DropdownMenuItem(value: camera, child: Text(camera.label)),
              const DropdownMenuItem(value: null, child: Text('Touch pad')),
            ],
            onChanged: c.calibrating ? null : c.selectCamera,
          ),
        ),
        SwitchListTile(
          title: const Text('Two zones'),
          subtitle: const Text(
            'Left half = pitch, right half = second hand. '
            'Off: the whole image controls pitch.',
          ),
          value: s.twoZones,
          onChanged: (v) => update(s.copyWith(twoZones: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              const Expanded(child: Text('Second hand controls')),
              SegmentedButton<SecondControl>(
                segments: [
                  for (final m in SecondControl.values)
                    ButtonSegment(value: m, label: Text(m.label)),
                ],
                selected: {s.secondControl},
                showSelectedIcon: false,
                onSelectionChanged: (v) =>
                    update(s.copyWith(secondControl: v.first)),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Less light = higher pitch'),
          subtitle: const Text('Like moving a hand closer to the antenna.'),
          value: s.invertPitch,
          onChanged: (v) => update(s.copyWith(invertPitch: v)),
        ),
        SwitchListTile(
          title: Text(
            secondIsShape ? 'Less light = more shape' : 'Less light = louder',
          ),
          value: s.invertSecond,
          onChanged: (v) => update(s.copyWith(invertSecond: v)),
        ),
        SwitchListTile(
          title: const Text('Lock camera exposure'),
          subtitle: Text(
            c.exposureLockWorked == false
                ? 'This camera does not support locking; it may adjust to '
                      'light changes on its own.'
                : 'Stops the camera from cancelling out your light changes.',
          ),
          value: s.lockExposure,
          onChanged: c.usingTouch
              ? null
              : (v) => update(s.copyWith(lockExposure: v)),
        ),
        SwitchListTile(
          title: const Text('Mirror image'),
          value: s.mirror,
          onChanged: c.usingTouch ? null : (v) => update(s.copyWith(mirror: v)),
        ),
        header('Notes'),
        _SliderTile(
          label: 'Range',
          valueLabel: '${noteName(s.lowNote)} – ${noteName(s.highNote)}',
          child: RangeSlider(
            values: RangeValues(s.lowNote.toDouble(), s.highNote.toDouble()),
            min: 24,
            max: 96,
            divisions: 72,
            labels: RangeLabels(noteName(s.lowNote), noteName(s.highNote)),
            onChanged: (r) {
              final low = r.start.round();
              final high = r.end.round();
              if (high - low >= 5) {
                update(s.copyWith(lowNote: low, highNote: high));
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButton<ScaleType>(
                  isExpanded: true,
                  value: s.scale,
                  items: [
                    for (final scale in ScaleType.values)
                      DropdownMenuItem(value: scale, child: Text(scale.label)),
                  ],
                  onChanged: (v) => update(s.copyWith(scale: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: s.root,
                  items: [
                    for (var i = 0; i < 12; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(pitchClassName(i)),
                      ),
                  ],
                  onChanged:
                      s.scale == ScaleType.continuous ||
                          s.scale == ScaleType.chromatic
                      ? null
                      : (v) => update(s.copyWith(root: v)),
                ),
              ),
            ],
          ),
        ),
        _SliderTile(
          label: 'Glide',
          valueLabel: '${s.glideMs.round()} ms',
          child: Slider(
            value: s.glideMs,
            max: 400,
            divisions: 40,
            onChanged: (v) => update(s.copyWith(glideMs: v)),
          ),
        ),
        header('How to play'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '1. Point the camera at a light, or lay your phone flat with the '
            'front camera facing up.\n'
            '2. Tap Calibrate and sweep your hand from covering the camera to '
            'fully away.\n'
            '3. Tap Play. Your left hand shades the pitch side; your right '
            'hand controls volume or the sound shape.\n'
            '4. Tap Record to capture a performance. Recordings can be '
            'replayed, switched to another chip and exported as WAV.\n'
            'No camera? Choose "Touch pad" above.',
          ),
        ),
      ],
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.valueLabel,
    required this.child,
  });

  final String label;
  final String valueLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(valueLabel),
            ],
          ),
          child,
        ],
      ),
    );
  }
}
