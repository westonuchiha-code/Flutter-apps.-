import 'package:material_ui/material_ui.dart';

import '../app/theremin_controller.dart';
import '../core/music.dart';
import '../core/settings.dart';
import '../input/camera_backend.dart';

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
    void update(ThereminSettings next) => c.updateSettings(next);
    final text = Theme.of(context).textTheme;
    Widget header(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: text.titleSmall),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
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
            'Left half = pitch, right half = volume. '
            'Off: the whole image controls pitch.',
          ),
          value: s.twoZones,
          onChanged: (v) => update(s.copyWith(twoZones: v)),
        ),
        SwitchListTile(
          title: const Text('Less light = higher pitch'),
          subtitle: const Text('Like moving a hand closer to the antenna.'),
          value: s.invertPitch,
          onChanged: (v) => update(s.copyWith(invertPitch: v)),
        ),
        SwitchListTile(
          title: const Text('Less light = louder'),
          value: s.invertVolume,
          onChanged: s.twoZones
              ? (v) => update(s.copyWith(invertVolume: v))
              : null,
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
        header('Sound'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<Wave>(
            segments: [
              for (final w in Wave.values)
                ButtonSegment(value: w, label: Text(w.label)),
            ],
            selected: {s.wave},
            showSelectedIcon: false,
            onSelectionChanged: (v) => update(s.copyWith(wave: v.first)),
          ),
        ),
        _SliderTile(
          label: 'Master volume',
          valueLabel: '${(s.masterVolume * 100).round()}%',
          child: Slider(
            value: s.masterVolume,
            onChanged: (v) => update(s.copyWith(masterVolume: v)),
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
        header('How to play'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '1. Point the camera at a light, or lay your phone flat with the '
            'front camera facing up.\n'
            '2. Tap Calibrate and sweep your hand from covering the camera to '
            'fully away.\n'
            '3. Tap Play. With two zones, your left hand shades the pitch side '
            'and your right hand the volume side.\n'
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
