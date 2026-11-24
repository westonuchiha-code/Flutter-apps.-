import 'package:fx_kit/fx_kit.dart';
import 'package:material_ui/material_ui.dart';

/// Edits an effect chain (top to bottom); drag the handle to reorder.
/// Effects themselves come from `fx_kit`.
class EffectChainEditor extends StatefulWidget {
  const EffectChainEditor({
    super.key,
    required this.effects,
    required this.onAdd,
    required this.onChanged,
    required this.onRemove,
    required this.onMove,
  });

  final List<EffectSpec> effects;
  final void Function(EffectKind kind) onAdd;
  final void Function(EffectSpec spec) onChanged;
  final void Function(EffectSpec spec) onRemove;

  /// Moves the effect at `from` so it ends up at index `to`.
  final void Function(int from, int to) onMove;

  @override
  State<EffectChainEditor> createState() => _EffectChainEditorState();
}

class _EffectChainEditorState extends State<EffectChainEditor> {
  final _open = <int>{};
  int _known = -1;

  @override
  Widget build(BuildContext context) {
    final fx = widget.effects;
    // Newly added effects open their knobs.
    if (_known >= 0 && fx.length > _known && fx.isNotEmpty) {
      _open.add(fx.last.id);
    }
    _known = fx.length;
    final canAdd = fx.length < FxChain.maxEffects;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  fx.isEmpty
                      ? 'No effects yet'
                      : '${fx.length} of ${FxChain.maxEffects} effects · sound flows top to bottom',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              PopupMenuButton<EffectKind>(
                enabled: canAdd,
                tooltip: 'Add effect',
                onSelected: widget.onAdd,
                itemBuilder: (context) => [
                  for (final k in EffectKind.values)
                    PopupMenuItem(value: k, child: Text(k.label)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add effect'),
                  backgroundColor: canAdd
                      ? null
                      : Theme.of(context).disabledColor,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            itemCount: fx.length,
            onReorderItem: widget.onMove,
            itemBuilder: (context, i) {
              final e = fx[i];
              return _EffectCard(
                key: ValueKey(e.id),
                index: i,
                spec: e,
                open: _open.contains(e.id),
                onToggleOpen: () => setState(() {
                  _open.contains(e.id) ? _open.remove(e.id) : _open.add(e.id);
                }),
                onChanged: widget.onChanged,
                onRemove: () => widget.onRemove(e),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EffectCard extends StatelessWidget {
  const _EffectCard({
    super.key,
    required this.index,
    required this.spec,
    required this.open,
    required this.onToggleOpen,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final EffectSpec spec;
  final bool open;
  final VoidCallback onToggleOpen;
  final ValueChanged<EffectSpec> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.drag_indicator),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onToggleOpen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      spec.kind.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: spec.on ? null : theme.disabledColor,
                      ),
                    ),
                  ),
                ),
              ),
              Switch(
                value: spec.on,
                onChanged: (v) => onChanged(spec.withOn(v)),
              ),
              IconButton(
                tooltip: open ? 'Hide knobs' : 'Show knobs',
                icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                onPressed: onToggleOpen,
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ],
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  for (final p in spec.kind.params)
                    _ParamControl(
                      def: p,
                      value: spec[p.id],
                      onChanged: (v) => onChanged(spec.withValue(p.id, v)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ParamControl extends StatelessWidget {
  const _ParamControl({
    required this.def,
    required this.value,
    required this.onChanged,
  });

  final ParamDef def;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = def.choices;
    if (choices != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(child: Text(def.label)),
            SegmentedButton<int>(
              segments: [
                for (var i = 0; i < choices.length; i++)
                  ButtonSegment(value: i, label: Text(choices[i])),
              ],
              selected: {value.round()},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onChanged(s.first.toDouble()),
            ),
          ],
        ),
      );
    }
    final steps = def.step == null
        ? null
        : ((def.max - def.min) / def.step!).round();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(def.label)),
              Text(def.format(value)),
            ],
          ),
          Slider(
            value: def.toKnob(value),
            divisions: def.log ? null : steps,
            onChanged: (k) => onChanged(def.fromKnob(k)),
          ),
        ],
      ),
    );
  }
}
