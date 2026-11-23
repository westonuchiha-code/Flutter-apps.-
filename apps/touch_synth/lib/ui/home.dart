import 'package:chip_synth/chip_synth.dart';
import 'package:material_ui/material_ui.dart';

import '../app/synth_controller.dart';
import 'controls.dart';
import 'pad.dart';
import 'style.dart';

class SynthHome extends StatelessWidget {
  const SynthHome({super.key, required this.controller});

  final SynthController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(controller: controller),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        final s = controller.spec;
                        final label = s.engine == EngineKind.chip
                            ? 'Shape'
                            : switch (s.yTarget) {
                                YTarget.filter => 'Brightness',
                                YTarget.volume => 'Volume',
                                YTarget.both => 'Brightness + volume',
                              };
                        return TouchPad(controller: controller, yLabel: label);
                      },
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 340,
                    child: ControlsPanel(controller: controller),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});
  final SynthController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.spec;
        final preset = polyPresets.entries
            .where((e) => e.value == s)
            .map((e) => e.key)
            .firstOrNull;
        return Container(
          height: 48,
          color: Ui.panel,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Text(
                'Touch Synth',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Ui.text,
                ),
              ),
              const SizedBox(width: 20),
              PopupMenuButton<String>(
                tooltip: 'Presets',
                onSelected: (k) => controller.setSpec(polyPresets[k]!),
                itemBuilder: (_) => [
                  for (final k in polyPresets.keys)
                    PopupMenuItem(value: k, child: Text(k)),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Ui.line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Text(
                        preset ?? 'Custom',
                        style: const TextStyle(fontSize: 13, color: Ui.text),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.expand_more, size: 18, color: Ui.dim),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<EngineKind>(
                segments: const [
                  ButtonSegment(
                    value: EngineKind.analog,
                    label: Text('Analog'),
                  ),
                  ButtonSegment(value: EngineKind.chip, label: Text('Chip')),
                ],
                selected: {s.engine},
                showSelectedIcon: false,
                onSelectionChanged: (v) =>
                    controller.setSpec(s.copyWith(engine: v.first)),
              ),
              if (controller.audioError != null) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.volume_off,
                  color: Color(0xFFE5484D),
                  size: 18,
                ),
              ],
              const Spacer(),
              const Icon(Icons.volume_up, size: 18, color: Ui.dim),
              SizedBox(
                width: 160,
                child: Slider(
                  value: s.master,
                  onChanged: (v) => controller.setSpec(s.copyWith(master: v)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
