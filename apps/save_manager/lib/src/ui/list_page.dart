/// The list: console tabs, the card column, the grid of saves, the paint
/// buttons and (wide) the side panel; Y's options over it. Wide screens
/// follow the PC's MemoryCardPages layout; compact ones stack it.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

import '../art/art.dart';
import '../controller.dart';
import '../state.dart';
import '../texts.dart';
import 'kit.dart';
import 'taps.dart';

// ---- pieces both layouts use ----------------------------------------------

/// One save in the grid.
class SaveCell extends StatelessWidget {
  const SaveCell({
    super.key,
    required this.save,
    required this.width,
    required this.height,
    required this.u,
    this.on = false,
    this.lit = 0,
    this.marked = false,
    this.ticked = false,
    this.quiet = false,
    this.onTap,
    this.onLongPress,
    this.nameSize = 20,
  });

  final CardSave save;
  final double width, height, u;

  /// The save you're on (yellow name, the icon turns further).
  final bool on;

  /// The glow behind it (0 = none).
  final double lit;

  /// Marked (a yellow box), and with the big tick ([ticked]).
  final bool marked, ticked;

  /// Behind the options: dimmed.
  final bool quiet;
  final double nameSize;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final nameH = nameSize * 1.5;
    final icon = math.max(8.0, math.min(width * 0.86, height - nameH - 4 * u));
    Widget art = SaveIcon(save, size: icon, selected: on, dim: quiet && !on);
    if (save.favorite) {
      art = FavoriteSparkle(size: icon, dimmed: quiet && !on, child: art);
    }
    final a = on || !quiet ? 1.0 : 0.4;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            if (marked)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(3 * u),
                  child: Box(
                    fill: Tone.markFill,
                    edge: Look.yellow,
                    width: math.max(2, 4 * u),
                  ),
                ),
              ),
            if (lit > 0)
              Positioned(
                left: width / 2 - icon * 0.75,
                top:
                    (height - icon - nameH - 2 * u) / 2 +
                    icon / 2 -
                    icon * 0.75,
                width: icon * 1.5,
                height: icon * 1.5,
                child: Glow(alpha: lit),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: width,
                  height: icon,
                  child: Center(child: art),
                ),
                SizedBox(height: 2 * u),
                SizedBox(
                  height: nameH,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2 * u),
                    child: Center(
                      child: line(
                        Texts.shortName(save.cellName()),
                        (on ? bold : body)(
                          nameSize,
                          (on ? Look.yellow : Colors.white).withValues(
                            alpha: a,
                          ),
                        ),
                        align: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (save.copyProtected)
              Positioned(
                left: 12 * u,
                top: 10 * u,
                child: Padlock(size: 24 * u, alpha: a),
              ),
            if (ticked)
              Positioned(
                left: 4 * u,
                top: 8 * u,
                child: Tick(size: 36 * u, disc: true),
              ),
          ],
        ),
      ),
    );
  }
}

/// A card in the column: its drawing, name, space and blocks.
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.u,
    this.on = false,
    this.holds = false,
    this.lit,
    this.lifted = false,
    this.onTap,
    this.onLongPress,
    this.compact = false,
  });

  final MemoryCard card;
  final double u;

  /// The card you're on (yellow edge, glow).
  final bool on;

  /// It holds the save you're on (a faint edge).
  final bool holds;

  /// That save, lit in the blocks.
  final CardSave? lit;

  /// Being carried by Move card.
  final bool lifted;
  final bool compact;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final edge = on ? Look.yellow : (holds ? Tone.holds : Tone.edge2);
    final pad = 13 * u;
    final art = compact ? 24.0 : 72 * u;
    final nameSize = compact ? 11.5 : 19 * u;
    final freeSize = compact ? 10.0 : 18 * u;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: Glow(
        alpha: on ? (lifted ? 1 : 0.7) : 0,
        grow: compact ? 6 : 22 * u,
        child: Transform.scale(
          scale: lifted ? 1.04 : 1,
          child: Box(
            fill: on ? Tone.panelOn : Tone.panelSoft,
            edge: edge,
            width: compact ? 2 : 3,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 5, vertical: 3)
                : EdgeInsets.all(pad),
            child: Row(
              children: [
                CardArt(card, width: art),
                SizedBox(width: compact ? 6 : 14 * u),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      line(
                        card.name.isEmpty ? card.system : card.name,
                        heavy(nameSize),
                      ),
                      if (compact && card.inSlot.isNotEmpty)
                        line(card.inSlot, heavy(freeSize, Look.good))
                      else
                        line(card.freeText(), body(freeSize, Tone.soft2)),
                      SizedBox(height: compact ? 2 : 8 * u),
                      BlockBar(card, save: lit, height: compact ? 4 : 14 * u),
                      if (!compact && card.inSlot.isNotEmpty)
                        line(
                          card.inSlot,
                          heavy(compact ? 10 : 15 * u, Look.good),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A console tab: "PS2 72".
class FilterTab extends StatelessWidget {
  const FilterTab({
    super.key,
    required this.name,
    required this.count,
    required this.on,
    required this.size,
    this.onTap,
  });

  final String name;
  final int count;
  final bool on;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Box(
      fill: on ? const Color(0xFF050632) : Look.chip,
      edge: on ? Colors.white : const Color(0xFF5B63D8),
      width: size > 14 ? 3 : 2,
      padding: EdgeInsets.symmetric(horizontal: size * 0.7),
      child: Center(
        widthFactor: 1,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: name, style: heavy(size)),
              TextSpan(text: '  $count', style: heavy(size, Look.yellow)),
            ],
          ),
          maxLines: 1,
        ),
      ),
    ),
  );
}

/// The cards' summary under the column: "82 cards, 22 empty cards".
String cardsSummary(MemoryCardState st, int shown) {
  final all = st.column();
  var empty = 0;
  for (final c in all) {
    if (c.error.isEmpty && c.saves.isEmpty) empty++;
  }
  return [
    if (all.length > shown) '${all.length} cards',
    if (empty > 0) '$empty empty card${empty == 1 ? '' : 's'}',
  ].join(', ');
}

/// Cards that can't be read: "2 cards can't be read" ('' = none).
String brokenText(MemoryCardState st) {
  var n = 0;
  for (final c in st.column()) {
    if (c.error.isNotEmpty && !c.unformatted) n++;
  }
  return n == 0 ? '' : "$n card${n == 1 ? '' : 's'} can't be read";
}

/// The options: a heading, then each group's options two to a row.
class OptionsPanel extends StatelessWidget {
  const OptionsPanel({
    super.key,
    required this.c,
    required this.taps,
    required this.u,
    this.compact = false,
  });

  final SaveManagerController c;
  final Taps taps;
  final double u;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final st = c.state;
    final fs = compact ? 14.0 : 19 * u;
    final rowH = compact ? 38.0 : 43 * u;
    final gap = compact ? 6.0 : 8 * u;
    var n = 0;
    final kids = <Widget>[
      line(
        Texts.optionsHeading(st),
        heavy(compact ? 18 : 30 * u, Look.yellow),
        align: TextAlign.center,
      ),
      SizedBox(height: compact ? 8 : 24 * u),
    ];
    for (final g in st.groups) {
      kids
        ..add(line(g.heading, bold(fs, Look.cyan)))
        ..add(SizedBox(height: gap));
      for (var k = 0; k < g.items.length; k += 2) {
        final pair = <Widget>[];
        for (var j = k; j < k + 2; j++) {
          if (j >= g.items.length) {
            pair.add(const Expanded(child: SizedBox()));
            continue;
          }
          final o = g.items[j];
          final i = n++;
          final on = i == st.option;
          final danger = MemoryCardState.destructive.contains(o.verb);
          pair.add(
            Expanded(
              child: SizedBox(
                height: rowH,
                child: ChoiceBox(
                  key: ValueKey('option-$i'),
                  on: on,
                  danger: danger,
                  onTap: () => taps.option(i),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: line(
                      Texts.optionLabel(st, o),
                      (on ? bold : body)(
                        fs,
                        on
                            ? Tone.onYellow
                            : (danger ? Look.danger : Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          if (j == k) pair.add(SizedBox(width: gap));
        }
        kids
          ..add(Row(children: pair))
          ..add(SizedBox(height: gap));
      }
      kids.add(SizedBox(height: compact ? 6 : 18 * u));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: kids,
      ),
    );
  }
}

/// The yellow box while choosing several.
class SelectionBox extends StatelessWidget {
  const SelectionBox({
    super.key,
    required this.n,
    required this.size,
    this.onTap,
    this.touch = false,
    this.oneLine = false,
  });

  final int n;
  final double size;
  final bool touch;

  /// Heading and help on one line (short screens).
  final bool oneLine;
  final VoidCallback? onTap;

  String get _head => n > 0 ? '$n SELECTED' : 'SELECT SEVERAL';

  String get _help => n > 0
      ? (touch
            ? 'Tap here to copy, move or delete them'
            : 'Press Y to copy, move or delete them')
      : (touch ? 'Tap each save you want' : 'Press A on each save you want');

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Box(
      fill: Look.yellow,
      edge: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: size * 0.6),
      child: oneLine
          ? Center(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$_head   ', style: heavy(size, Look.ink)),
                    TextSpan(text: _help, style: body(size, Look.ink)),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                line(
                  _head,
                  heavy(size * 1.18, Look.ink),
                  align: TextAlign.center,
                ),
                line(_help, body(size, Look.ink), align: TextAlign.center),
              ],
            ),
    ),
  );
}

// ---- the grid ---------------------------------------------------------------

/// The saves, as many across as fit; it scrolls, and the d-pad steps the
/// way it looks (it tells the state its columns and rows).
class SaveGrid extends StatelessWidget {
  const SaveGrid({
    super.key,
    required this.c,
    required this.taps,
    required this.cellW,
    required this.cellH,
    required this.u,
    this.nameSize = 20,
  });

  final SaveManagerController c;
  final Taps taps;

  /// The smallest cell; the cells grow to fill the width.
  final double cellW, cellH, u, nameSize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final st = c.state;
      final cols = math.max(1, (box.maxWidth / cellW).floor());
      final rows = math.max(1, (box.maxHeight / cellH).floor());
      st.setGrid(cols, rows);
      final w = box.maxWidth / cols;
      final h = box.maxHeight / rows;
      if (st.saves.isEmpty) {
        return Center(
          child: Text(
            Texts.emptyGrid(c.isLoading || !c.loaded),
            textAlign: TextAlign.center,
            style: bold(nameSize * 1.5),
          ),
        );
      }
      final options = st.mode == Mode.options;
      final inGrid = st.button < 0 && st.cardI < 0;
      return KeepInSight(
        selected: st.index,
        itemExtent: h,
        perRow: cols,
        builder: (context, scroll) => GridView.builder(
          key: const ValueKey('save-grid'),
          controller: scroll,
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: h,
          ),
          itemCount: st.saves.length,
          itemBuilder: (context, i) {
            final s = st.saves[i];
            final here = i == st.index;
            final marked = st.marks.contains(MemoryCardState.saveKey(s));
            return SaveCell(
              key: ValueKey('save-$i'),
              save: s,
              width: w,
              height: h,
              u: u,
              nameSize: nameSize,
              on: here && (inGrid || options),
              lit: here && !options ? (inGrid ? 1 : 0.5) : 0,
              marked: marked,
              ticked: marked && st.selecting() && !options,
              quiet: options,
              onTap: () => taps.save(i),
              onLongPress: () => taps.saveOptions(i),
            );
          },
        ),
      );
    },
  );
}

/// The paint buttons under the grid.
class ListButtons extends StatelessWidget {
  const ListButtons({
    super.key,
    required this.c,
    required this.taps,
    required this.width,
    required this.height,
    this.gap = 0,
  });

  final SaveManagerController c;
  final Taps taps;
  final double width, height, gap;

  @override
  Widget build(BuildContext context) {
    final st = c.state;
    final options = st.mode == Mode.options;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, b) in MemoryCardState.listButtons.indexed) ...[
          if (i > 0) SizedBox(width: gap),
          PaintButton(
            b.label,
            key: ValueKey('list-button-$i'),
            seed: i + 1,
            width: width,
            height: height,
            selected: i == st.button && !options,
            enabled: !options,
            onTap: () => taps.button(i),
          ),
        ],
      ],
    );
  }
}

// ---- wide -------------------------------------------------------------------

/// The PC's list page.
class WideList extends StatelessWidget {
  const WideList({
    super.key,
    required this.c,
    required this.taps,
    required this.d,
    this.actions = const [],
    this.touch = false,
  });

  final SaveManagerController c;
  final Taps taps;
  final Dims d;
  final List<Widget> actions;
  final bool touch;

  static const cardsShown = 4;

  @override
  Widget build(BuildContext context) {
    final st = c.state;
    final u = d.u;
    final options = st.mode == Mode.options;
    final column = st.column();
    final shown = math.min(column.length, cardsShown);
    final cur = st.current();
    final title = d.pc(10, 2, 480, 134);
    final allRect = d.pc(22, 150 + shown * 141 + 30, 300, 100);
    final summary = cardsSummary(st, shown);
    final broken = brokenText(st);
    return Stack(
      children: [
        Positioned.fromRect(
          rect: title,
          child: Center(
            child: PaintTitle(
              'MEMORY CARDS',
              width: title.width,
              height: title.height * 0.9,
            ),
          ),
        ),
        d.at(
          512,
          38,
          1230,
          62,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, f) in MemoryCardState.filters.indexed) ...[
                  if (i > 0) SizedBox(width: 9 * d.sx),
                  SizedBox(
                    height: 62 * d.sy,
                    child: FilterTab(
                      key: ValueKey('tab-$i'),
                      name: f,
                      count: st.count(f),
                      on: i == st.filter,
                      size: 20 * u,
                      onTap: () => taps.tab(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        d.at(
          1660,
          38,
          234,
          62,
          GestureDetector(
            onTap: taps.sort,
            child: Align(
              alignment: Alignment.centerRight,
              child: line(Texts.listCorner(st), body(22 * u, Look.soft)),
            ),
          ),
        ),
        // the card column
        d.at(
          22,
          150,
          300,
          math.max(shown, 1) * 141.0 - 14,
          KeepInSight(
            selected: _cardInSight(st, column),
            itemExtent: 141 * d.sy,
            builder: (context, scroll) => ListView.builder(
              key: const ValueKey('card-column'),
              controller: scroll,
              padding: EdgeInsets.zero,
              itemExtent: 141 * d.sy,
              itemCount: column.length,
              itemBuilder: (context, i) {
                final card = column[i];
                final on = st.cardI == i;
                return Padding(
                  padding: EdgeInsets.only(bottom: 14 * d.sy),
                  child: CardTile(
                    key: ValueKey('card-$i'),
                    card: card,
                    u: u,
                    on: on,
                    lifted: on && st.moving,
                    holds: st.cardI < 0 && cur != null && cur.card == card,
                    lit: st.cardI < 0 && cur?.card == card ? cur : null,
                    onTap: () => taps.card(i),
                    onLongPress: () => taps.cardOptions(i),
                  ),
                );
              },
            ),
          ),
        ),
        if (summary.isNotEmpty)
          d.at(
            22,
            150 + shown * 141.0 - 6,
            300,
            34,
            Center(child: line(summary, body(18 * u, Tone.soft2))),
          ),
        if (column.isNotEmpty)
          Positioned.fromRect(
            rect: allRect,
            child: PaintButton(
              'BACK UP ALL',
              key: const ValueKey('back-up-all'),
              seed: 5,
              width: allRect.width,
              height: allRect.height,
              selected: st.button == MemoryCardState.backUpAll && !options,
              enabled: !options,
              onTap: () => taps.button(MemoryCardState.backUpAll),
            ),
          ),
        if (broken.isNotEmpty)
          Positioned(
            left: allRect.left,
            width: allRect.width,
            top: allRect.bottom + 6 * d.sy,
            child: line(
              broken,
              body(18 * u, Look.danger),
              align: TextAlign.center,
            ),
          ),
        // the grid
        d.at(
          343,
          146,
          1000,
          740,
          SaveGrid(
            c: c,
            taps: taps,
            cellW: 198 * d.sx,
            cellH: 184 * d.sy,
            u: u,
            nameSize: 20 * u,
          ),
        ),
        d.at(
          338,
          902,
          1004,
          106,
          FittedBox(
            fit: BoxFit.scaleDown,
            child: ListButtons(
              c: c,
              taps: taps,
              width: 250 * d.sx,
              height: 106 * d.sy,
            ),
          ),
        ),
        // the side panel
        if (options)
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('options-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: c.cancel,
            ),
          ),
        d.at(
          1360,
          148,
          538,
          850,
          Box(
            width: 4,
            padding: EdgeInsets.fromLTRB(24 * u, 14 * u, 24 * u, 16 * u),
            child: options
                ? Padding(
                    padding: EdgeInsets.only(top: 24 * u),
                    child: OptionsPanel(c: c, taps: taps, u: u),
                  )
                : (cur != null
                      ? _Side(c: c, save: cur, u: u, touch: touch)
                      : const SizedBox.expand()),
          ),
        ),
        if (actions.isNotEmpty)
          d.at(
            1700,
            1012,
            210,
            64,
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ),
      ],
    );
  }
}

/// Which card the column keeps in sight: the one you're on, else the
/// selected save's (the PC's _cards_shown).
int _cardInSight(MemoryCardState st, List<MemoryCard> column) {
  if (st.button == MemoryCardState.backUpAll) return column.length - 1;
  if (st.cardI >= 0) return st.cardI;
  final cur = st.current();
  return cur == null
      ? 0
      : math.max(column.indexOf(cur.card ?? MemoryCard()), 0);
}

/// The side panel: the save big, its names and badges, its rows.
class _Side extends StatelessWidget {
  const _Side({
    required this.c,
    required this.save,
    required this.u,
    required this.touch,
  });

  final SaveManagerController c;
  final CardSave save;
  final double u;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final st = c.state;
    final rows = Texts.sideRows(save, c.utcOffset);
    final hero = 216 * u;
    Widget art = SaveIcon(save, size: hero, selected: true, wide: false);
    if (save.favorite) art = FavoriteSparkle(size: hero, child: art);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: hero,
          child: Center(child: art),
        ),
        SizedBox(height: 26 * u),
        line(
          Texts.shortName(save.displayName()),
          heavy(30 * u, Look.yellow),
          align: TextAlign.center,
        ),
        for (final t in save.titleLines.take(3))
          line(t, body(23 * u), align: TextAlign.center),
        SizedBox(height: 10 * u),
        Badges(save, size: 18 * u, centred: true),
        SizedBox(height: 16 * u),
        Expanded(
          child: Column(
            children: [
              for (final (k, v) in rows)
                SizedBox(
                  height: 35 * u,
                  child: InfoRow(k, v, size: 20 * u, rule: true),
                ),
            ],
          ),
        ),
        if (st.selecting())
          SizedBox(
            height: 82 * u,
            child: SelectionBox(
              n: st.marks.length,
              size: 22 * u,
              touch: touch,
              onTap: c.toggleOptions,
            ),
          ),
      ],
    );
  }
}

// ---- compact ----------------------------------------------------------------

/// The list on a phone or the Retroid: tabs strip, card strip, grid,
/// buttons.
class CompactList extends StatelessWidget {
  const CompactList({
    super.key,
    required this.c,
    required this.taps,
    required this.d,
    this.actions = const [],
    this.touch = true,
  });

  final SaveManagerController c;
  final Taps taps;
  final Dims d;
  final List<Widget> actions;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final st = c.state;
    final options = st.mode == Mode.options;
    final tall = d.size.height >= 640;
    final short = d.size.height < 480;
    final column = st.column();
    final cur = st.current();
    final tabs = SizedBox(
      height: 34,
      child: ListView(
        key: const ValueKey('tabs'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final (i, f) in MemoryCardState.filters.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: EnsureVisible(
                active: i == st.filter,
                child: FilterTab(
                  key: ValueKey('tab-$i'),
                  name: f,
                  count: st.count(f),
                  on: i == st.filter,
                  size: 13,
                  onTap: () => taps.tab(i),
                ),
              ),
            ),
        ],
      ),
    );
    final sort = GestureDetector(
      onTap: taps.sort,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          Texts.listCorner(st),
          style: body(12, Look.soft),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    );
    final cardH = tall ? 62.0 : (short ? 44.0 : 54.0);
    final strip = SizedBox(
      height: cardH,
      child: KeepInSight(
        selected: _cardInSight(st, column),
        itemExtent: 178,
        builder: (context, scroll) => ListView.builder(
          key: const ValueKey('card-column'),
          controller: scroll,
          scrollDirection: Axis.horizontal,
          itemExtent: 178,
          itemCount: column.length + (column.isEmpty ? 0 : 1),
          itemBuilder: (context, i) {
            if (i == column.length) {
              return Padding(
                padding: const EdgeInsets.only(left: 4),
                child: PaintButton(
                  'BACK UP ALL',
                  key: const ValueKey('back-up-all'),
                  seed: 5,
                  width: 170,
                  height: cardH,
                  selected: st.button == MemoryCardState.backUpAll && !options,
                  enabled: !options,
                  onTap: () => taps.button(MemoryCardState.backUpAll),
                ),
              );
            }
            final card = column[i];
            final on = st.cardI == i;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CardTile(
                key: ValueKey('card-$i'),
                card: card,
                u: 1,
                compact: true,
                on: on,
                lifted: on && st.moving,
                holds: st.cardI < 0 && cur != null && cur.card == card,
                lit: st.cardI < 0 && cur?.card == card ? cur : null,
                onTap: () => taps.card(i),
                onLongPress: () => taps.cardOptions(i),
              ),
            );
          },
        ),
      ),
    );
    final cellW = d.landscape ? 86.0 : 92.0;
    final buttonsW = (d.size.width - 16) / 4;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tall)
                SizedBox(
                  height: 60,
                  child: Row(
                    children: [
                      const PaintTitle('MEMORY CARDS', width: 210, height: 58),
                      const Spacer(),
                      Flexible(child: sort),
                      ...actions,
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(child: tabs),
                  if (!tall) ...[Flexible(child: sort), ...actions],
                ],
              ),
              const SizedBox(height: 6),
              strip,
              if (brokenText(st).isNotEmpty)
                line(brokenText(st), body(11, Look.danger)),
              const SizedBox(height: 4),
              Expanded(
                child: SaveGrid(
                  c: c,
                  taps: taps,
                  cellW: cellW,
                  cellH: short ? 84 : cellW * (d.landscape ? 1.0 : 1.12),
                  u: 0.45,
                  nameSize: 11.5,
                ),
              ),
              if (st.selecting() && st.mode == Mode.list && st.saves.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    height: short ? 24 : 42,
                    child: SelectionBox(
                      n: st.marks.length,
                      size: 11.5,
                      oneLine: short,
                      touch: touch,
                      onTap: c.toggleOptions,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Center(
                child: ListButtons(
                  c: c,
                  taps: taps,
                  width: math.min(buttonsW, 150),
                  height: tall ? 52 : (short ? 38 : 44),
                ),
              ),
            ],
          ),
        ),
        if (options) ...[
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('options-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: c.cancel,
              child: const ColoredBox(color: Color(0x99000010)),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(520, d.size.width - 24),
                maxHeight: d.size.height - 24,
              ),
              child: Box(
                fill: Tone.panelOn,
                width: 3,
                padding: const EdgeInsets.all(12),
                child: OptionsPanel(c: c, taps: taps, u: 1, compact: true),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
