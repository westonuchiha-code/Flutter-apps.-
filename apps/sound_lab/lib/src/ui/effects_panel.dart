import 'package:fx_kit/fx_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';

/// The effect chain, top to bottom. Drag the handle to reorder.
class EffectsPanel extends StatefulWidget {
  const EffectsPanel({super.key, required this.c});

  final LabController c;

  @override
  State<EffectsPanel> createState() => _EffectsPanelState();
}

class _EffectsPanelState extends State<EffectsPanel> {
  final _open = <int>{};

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  c.fx.isEmpty
                      ? 'No effects yet'
                      : '${c.fx.length} of ${FxChain.maxEffects} effects · sound flows top to bottom',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              PopupMenuButton<EffectKind>(
                enabled: c.canAddEffect,
                tooltip: 'Add effect',
                onSelected: (k) {
                  c.addEffect(k);
                  setState(() => _open.add(c.fx.last.id));
                },
                itemBuilder: (context) => [
                  for (final k in EffectKind.values)
                    PopupMenuItem(value: k, child: Text(k.label)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add effect'),
                  backgroundColor: c.canAddEffect
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
            itemCount: c.fx.length,
            onReorderItem: c.moveEffect,
            itemBuilder: (context, i) {
              final e = c.fx[i];
              return _EffectCard(
                key: ValueKey(e.id),
                index: i,
                spec: e,
                open: _open.contains(e.id),
                onToggleOpen: () => setState(() {
                  _open.contains(e.id) ? _open.remove(e.id) : _open.add(e.id);
                }),
                onChanged: c.updateEffect,
                onRemove: () => c.removeEffect(e),
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
