import 'dart:math' as math;

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
  const SceneSheet({
    super.key,
    required this.c,
    required this.scene,
    this.pickSprite,
  });
  final VideoController c;
  final Scene scene;

  /// Picks a sprite or picture from the Asset Locker (its details JSON).
  final Future<Map<String, Object?>?> Function()? pickSprite;

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

  double _maxBeats(double maxSeconds) => math
      .max(1, (maxSeconds / c.project.beat).floorToDouble())
      .clamp(1, 64)
      .toDouble();

  Future<void> _editOverlay(SceneOverlay o) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: c,
      builder: (context, _) => _OverlaySheet(c: c, scene: s, overlay: o),
    ),
  );

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
            if (c.project.snap)
              _Row(
                label: 'Length',
                value: '${(_duration / c.project.beat).round()} beats',
                child: Slider(
                  value: (_duration / c.project.beat).roundToDouble().clamp(
                    1,
                    _maxBeats(maxDur),
                  ),
                  min: 1,
                  max: _maxBeats(maxDur),
                  divisions: math.max(1, _maxBeats(maxDur).round() - 1),
                  onChanged: (v) =>
                      setState(() => _duration = v.round() * c.project.beat),
                  onChangeEnd: (v) =>
                      _set((s) => s.duration = v.round() * c.project.beat),
                ),
              )
            else
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
            Text('Arrives with', style: t.labelLarge),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<Transition>(
                    isExpanded: true,
                    value: s.transition,
                    items: [
                      for (final tr in Transition.values)
                        DropdownMenuItem(value: tr, child: Text(tr.label)),
                    ],
                    onChanged: (v) =>
                        _set((s) => s.transition = v ?? Transition.cut),
                  ),
                ),
              ],
            ),
            if (s.transition != Transition.cut)
              _Row(
                label: 'Over',
                value: '${s.transitionLength.toStringAsFixed(1)} s',
                child: Slider(
                  value: s.transitionLength.clamp(0.2, 1.5),
                  min: 0.2,
                  max: 1.5,
                  divisions: 13,
                  onChanged: (v) => _set((s) => s.transitionLength = v),
                ),
              ),
            if (s.transition != Transition.cut &&
                c.project.scenes.indexOf(s) == 0)
              Text(
                '(The first scene has nothing to come from.)',
                style: t.bodySmall,
              ),
            const SizedBox(height: 8),
            Text('On top', style: t.labelLarge),
            for (final o in s.overlays)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  o.kind == OverlayKind.text
                      ? Icons.text_fields
                      : Icons.grid_on,
                ),
                title: Text(
                  o.kind == OverlayKind.text
                      ? o.text.replaceAll('\n', ' ')
                      : ((o.asset?['name'] as String?) ?? 'Sprite'),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  o.aboveEffect ? 'Above the effect' : 'Through the effect',
                ),
                onTap: () => _editOverlay(o),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final o = SceneOverlay(kind: OverlayKind.text);
                    await _set((s) => s.overlays.add(o));
                    await _editOverlay(o);
                  },
                  icon: const Icon(Icons.text_fields),
                  label: const Text('Add text'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final info = await widget.pickSprite?.call();
                    if (info == null) return;
                    final o = SceneOverlay(
                      kind: OverlayKind.sprite,
                      asset: info,
                      y: 0.5,
                    );
                    await _set((s) => s.overlays.add(o));
                    await _editOverlay(o);
                  },
                  icon: const Icon(Icons.grid_on),
                  label: const Text('Add sprite'),
                ),
              ],
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

/// Edits one overlay (text or sprite) on a scene.
class _OverlaySheet extends StatefulWidget {
  const _OverlaySheet({
    required this.c,
    required this.scene,
    required this.overlay,
  });
  final VideoController c;
  final Scene scene;
  final SceneOverlay overlay;

  @override
  State<_OverlaySheet> createState() => _OverlaySheetState();
}

class _OverlaySheetState extends State<_OverlaySheet> {
  late final _text = TextEditingController(text: widget.overlay.text);
  SceneOverlay get o => widget.overlay;

  Future<void> _set(void Function(SceneOverlay o) f) async {
    await widget.c.updateScene(widget.scene, (_) => f(o));
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
    final d = widget.scene.duration;
    final to = o.to <= 0 ? d : o.to.clamp(0.0, d);
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
                Expanded(
                  child: Text(
                    o.kind == OverlayKind.text
                        ? 'Text on top'
                        : 'Sprite on top',
                    style: t.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await widget.c.updateScene(
                      widget.scene,
                      (s) => s.overlays.remove(o),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
            if (o.kind == OverlayKind.text) ...[
              TextField(
                controller: _text,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _set((o) => o.text = v),
              ),
              const SizedBox(height: 6),
              _Colors(
                selected: o.color,
                onPick: (v) => _set((o) => o.color = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Black outline'),
                value: o.outline,
                onChanged: (v) => _set((o) => o.outline = v),
              ),
            ],
            _Row(
              label: 'Size',
              value: '${o.scale}',
              child: Slider(
                value: o.scale.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                onChanged: (v) => _set((o) => o.scale = v.round()),
              ),
            ),
            _Row(
              label: 'Across',
              value: '${(o.x * 100).round()}%',
              child: Slider(value: o.x, onChanged: (v) => _set((o) => o.x = v)),
            ),
            _Row(
              label: 'Down',
              value: '${(o.y * 100).round()}%',
              child: Slider(value: o.y, onChanged: (v) => _set((o) => o.y = v)),
            ),
            _Row(
              label: 'Appears',
              value: '${o.from.toStringAsFixed(1)} s',
              child: Slider(
                value: o.from.clamp(0, d),
                max: d,
                onChanged: (v) => _set(
                  (o) => o.from = math
                      .min((v * 10).round() / 10, to - 0.1)
                      .clamp(0, d),
                ),
              ),
            ),
            _Row(
              label: 'Goes',
              value: o.to <= 0 ? 'end' : '${o.to.toStringAsFixed(1)} s',
              child: Slider(
                value: to,
                max: d,
                onChanged: (v) => _set((o) {
                  final x = (v * 10).round() / 10;
                  o.to = x >= d - 0.05 ? 0 : math.max(x, o.from + 0.1);
                }),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Above the effect'),
              subtitle: const Text(
                'Clean on top, instead of going through the scene\'s effect',
              ),
              value: o.aboveEffect,
              onChanged: (v) => _set((o) => o.aboveEffect = v),
            ),
          ],
        ),
      ),
    );
  }
}
