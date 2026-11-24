import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:pixel_kit/pixel_kit.dart' as px;

import '../editor.dart';

Color toColor(int argb) => Color(argb);

IconData toolIcon(Tool t) => switch (t) {
  Tool.pencil => Icons.edit,
  Tool.eraser => Icons.auto_fix_normal,
  Tool.line => Icons.horizontal_rule,
  Tool.rect => Icons.crop_square,
  Tool.ellipse => Icons.circle_outlined,
  Tool.fill => Icons.format_color_fill,
  Tool.picker => Icons.colorize,
  Tool.select => Icons.highlight_alt,
};

/// Tool buttons plus the options of the current tool.
class ToolBar extends StatelessWidget {
  const ToolBar({super.key, required this.e, this.vertical = false});

  final Editor e;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget toolButton(Tool t) => IconButton(
      tooltip: '${t.label} (${t.key})',
      isSelected: e.tool == t,
      style: IconButton.styleFrom(
        backgroundColor: e.tool == t ? scheme.primaryContainer : null,
        foregroundColor: e.tool == t ? scheme.onPrimaryContainer : null,
      ),
      icon: Icon(toolIcon(t)),
      onPressed: () => e.setTool(t),
    );
    final options = <Widget>[
      if (e.tool == Tool.pencil || e.tool == Tool.eraser || e.tool == Tool.line)
        PopupMenuButton<int>(
          tooltip: 'Brush size',
          onSelected: e.setBrush,
          itemBuilder: (context) => [
            for (final s in [1, 2, 3, 4, 6, 8])
              PopupMenuItem(value: s, child: Text('$s px')),
          ],
          child: Chip(
            visualDensity: VisualDensity.compact,
            label: Text(vertical ? '${e.brushSize}' : '${e.brushSize} px'),
          ),
        ),
      if (e.tool == Tool.rect || e.tool == Tool.ellipse)
        FilterChip(
          label: const Text('Filled'),
          selected: e.shapeFilled,
          onSelected: (_) => e.toggleFilled(),
        ),
      if (e.tool == Tool.fill)
        FilterChip(
          label: const Text('Same colour everywhere'),
          selected: e.fillGlobal,
          onSelected: e.setFillGlobal,
        ),
      if (e.tool == Tool.select) ...[
        IconButton(
          tooltip: 'Flip left-right',
          icon: const Icon(Icons.flip),
          onPressed: e.flipX,
        ),
        IconButton(
          tooltip: 'Flip up-down',
          icon: Transform.rotate(
            angle: math.pi / 2,
            child: const Icon(Icons.flip),
          ),
          onPressed: e.flipY,
        ),
        IconButton(
          tooltip: 'Rotate 90°',
          icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
          onPressed: e.rotate,
        ),
        IconButton(
          tooltip: 'Copy (Ctrl+C)',
          icon: const Icon(Icons.copy),
          onPressed: e.copySelection,
        ),
        IconButton(
          tooltip: 'Paste (Ctrl+V)',
          icon: const Icon(Icons.paste),
          onPressed: e.clipboard == null ? null : e.paste,
        ),
        IconButton(
          tooltip: 'Delete (Del)',
          icon: const Icon(Icons.delete_outline),
          onPressed: e.selection == null ? null : e.deleteSelection,
        ),
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all),
          onPressed: e.selectAll,
        ),
        IconButton(
          tooltip: 'Deselect (Esc)',
          icon: const Icon(Icons.deselect),
          onPressed: e.selection == null ? null : e.deselect,
        ),
      ],
      IconButton(
        tooltip: 'Mirror left-right',
        isSelected: e.mirrorX,
        style: IconButton.styleFrom(
          backgroundColor: e.mirrorX ? scheme.secondaryContainer : null,
        ),
        icon: const Icon(Icons.vertical_split_outlined),
        onPressed: e.toggleMirrorX,
      ),
      IconButton(
        tooltip: 'Mirror up-down',
        isSelected: e.mirrorY,
        style: IconButton.styleFrom(
          backgroundColor: e.mirrorY ? scheme.secondaryContainer : null,
        ),
        icon: Transform.rotate(
          angle: math.pi / 2,
          child: const Icon(Icons.vertical_split_outlined),
        ),
        onPressed: e.toggleMirrorY,
      ),
    ];
    if (vertical) {
      return SingleChildScrollView(
        child: Column(
          children: [
            for (final t in Tool.values) toolButton(t),
            const Divider(),
            ...options,
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [for (final t in Tool.values) toolButton(t)]),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (final w in options) Center(child: w)],
          ),
        ),
      ],
    );
  }
}

/// Current colours and the palette.
class ColorBar extends StatelessWidget {
  const ColorBar({
    super.key,
    required this.e,
    required this.onEditColor,
    required this.onPalettes,
    this.grid = false,
  });

  final Editor e;
  final VoidCallback onEditColor;
  final VoidCallback onPalettes;

  /// Wrap the palette into rows (side panel) instead of one scrolling row.
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget swatch(
      int c, {
      double size = 28,
      bool selected = false,
      VoidCallback? onTap,
      VoidCallback? onLong,
    }) => GestureDetector(
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: c == 0 ? null : toColor(c),
          border: Border.all(
            color: selected ? scheme.onSurface : scheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: c == 0 ? const Icon(Icons.block, size: 16) : null,
      ),
    );
    final current = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, top: 14),
          child: swatch(e.secondary, size: 30, onTap: e.swapColors),
        ),
        Tooltip(
          message: 'Edit colour (tap) · the back square is the second colour: tap it to swap (X)',
          child: swatch(
            e.primary,
            size: 34,
            selected: true,
            onTap: onEditColor,
          ),
        ),
      ],
    );
    final colors = [
      for (final c in e.palette.colors)
        swatch(c, selected: c == e.primary, onTap: () => e.setPrimary(c)),
    ];
    final paletteButton = IconButton(
      tooltip: 'Palettes',
      icon: const Icon(Icons.palette_outlined),
      onPressed: onPalettes,
    );
    if (grid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [current, const Spacer(), paletteButton]),
          Text(e.palette.name, style: Theme.of(context).textTheme.labelMedium),
          Wrap(children: colors),
        ],
      );
    }
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 8),
          current,
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [for (final s in colors) Center(child: s)],
            ),
          ),
          paletteButton,
        ],
      ),
    );
  }
}

/// Layer list: tap to choose, eye to hide, drag to reorder, menu for more.
class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.e});

  final Editor e;

  @override
  Widget build(BuildContext context) {
    final s = e.sprite;
    final theme = Theme.of(context);
    // Top layer first, like other editors.
    final order = [for (var i = s.layers.length - 1; i >= 0; i--) i];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('Layers', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              tooltip: 'New layer',
              icon: const Icon(Icons.add),
              onPressed: e.addLayer,
            ),
          ],
        ),
        Flexible(
          child: ReorderableListView(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => e.moveLayer(order[from], order[to]),
            children: [
              for (var k = 0; k < order.length; k++)
                _LayerTile(
                  key: ValueKey('${order[k]}-${s.layers[order[k]].name}'),
                  e: e,
                  index: order[k],
                  listIndex: k,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LayerTile extends StatelessWidget {
  const _LayerTile({
    super.key,
    required this.e,
    required this.index,
    required this.listIndex,
  });

  final Editor e;
  final int index, listIndex;

  @override
  Widget build(BuildContext context) {
    final l = e.sprite.layers[index];
    final selected = e.layer == index;
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.secondaryContainer
          : Colors.transparent,
      child: ListTile(
        dense: true,
        onTap: () => e.selectLayer(index),
        leading: ReorderableDragStartListener(
          index: listIndex,
          child: const Icon(Icons.drag_indicator),
        ),
        title: Text(l.name, overflow: TextOverflow.ellipsis),
        subtitle: l.opacity < 1 ? Text('${(l.opacity * 100).round()}%') : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l.visible ? 'Hide' : 'Show',
              icon: Icon(
                l.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => e.setLayerVisible(index, !l.visible),
            ),
            PopupMenuButton<String>(
              tooltip: 'Layer options',
              onSelected: (a) => _action(context, a),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename…')),
                const PopupMenuItem(value: 'opacity', child: Text('Opacity…')),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate'),
                ),
                if (index > 0)
                  const PopupMenuItem(
                    value: 'merge',
                    child: Text('Merge down'),
                  ),
                if (e.sprite.layers.length > 1)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _action(BuildContext context, String a) async {
    switch (a) {
      case 'rename':
        final ctl = TextEditingController(text: e.sprite.layers[index].name);
        final v = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Layer name'),
            content: TextField(controller: ctl, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, ctl.text.trim()),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        ctl.dispose();
        if (v != null && v.isNotEmpty) e.renameLayer(index, v);
      case 'opacity':
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, set) => AlertDialog(
              title: Text(
                'Opacity ${(e.sprite.layers[index].opacity * 100).round()}%',
              ),
              content: Slider(
                value: e.sprite.layers[index].opacity,
                onChanged: (v) {
                  e.setLayerOpacity(index, v);
                  set(() {});
                },
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      case 'duplicate':
        e.duplicateLayer(index);
      case 'merge':
        e.mergeDown(index);
      case 'delete':
        e.removeLayer(index);
    }
  }
}

/// Hue/saturation/brightness + alpha + hex colour editor.
Future<int?> editColor(BuildContext context, int start) => showDialog<int>(
  context: context,
  builder: (context) => _ColorDialog(start: start),
);

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.start});
  final int start;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(
    Color(widget.start == 0 ? 0xFF000000 : widget.start),
  );
  late final _hex = TextEditingController(text: px.hexOf(widget.start));

  int get _value => _hsv.toColor().toARGB32();

  void _set(HSVColor h) {
    setState(() => _hsv = h);
    _hex.text = px.hexOf(_value);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget slider(
      String label,
      double v,
      double max,
      ValueChanged<double> on,
    ) => Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(value: v.clamp(0, max), max: max, onChanged: on),
        ),
      ],
    );
    return AlertDialog(
      title: const Text('Colour'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            slider('Hue', _hsv.hue, 360, (v) => _set(_hsv.withHue(v))),
            slider(
              'Colour',
              _hsv.saturation,
              1,
              (v) => _set(_hsv.withSaturation(v)),
            ),
            slider('Brightness', _hsv.value, 1, (v) => _set(_hsv.withValue(v))),
            slider('Opacity', _hsv.alpha, 1, (v) => _set(_hsv.withAlpha(v))),
            TextField(
              controller: _hex,
              decoration: const InputDecoration(labelText: 'Hex (#RRGGBB)'),
              onSubmitted: (t) {
                final c = px.parseHex(t);
                if (c != null) {
                  setState(() => _hsv = HSVColor.fromColor(Color(c)));
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value),
          child: const Text('Use'),
        ),
      ],
    );
  }
}
