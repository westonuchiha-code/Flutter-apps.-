import 'package:material_ui/material_ui.dart';

import '../app/theremin_controller.dart';
import '../recording/take.dart';
import '../synth/catalog.dart';
import '../synth/engine.dart';
import 'sound_picker.dart';

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Saved performances: play, rename, re-voice, export, delete.
class RecordingsPage extends StatelessWidget {
  const RecordingsPage({super.key, required this.controller});

  final ThereminController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recordings')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final takes = controller.takes;
          if (takes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No recordings yet.\nTap Record on the main screen, play, '
                  'then tap Stop.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: takes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) =>
                _TakeTile(controller: controller, take: takes[i]),
          );
        },
      ),
    );
  }
}

class _TakeTile extends StatelessWidget {
  const _TakeTile({required this.controller, required this.take});

  final ThereminController controller;
  final Take take;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final chip = chipById(take.sound.chipId);
    final patch = chip.patch(take.sound.patchId);
    final busy = c.busyTakeId == take.id;
    final playing = c.playingTakeId == take.id;
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : IconButton.filledTonal(
                tooltip: playing ? 'Stop' : 'Play',
                icon: Icon(playing ? Icons.stop : Icons.play_arrow),
                onPressed: () => playing ? c.stopTake() : c.playTake(take),
              ),
      ),
      title: Text(take.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${formatDuration(take.duration)} · ${chip.name} ${patch.name}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (action) => _onAction(context, action),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'export', child: Text('Export WAV')),
          PopupMenuItem(value: 'sound', child: Text('Change sound')),
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _onAction(BuildContext context, String action) async {
    switch (action) {
      case 'export':
        await controller.exportTake(take);
      case 'sound':
        final spec = await showModalBottomSheet<SoundSpec>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => _ChangeSoundSheet(
            initial: take.sound,
            current: controller.settings.sound,
          ),
        );
        if (spec != null) await controller.revoiceTake(take, spec);
      case 'rename':
        final name = await showDialog<String>(
          context: context,
          builder: (_) => _RenameDialog(initial: take.name),
        );
        if (name != null) await controller.renameTake(take, name);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete recording?'),
            content: Text('"${take.name}" will be removed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok ?? false) await controller.deleteTake(take);
    }
  }
}

class _ChangeSoundSheet extends StatefulWidget {
  const _ChangeSoundSheet({required this.initial, required this.current});

  final SoundSpec initial;

  /// The sound currently set on the main screen (with its effects).
  final SoundSpec current;

  @override
  State<_ChangeSoundSheet> createState() => _ChangeSoundSheetState();
}

class _ChangeSoundSheetState extends State<_ChangeSoundSheet> {
  late SoundSpec _spec = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Play this recording with:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SoundPicker(
              spec: _spec,
              onChanged: (s) => setState(() => _spec = s),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.tune),
              label: const Text('Use my current sound and effects'),
              onPressed: () => setState(() => _spec = widget.current),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _spec),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: _text,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
