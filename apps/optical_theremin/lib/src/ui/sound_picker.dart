import 'package:material_ui/material_ui.dart';

import '../synth/catalog.dart';
import '../synth/engine.dart';

/// Chip row + sound row for choosing what the theremin plays.
class SoundPicker extends StatelessWidget {
  const SoundPicker({
    super.key,
    required this.spec,
    required this.onChanged,
    this.dense = false,
  });

  final SoundSpec spec;
  final ValueChanged<SoundSpec> onChanged;

  /// Single-line layout for the main screen.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final chip = chipById(spec.chipId);
    final patch = chip.patch(spec.patchId);
    final scheme = Theme.of(context).colorScheme;
    Widget row(List<Widget> children) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in children)
            Padding(padding: const EdgeInsets.only(right: 8), child: c),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row([
          for (final c in chipCatalog)
            ChoiceChip(
              label: Text(c.name),
              selected: c.id == chip.id,
              onSelected: (_) => onChanged(
                spec.copyWith(chipId: c.id, patchId: c.patches.first.id),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        row([
          for (final p in chip.patches)
            ChoiceChip(
              avatar: p.transpose < 0
                  ? const Icon(Icons.south, size: 16)
                  : null,
              label: Text(p.name),
              selected: p.id == patch.id,
              selectedColor: scheme.tertiaryContainer,
              onSelected: (_) => onChanged(spec.copyWith(patchId: p.id)),
            ),
        ]),
        if (!dense || patch.note != null) ...[
          const SizedBox(height: 4),
          Text(
            [chip.chip, ?patch.note].join(' — '),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
