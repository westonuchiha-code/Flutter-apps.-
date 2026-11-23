import 'package:material_ui/material_ui.dart';

import '../app/theremin_controller.dart';
import '../core/settings.dart';
import '../core/music.dart';
import 'camera_view.dart';

/// Camera image with control zones, or the touch pad.
class PlaySurface extends StatelessWidget {
  const PlaySurface({super.key, required this.controller});

  final ThereminController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.usingTouch) return _TouchPad(controller: c);

    final frame = c.frame;
    final aspect = frame == null ? 4 / 3 : frame.width / frame.height;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraView(frame: frame),
              if (c.settings.twoZones)
                Row(
                  children: [
                    Expanded(
                      child: _Zone(
                        label: 'PITCH',
                        level: c.pitchControl,
                        color: Colors.cyanAccent,
                      ),
                    ),
                    Container(width: 2, color: Colors.white70),
                    Expanded(
                      child: _Zone(
                        label: c.settings.secondControl.label.toUpperCase(),
                        level: c.secondControl,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ],
                )
              else
                _Zone(
                  label: 'PITCH',
                  level: c.pitchControl,
                  color: Colors.cyanAccent,
                ),
              if (c.calibrating)
                _CalibrationOverlay(progress: c.calibrationProgress),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label and light-level bar drawn over one control zone.
class _Zone extends StatelessWidget {
  const _Zone({required this.label, required this.level, required this.color});

  final String label;
  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 80,
                    child: LinearProgressIndicator(
                      value: level,
                      color: color,
                      backgroundColor: Colors.white24,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalibrationOverlay extends StatelessWidget {
  const _CalibrationOverlay({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Calibrating…\nSweep your hand from covering the camera '
                'to fully away, a few times.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(value: progress),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fallback input: drag to play (left→right = pitch, bottom→top = volume).
class _TouchPad extends StatelessWidget {
  const _TouchPad({required this.controller});

  final ThereminController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        Offset normalize(Offset local) => Offset(
          local.dx / constraints.maxWidth,
          local.dy / constraints.maxHeight,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => controller.touch(normalize(d.localPosition)),
          onPanUpdate: (d) => controller.touch(normalize(d.localPosition)),
          onPanEnd: (_) => controller.releaseTouch(),
          onPanCancel: controller.releaseTouch,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [scheme.primaryContainer, scheme.tertiaryContainer],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      'Touch pad',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: Text('← lower pitch      higher pitch →'),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        controller.settings.secondControl ==
                                SecondControl.volume
                            ? 'quieter      louder →'
                            : 'less shape      more shape →',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Current note, frequency and volume.
class NoteReadout extends StatelessWidget {
  const NoteReadout({super.key, required this.controller});

  final ThereminController controller;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    final text = Theme.of(context).textTheme;
    final midi = engine.targetMidi.round().clamp(0, 127);
    return Row(
      children: [
        Text(
          noteName(midi),
          style: text.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${engine.frequency.toStringAsFixed(1)} Hz',
                style: text.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: controller.playing ? engine.volume : 0,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
