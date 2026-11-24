import 'package:material_ui/material_ui.dart';

import '../controller.dart';

/// Colour of pad [i] (four rows of four hues).
Color padColor(int i, Brightness b) {
  final hue = (i * 360 / 16 + 200) % 360;
  return HSLColor.fromAHSL(
    1,
    hue,
    0.55,
    b == Brightness.dark ? 0.55 : 0.45,
  ).toColor();
}

/// Keyboard keys for the pads (rows 1234 / QWER / ASDF / ZXCV).
const padKeys = '1234QWERASDFZXCV';

/// 4×4 grid of pads. Each pad reacts to its own pointer (multi-touch).
class PadsView extends StatelessWidget {
  const PadsView({
    super.key,
    required this.c,
    required this.onEdit,
    required this.editMode,
  });

  final PadController c;
  final void Function(int pad) onEdit;
  final bool editMode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth < box.maxHeight
            ? box.maxWidth
            : box.maxHeight;
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox.square(
            dimension: side,
            child: GridView.count(
              crossAxisCount: 4,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(6),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var i = 0; i < 16; i++)
                  _Pad(
                    index: i,
                    slot: c.pads[i],
                    lit: (c.activePads >> i) & 1 == 1,
                    onDown: () => (editMode || c.pads[i].isEmpty)
                        ? onEdit(i)
                        : c.padDown(i),
                    onUp: () => c.padUp(i),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({
    required this.index,
    required this.slot,
    required this.lit,
    required this.onDown,
    required this.onUp,
  });

  final int index;
  final PadSlot slot;
  final bool lit;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = padColor(index, theme.brightness);
    final empty = slot.isEmpty;
    final fill = empty
        ? theme.colorScheme.surfaceContainerHighest
        : Color.lerp(base, Colors.black, lit ? 0 : 0.45)!;
    final fg = empty ? theme.colorScheme.outline : Colors.white;
    return Semantics(
      button: true,
      label: 'Pad ${index + 1} ${slot.name}',
      child: Listener(
        onPointerDown: (_) => onDown(),
        onPointerUp: (_) => onUp(),
        onPointerCancel: (_) => onUp(),
        child: AnimatedContainer(
          duration: Duration(milliseconds: lit ? 0 : 160),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: empty ? theme.colorScheme.outlineVariant : base,
              width: 2,
            ),
            boxShadow: lit
                ? [
                    BoxShadow(
                      color: base.withValues(alpha: 0.7),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(6),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  '${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(color: fg),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: Text(
                  padKeys[index],
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg.withValues(alpha: 0.6),
                  ),
                ),
              ),
              Center(
                child: empty
                    ? Icon(Icons.add, color: fg)
                    : Text(
                        slot.name.isEmpty ? 'Sample' : slot.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(color: fg),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
