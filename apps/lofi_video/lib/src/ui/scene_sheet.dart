import 'package:material_ui/material_ui.dart';
import 'package:video_kit/video_kit.dart';

import '../controller.dart';
import '../media.dart';
import '../project.dart';

/// Colours for title cards (a classic 16-colour set).
const titleColors = [
  0xFF000000,
  0xFF1D2B53,
  0xFF7E2553,
  0xFF008751,
  0xFFAB5236,
  0xFF5F574F,
  0xFFC2C3C7,
  0xFFFFF1E8,
  0xFFFF004D,
  0xFFFFA300,
  0xFFFFEC27,
  0xFF00E436,
  0xFF29ADFF,
  0xFF83769C,
  0xFFFF77A8,
  0xFFFFCCAA,
];

final _effectInfo = {for (final e in allEffects()) e.id: e};

String effectName(String? id) =>
    id == null ? 'No effect' : (_effectInfo[id]?.name ?? id);

/// Edits one scene.
class SceneSheet extends StatefulWidget {
  const SceneSheet({super.key, required this.c, required this.scene});
  final VideoController c;
  final Scene scene;

  @override
  State<SceneSheet> createState() => _SceneSheetState();
}

class _SceneSheetState extends State<SceneSheet> {
  late final _text = TextEditingController(text: widget.scene.text);
  late double _duration = widget.scene.duration;
  late double _start = widget.scene.clipStart;

  Scene get s => widget.scene;
  VideoController get c => widget.c;

  Future<void> _set(void Function(Scene s) f) async {
    await c.updateScene(s, f);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = s.assetId == null ? null : c.media[s.assetId];
    final clipLength = m is ClipMedia ? m.clip.length : 0.0;
    final maxDur = s.kind == SceneKind.clip && clipLength > 0
        ? (clipLength - _start).clamp(0.5, maxSeconds)
        : 20.0;
    final effect = s.effectId == null ? null : _effectInfo[s.effectId];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(s.kind.label, style: t.titleMedium)),
                IconButton(
                  tooltip: 'Duplicate',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () async {
                    await c.duplicateScene(s);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await c.removeScene(s);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
            if (s.asset != null)
              Text((s.asset!['name'] as String?) ?? '', style: t.bodySmall),
            if (s.assetId != null && c.failed[s.assetId] != null)
              Text(
                c.failed[s.assetId]!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            if (s.kind == SceneKind.title) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _text,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _set((s) => s.text = v),
              ),
              const SizedBox(height: 8),
              Text('Text colour', style: t.labelLarge),
              _Colors(
                selected: s.textColor,
                onPick: (v) => _set((s) => s.textColor = v),
              ),
            ],
            if (s.kind == SceneKind.title ||
                s.kind == SceneKind.sprite ||
                s.kind == SceneKind.picture) ...[
              Text('Background', style: t.labelLarge),
              _Colors(
                selected: s.background,
                onPick: (v) => _set((s) => s.background = v),
              ),
            ],
            const SizedBox(height: 8),
            _Row(
              label: 'Length',
              value: '${_duration.toStringAsFixed(1)} s',
              child: Slider(
                value: _duration.clamp(0.5, maxDur),
                min: 0.5,
                max: maxDur,
                onChanged: (v) =>
                    setState(() => _duration = (v * 10).round() / 10),
                onChangeEnd: (v) =>
                    _set((s) => s.duration = (v * 10).round() / 10),
              ),
            ),
            if (s.kind == SceneKind.clip && clipLength > 0.6) ...[
              _Row(
                label: 'Start at',
                value: '${_start.toStringAsFixed(1)} s',
                child: Slider(
                  value: _start.clamp(0, clipLength - 0.5),
                  max: clipLength - 0.5,
                  onChanged: (v) =>
                      setState(() => _start = (v * 10).round() / 10),
                  onChangeEnd: (v) => _set((s) {
                    s.clipStart = (v * 10).round() / 10;
                    s.duration = s.duration.clamp(
                      0.5,
                      clipLength - s.clipStart,
                    );
                    _duration = s.duration;
                  }),
                ),
              ),
              if (m is ClipMedia && m.clip.hasSound)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Clip's own sound"),
                  value: s.clipSound,
                  onChanged: (v) => _set((s) => s.clipSound = v),
                ),
            ],
            if (s.kind != SceneKind.title && s.kind != SceneKind.bars)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SegmentedButton<Fit>(
                  segments: const [
                    ButtonSegment(
                      value: Fit.contain,
                      label: Text('Whole picture'),
                    ),
                    ButtonSegment(
                      value: Fit.cover,
                      label: Text('Fill the screen'),
                    ),
                  ],
                  selected: {s.fit},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => _set((s) => s.fit = v.first),
                ),
              ),
            const SizedBox(height: 8),
            Text('Effect', style: t.labelLarge),
            const SizedBox(height: 4),
            DropdownButton<String?>(
              isExpanded: true,
              value: s.effectId,
              items: [
                const DropdownMenuItem(value: null, child: Text('No effect')),
                for (final e in allEffects())
                  DropdownMenuItem(value: e.id, child: Text(e.name)),
              ],
              onChanged: (v) => _set((s) {
                s.effectId = v;
                s.knobs = {};
              }),
            ),
            if (effect != null) ...[
              Text(effect.about, style: t.bodySmall),
              for (final k in effect.knobs)
                if (k.choices != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(k.label),
                        for (var i = 0; i < k.choices!.length; i++)
                          ChoiceChip(
                            label: Text(k.choices![i]),
                            selected: (s.knobs[k.id] ?? k.value).round() == i,
                            onSelected: (_) =>
                                _set((s) => s.knobs[k.id] = i.toDouble()),
                          ),
                      ],
                    ),
                  )
                else
                  _Row(
                    label: k.label,
                    value: '',
                    child: Slider(
                      value: (s.knobs[k.id] ?? k.value).clamp(k.min, k.max),
                      min: k.min,
                      max: k.max,
                      onChanged: (v) => setState(() => s.knobs[k.id] = v),
                      onChangeEnd: (v) => _set((s) => s.knobs[k.id] = v),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.child});
  final String label, value;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 96, child: Text(label, overflow: TextOverflow.ellipsis)),
      Expanded(child: child),
      SizedBox(width: 44, child: Text(value, textAlign: TextAlign.end)),
    ],
  );
}

class _Colors extends StatelessWidget {
  const _Colors({required this.selected, required this.onPick});
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final c in titleColors)
          InkWell(
            onTap: () => onPick(c),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(c),
                border: Border.all(
                  color: c == selected ? Colors.white : Colors.white24,
                  width: c == selected ? 3 : 1,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
