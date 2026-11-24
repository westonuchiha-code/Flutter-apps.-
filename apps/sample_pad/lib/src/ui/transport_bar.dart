import 'package:material_ui/material_ui.dart';

import '../controller.dart';

class TransportBar extends StatelessWidget {
  const TransportBar({super.key, required this.c});

  final PadController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = c.tempoLocked;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton.filled(
            iconSize: 30,
            tooltip: c.playing ? 'Stop (Space)' : 'Play (Space)',
            icon: Icon(c.playing ? Icons.stop : Icons.play_arrow),
            onPressed: () => c.setPlaying(!c.playing),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Slower',
            icon: const Icon(Icons.remove),
            onPressed: locked ? null : () => c.setBpm(c.bpm - 1),
          ),
          GestureDetector(
            onTap: locked ? null : () => _editBpm(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.bpm.round().toString(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text('BPM', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Faster',
            icon: const Icon(Icons.add),
            onPressed: locked ? null : () => c.setBpm(c.bpm + 1),
          ),
          TextButton(
            onPressed: locked ? null : c.tapTempo,
            child: const Text('TAP'),
          ),
          const Spacer(),
          if (locked)
            const Tooltip(
              message: 'Tempo locked by loops',
              child: Icon(Icons.lock_outline, size: 18),
            ),
          PopupMenuButton<void>(
            tooltip: 'Swing',
            icon: const Icon(Icons.waves),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: StatefulBuilder(
                  builder: (context, set) => SizedBox(
                    width: 220,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Swing ${(c.swing * 200).round()}%'),
                        Slider(
                          value: c.swing,
                          max: 0.5,
                          divisions: 10,
                          onChanged: locked
                              ? null
                              : (v) {
                                  c.setSwing(v);
                                  set(() {});
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editBpm(BuildContext context) async {
    final ctl = TextEditingController(text: c.bpm.round().toString());
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tempo (BPM)'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    ctl.dispose();
    final n = double.tryParse(v ?? '');
    if (n != null) c.setBpm(n);
  }
}
