import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Chunky display text with a thick black outline, like the game's HUD.
class OutlinedText extends StatelessWidget {
  const OutlinedText(
    this.text, {
    super.key,
    this.size = 21,
    this.color = SaColors.ink,
    this.stroke = 5,
    this.family = SaFonts.display,
    this.upperCase = true,
    this.letterSpacing = 0.6,
    this.shadow = true,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final double size;
  final Color color;
  final double stroke;
  final String family;
  final bool upperCase;
  final double letterSpacing;
  final bool shadow;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final t = upperCase ? text.toUpperCase() : text;
    final base = TextStyle(
      fontFamily: family,
      fontSize: size,
      height: 1.05,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Stack(
      children: [
        Text(
          t,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.black,
            shadows: shadow
                ? const [Shadow(color: Color(0xA6000000), offset: Offset(0, 3))]
                : null,
          ),
        ),
        Text(
          t,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: base.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Dark glass panel. [accent] adds a coloured left edge.
class SaCard extends StatelessWidget {
  const SaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.accent,
    this.accentWidth = 5,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final double accentWidth;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: accent!, width: accentWidth),
          ),
        ),
        child: content,
      );
    }
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SaColors.p1, SaColors.p2],
          ),
          border: Border.all(color: SaColors.line),
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              highlightColor: const Color(0x22F3B93A),
              splashColor: const Color(0x22F3B93A),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

enum MeterStyle { health, armor, gold, green }

/// HUD-style bar (health, armor, gold or green fill).
class Meter extends StatelessWidget {
  const Meter(this.value, {super.key, this.style = MeterStyle.health});

  final double value;
  final MeterStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = switch (style) {
      MeterStyle.health => const [Color(0xFFE24A4A), SaColors.redDark],
      MeterStyle.armor => const [Color(0xFFEEF1EE), Color(0xFF8F9893)],
      MeterStyle.gold => const [Color(0xFFF9D070), SaColors.goldDark],
      MeterStyle.green => const [Color(0xFF7FE07A), SaColors.grove],
    };
    return Container(
      height: 13,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [BoxShadow(color: SaColors.line2, spreadRadius: 1)],
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 300),
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section heading with a gold rule and an optional count.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.count});

  final String title;
  final String? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontFamily: SaFonts.display,
              fontSize: 13,
              letterSpacing: 1.2,
              color: SaColors.gold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 2,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [SaColors.goldDark, Colors.transparent],
                ),
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 10),
            Text(count!, style: condensed(size: 14, spacing: 1)),
          ],
        ],
      ),
    );
  }
}

/// Red warning or gold info box. [bold] is shown first, in bold.
class NoteBox extends StatelessWidget {
  const NoteBox({
    super.key,
    required this.bold,
    required this.text,
    this.gold = false,
  });

  final String bold;
  final String text;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final edge = gold ? SaColors.gold : SaColors.red;
    final frame = gold ? const Color(0xFF5B4513) : const Color(0xFF5A2323);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: gold ? const Color(0x1AF3B93A) : const Color(0x1FD03232),
        border: Border.all(color: frame),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: edge, width: 4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$bold ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: text),
              ],
            ),
            style: const TextStyle(fontSize: 14.5, height: 1.4),
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling filter chips.
class FilterChips extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final o = options[i];
          final on = o == selected;
          return Semantics(
            selected: on,
            button: true,
            child: GestureDetector(
              onTap: () => onSelected(o),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? SaColors.gold : SaColors.field,
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: on ? SaColors.goldDark : SaColors.line,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  o.toUpperCase(),
                  style: condensed(
                    size: 15,
                    color: on ? const Color(0xFF1A1203) : SaColors.ink,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: SaColors.field,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: SaColors.line, spreadRadius: 1)],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: SaColors.dim),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF6D7A74)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18, color: SaColors.dim),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
        ],
      ),
    );
  }
}

enum SaButtonKind { primary, ghost, danger }

/// Chunky game-menu button.
class SaButton extends StatelessWidget {
  const SaButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = SaButtonKind.primary,
    this.small = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final SaButtonKind kind;
  final bool small;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = switch (kind) {
      SaButtonKind.primary => const Color(0xFF1B1203),
      SaButtonKind.ghost => SaColors.ink,
      SaButtonKind.danger => const Color(0xFFFF8D84),
    };
    final decoration = switch (kind) {
      SaButtonKind.primary => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6C548), Color(0xFFD99A1F)],
        ),
      ),
      SaButtonKind.ghost => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF232B27), Color(0xFF1A201D)],
        ),
      ),
      SaButtonKind.danger => const BoxDecoration(),
    };
    final radius = BorderRadius.circular(10);
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: kind == SaButtonKind.danger
              ? Border.all(color: const Color(0xFF6B2B27))
              : Border.all(color: Colors.black, width: 2),
          boxShadow: kind == SaButtonKind.danger
              ? null
              : const [BoxShadow(color: Colors.black, offset: Offset(0, 3))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: decoration,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPressed,
                child: Padding(
                  padding: small
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                      : const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: small ? 18 : 20, color: fg),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: condensed(
                            size: small ? 15 : 17,
                            color: fg,
                            spacing: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Square check box used for missions and 100% items.
class TickBox extends StatelessWidget {
  const TickBox({
    super.key,
    required this.checked,
    required this.onTap,
    required this.label,
  });

  final bool checked;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: checked ? SaColors.money : const Color(0xFF0B0E0D),
              border: Border.all(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: checked ? SaColors.grove : const Color(0xFF4A5651),
                  spreadRadius: 1.5,
                ),
              ],
            ),
            child: checked
                ? const Icon(Icons.check, size: 22, color: Color(0xFF0B1A0B))
                : null,
          ),
        ),
      ),
    );
  }
}

/// Six wanted-level stars, [lit] of them gold.
class WantedStars extends StatelessWidget {
  const WantedStars(this.lit, {super.key, this.size = 13});

  final int lit;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 6; i++)
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(
            Icons.star,
            size: size,
            color: i < lit ? SaColors.gold : const Color(0xFF1C221F),
            shadows: const [Shadow(color: Colors.black, blurRadius: 1)],
          ),
        ),
    ],
  );
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 10),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: SaColors.dim),
    ),
  );
}
