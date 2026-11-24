import 'package:audio_kit/audio_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';

/// Loop Station: record mic layers over the beat, in sync.
class LoopsView extends StatelessWidget {
  const LoopsView({super.key, required this.c});

  final PadController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rec = c.layerRec;
    final mic = c.layerMic;
    final status = switch (rec) {
      LayerRec.idle =>
        'Records your mic for ${c.layerBars} bar${c.layerBars == 1 ? '' : 's'}, starting on the next bar.',
      LayerRec.starting => 'Starting the microphone…',
      LayerRec.waiting => 'Get ready… recording starts on the next bar',
      LayerRec.recording =>
        'Recording bar ${c.layerBarsDone + 1} of ${c.layerBars}',
      LayerRec.processing => 'Adding the loop…',
    };
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Record loop'),
              onPressed: rec == LayerRec.idle ? c.recordLayer : null,
            ),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: c.layerBars,
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 bar')),
                DropdownMenuItem(value: 2, child: Text('2 bars')),
                DropdownMenuItem(value: 4, child: Text('4 bars')),
                DropdownMenuItem(value: 8, child: Text('8 bars')),
              ],
              onChanged: rec == LayerRec.idle
                  ? (v) => c.setLayerBars(v ?? 2)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(status),
        if (mic != null) ...[
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: mic,
            builder: (context, _) =>
                LevelMeter(level: mic.level, clipped: mic.clipped),
          ),
        ],
        if (c.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              c.message!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Use headphones so the beat isn\'t recorded too. '
          'If loops sound early or late, adjust "Loop timing" in Settings.',
          style: theme.textTheme.bodySmall,
        ),
        const Divider(height: 24),
        if (c.layers.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No loops yet.'),
          )
        else ...[
          for (final l in c.layers)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        '${l.name}\n${l.bars} bar${l.bars == 1 ? '' : 's'}',
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: l.gain,
                        max: 1.5,
                        onChanged: (v) => c.updateLayer(l, gain: v),
                      ),
                    ),
                    IconButton(
                      tooltip: l.muted ? 'Unmute' : 'Mute',
                      icon: Icon(l.muted ? Icons.volume_off : Icons.volume_up),
                      onPressed: () => c.updateLayer(l, muted: !l.muted),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => c.removeLayer(l),
                    ),
                  ],
                ),
              ),
            ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('Undo last'),
                onPressed: c.undoLayer,
              ),
              TextButton.icon(
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear all'),
                onPressed: c.clearLayers,
              ),
            ],
          ),
          Text(
            'Tempo is locked while there are loops.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
