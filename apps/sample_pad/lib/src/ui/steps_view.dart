import 'package:beat_kit/beat_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import 'pads_view.dart';

/// Step grid: one row per loaded pad, 16 steps visible at a time.
class StepsView extends StatefulWidget {
  const StepsView({super.key, required this.c});

  final PadController c;

  @override
  State<StepsView> createState() => _StepsViewState();
}

class _StepsViewState extends State<StepsView> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final theme = Theme.of(context);
    final rows = [
      for (var i = 0; i < padCount; i++)
        if (!c.pads[i].isEmpty) i,
    ];
    final page = c.steps > 16 ? _page : 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 16, label: Text('16 steps')),
                  ButtonSegment(value: 32, label: Text('32')),
                ],
                selected: {c.steps},
                showSelectedIcon: false,
                onSelectionChanged: (s) => c.setSteps(s.first),
              ),
              const Spacer(),
              if (c.steps > 16)
                IconButton(
                  tooltip: page == 0 ? 'Steps 17–32' : 'Steps 1–16',
                  icon: Icon(
                    page == 0 ? Icons.chevron_right : Icons.chevron_left,
                  ),
                  onPressed: () => setState(() => _page = 1 - page),
                ),
              IconButton(
                tooltip: 'Clear pattern',
                icon: const Icon(Icons.layers_clear_outlined),
                onPressed: c.clearPattern,
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Load sounds onto pads first; each loaded pad gets a row here.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final p in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(
                                c.pads[p].name.isEmpty
                                    ? 'Pad ${p + 1}'
                                    : c.pads[p].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                            for (var k = 0; k < 16; k++)
                              Expanded(
                                child: _Cell(
                                  on: c.stepOn(p, page * 16 + k),
                                  now: c.currentStep == page * 16 + k,
                                  beat: k % 4 == 0,
                                  color: padColor(p, theme.brightness),
                                  onTap: () => c.toggleStep(p, page * 16 + k),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.on,
    required this.now,
    required this.beat,
    required this.color,
    required this.onTap,
  });

  final bool on, now, beat;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 0.8,
        child: Container(
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: on
                ? color
                : (beat
                      ? scheme.surfaceContainerHighest
                      : scheme.surfaceContainer),
            borderRadius: BorderRadius.circular(4),
            border: now ? Border.all(color: scheme.onSurface, width: 2) : null,
          ),
        ),
      ),
    );
  }
}
