/// An opened save (THIS SAVE / THE GAME / FILES INSIDE / ON THE CARD) and
/// a card's own page (THIS CARD / ON THE CARD / SAVES), wide like the PC
/// and compact as one scrolling column.
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

/// The PS2 models' names (the PC's KIND_NAMES).
const kindNames = ['List', 'Copy', 'Delete'];

/// An opened save's files: name and size, or for consoles without files
/// its data and icon frames. [top] / [shown] window the list (shown = 0:
/// all). Returns the heading and the rows.
(String, List<Row2>) fileRows(CardSave s, {int top = 0, int shown = 0}) {
  if (s.system != 'PS2' && s.system != 'PS3') {
    return (
      'FILES INSIDE',
      [('Save data', s.sizeText()), ('Icon frames', '${s.frames.length}')],
    );
  }
  final end = shown <= 0
      ? s.files.length
      : math.min(top + shown, s.files.length);
  final first = shown <= 0 ? 0 : math.min(top, end);
  final rows = [
    for (final f in s.files.sublist(first, end))
      (f.name, Texts.bytesText(f.size)),
  ];
  var head = 'FILES INSIDE';
  if (shown > 0 && s.files.length > shown) {
    head += '  (${first + 1}-${first + rows.length} of ${s.files.length})';
  }
  return (head, rows);
}

/// The save's icon, sparkling when it's a favorite.
Widget heroIcon(CardSave s, double size, {bool wide = false, int kind = 0}) {
  Widget art = SaveIcon(s, size: size, selected: true, wide: wide, kind: kind);
  if (s.favorite && kind == 0) art = FavoriteSparkle(size: size, child: art);
  return art;
}

/// Big words with a soft shadow (the PC's text with shadow).
TextStyle shadowed(TextStyle t) => t.copyWith(
  shadows: [
    Shadow(
      color: const Color(0xCC000000),
      offset: Offset(t.fontSize! * 0.06, t.fontSize! * 0.08),
    ),
  ],
);

/// A row of paint buttons ([labels]), [on] highlighted.
class PageButtons extends StatelessWidget {
  const PageButtons({
    super.key,
    required this.labels,
    required this.on,
    required this.taps,
    required this.width,
    required this.height,
    this.gap = 0,
  });

  final List<String> labels;
  final int on;
  final Taps taps;
  final double width, height, gap;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, l) in labels.indexed) ...[
        if (i > 0) SizedBox(width: gap),
        PaintButton(
          l,
          key: ValueKey('page-button-$i'),
          seed: i + 1,
          width: width,
          height: height,
          selected: i == on,
          onTap: () => taps.pageButton(i),
        ),
      ],
    ],
  );
}

// ---- an opened save ---------------------------------------------------------

class OpenedPage extends StatelessWidget {
  const OpenedPage({
    super.key,
    required this.c,
    required this.taps,
    required this.d,
    this.scroll,
  });

  final SaveManagerController c;
  final Taps taps;
  final Dims d;

  /// Compact: the page's scroller (the d-pad scrolls it).
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    final s = c.state.current();
    if (s == null) return const SizedBox.shrink();
    return d.compact ? _compact(s) : _wide(s);
  }

  List<String> get _labels => [
    for (final b in MemoryCardState.openButtons) b.label,
  ];

  Widget _wide(CardSave s) {
    final u = d.u;
    final st = c.state;
    final files = fileRows(
      s,
      top: st.fileTop,
      shown: MemoryCardState.filesShown,
    );
    final card = s.card;
    final pedestal = d.pc(130, 218, 540, 440);
    final art = math.min(pedestal.width, pedestal.height);
    return Stack(
      children: [
        d.at(
          56,
          30,
          740,
          200,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(
                Texts.shortName(s.displayName()),
                shadowed(heavy(44 * u, Look.yellow)),
              ),
              for (final t in s.titleLines.take(2))
                line(t, shadowed(body(27 * u))),
              SizedBox(height: 8 * u),
              Badges(s, size: 18 * u),
            ],
          ),
        ),
        Positioned.fromRect(
          rect: pedestal.inflate(20 * u),
          child: const Glow(alpha: 0.42),
        ),
        Positioned.fromRect(
          rect: pedestal,
          child: Center(child: heroIcon(s, art, wide: s.system == 'PS3')),
        ),
        if (s.system == 'PS2')
          for (var k = 0; k < 3; k++)
            d.at(
              130 + k * 188.0,
              712,
              164,
              160,
              Box(
                fill: const Color(0x80070838),
                width: 2,
                child: Column(
                  children: [
                    Expanded(
                      child: Center(child: heroIcon(s, 120 * u, kind: k)),
                    ),
                    line(kindNames[k], body(20 * u)),
                    SizedBox(height: 6 * u),
                  ],
                ),
              ),
            ),
        d.at(
          810,
          76,
          590,
          352,
          Sheet(
            heading: 'THIS SAVE',
            rows: Texts.saveRows(s, c.utcOffset, opened: true),
            size: 21 * u,
            gap: 46 * d.sy,
            pad: 24 * u,
          ),
        ),
        d.at(
          810,
          446,
          590,
          428,
          Sheet(
            heading: 'THE GAME',
            rows: Texts.gameRows(s, c.utcOffset),
            size: 21 * u,
            gap: 46 * d.sy,
            pad: 24 * u,
          ),
        ),
        d.at(
          1420,
          76,
          470,
          590,
          Sheet(
            heading: files.$1,
            rows: files.$2,
            size: 19 * u,
            gap: 32 * d.sy,
            pad: 24 * u,
          ),
        ),
        d.at(
          1420,
          686,
          470,
          188,
          Box(
            padding: EdgeInsets.fromLTRB(24 * u, 14 * u, 24 * u, 14 * u),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line('ON THE CARD', bold(19 * u, Look.cyan)),
                const Spacer(),
                if (card != null)
                  Row(
                    children: [
                      CardArt(card, width: 58 * u),
                      SizedBox(width: 18 * u),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            line(
                              '${card.name}, ${card.freeText()}',
                              body(19 * u),
                            ),
                            SizedBox(height: 10 * u),
                            BlockBar(card, save: s, height: 14 * u),
                          ],
                        ),
                      ),
                    ],
                  ),
                const Spacer(),
              ],
            ),
          ),
        ),
        d.at(
          40,
          896,
          1860,
          118,
          FittedBox(
            fit: BoxFit.scaleDown,
            child: PageButtons(
              labels: _labels,
              on: st.openButton,
              taps: taps,
              width: 430 * d.sx,
              height: 118 * d.sy,
              gap: 38 * d.sx,
            ),
          ),
        ),
      ],
    );
  }

  Widget _compact(CardSave s) {
    final st = c.state;
    final tall = d.size.height >= 640;
    final icon = tall ? 120.0 : 84.0;
    final files = fileRows(s);
    final card = s.card;
    const fs = 13.0, gap = 24.0;
    final buttonW = math.min((d.size.width - 16) / 4, 150.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: icon + 8,
                height: icon + 4,
                child: Glow(
                  alpha: 0.42,
                  child: Center(
                    child: heroIcon(s, icon, wide: s.system == 'PS3'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Texts.shortName(s.displayName()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: shadowed(heavy(18, Look.yellow)),
                    ),
                    for (final t in s.titleLines.take(2)) line(t, body(12.5)),
                    const SizedBox(height: 4),
                    Badges(s, size: 10.5),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              key: const ValueKey('opened-scroll'),
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                Sheet(
                  heading: 'THIS SAVE',
                  rows: Texts.saveRows(s, c.utcOffset, opened: true),
                  size: fs,
                  gap: gap,
                  pad: 10,
                  expand: false,
                ),
                const SizedBox(height: 6),
                Sheet(
                  heading: 'THE GAME',
                  rows: Texts.gameRows(s, c.utcOffset),
                  size: fs,
                  gap: gap,
                  pad: 10,
                  expand: false,
                ),
                const SizedBox(height: 6),
                Sheet(
                  heading: files.$1,
                  rows: files.$2,
                  size: 12,
                  gap: 21,
                  pad: 10,
                  expand: false,
                ),
                if (card != null) ...[
                  const SizedBox(height: 6),
                  Box(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        line('ON THE CARD', bold(12, Look.cyan)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            CardArt(card, width: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  line(
                                    '${card.name}, ${card.freeText()}',
                                    body(fs),
                                  ),
                                  const SizedBox(height: 5),
                                  BlockBar(card, save: s, height: 7),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: PageButtons(
              labels: _labels,
              on: st.openButton,
              taps: taps,
              width: buttonW,
              height: tall ? 52 : 44,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- a card's own page -----------------------------------------------------

class CardPage extends StatelessWidget {
  const CardPage({
    super.key,
    required this.c,
    required this.taps,
    required this.d,
    this.scroll,
  });

  final SaveManagerController c;
  final Taps taps;
  final Dims d;
  final ScrollController? scroll;

  /// Save icons shown on the page (the PC's CARD_ICONS_SHOWN).
  static const iconsShown = 8;

  /// Saves named on the page (the PC's CARD_SAVES_SHOWN).
  static const savesShown = 19;

  @override
  Widget build(BuildContext context) {
    final card = c.state.focusedCard();
    if (card == null) return const SizedBox.shrink();
    return d.compact ? _compact(card) : _wide(card);
  }

  List<Row2> _saves(MemoryCard card, int n) => [
    for (final s in card.saves.take(n))
      (Texts.shortName(s.cellName()), s.sizeText()),
  ];

  Widget _wide(MemoryCard card) {
    final u = d.u;
    final st = c.state;
    final big = d.pc(230, 190, 330, 429);
    final w = math.min(big.width, big.height / CardArt.aspect);
    final labels = [for (final b in st.cardButtons(card)) b.label];
    final icons = math.min(card.saves.length, iconsShown);
    return Stack(
      children: [
        d.at(
          56,
          30,
          740,
          130,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(card.name, shadowed(heavy(44 * u, Look.yellow))),
              line(Texts.cardTag(card), shadowed(body(26 * u))),
            ],
          ),
        ),
        Positioned.fromRect(
          rect: big.inflate(60 * u),
          child: const Glow(alpha: 0.42),
        ),
        Positioned.fromRect(
          rect: big,
          child: Center(child: CardArt(card, width: w)),
        ),
        d.at(
          810,
          76,
          590,
          500,
          Sheet(
            heading: 'THIS CARD',
            rows: Texts.cardRows(card, c.utcOffset),
            size: 21 * u,
            gap: 46 * d.sy,
            pad: 24 * u,
            extra: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: BlockBar(card, height: 16 * u),
              ),
            ),
          ),
        ),
        d.at(
          810,
          594,
          590,
          280,
          Box(
            padding: EdgeInsets.fromLTRB(18 * u, 14 * u, 18 * u, 10 * u),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 6 * u),
                  child: line(
                    icons > 0 ? 'ON THE CARD' : 'ON THE CARD: nothing yet',
                    bold(19 * u, Look.cyan),
                  ),
                ),
                SizedBox(height: 8 * u),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 4,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 141 / 112,
                    padding: EdgeInsets.zero,
                    children: [
                      for (var i = 0; i < icons; i++)
                        Center(
                          child: SaveIcon(
                            card.saves[i],
                            size: 100 * u,
                            phase: i * 0.7,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        d.at(
          1420,
          76,
          470,
          798,
          Sheet(
            heading: Texts.cardSavesHeading(card, shown: savesShown),
            rows: _saves(card, savesShown),
            size: 19 * u,
            gap: 38 * d.sy,
            pad: 24 * u,
          ),
        ),
        d.at(
          40,
          896,
          1860,
          118,
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: PageButtons(
                labels: labels,
                on: st.cardButton,
                taps: taps,
                width: 430 * d.sx,
                height: 118 * d.sy,
                gap: 38 * d.sx,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _compact(MemoryCard card) {
    final st = c.state;
    final tall = d.size.height >= 640;
    final labels = [for (final b in st.cardButtons(card)) b.label];
    final buttonW = math.min((d.size.width - 16) / labels.length, 150.0);
    final icons = math.min(card.saves.length, iconsShown);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Glow(
                alpha: 0.42,
                grow: 6,
                child: CardArt(card, width: tall ? 64 : 48),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: shadowed(heavy(18, Look.yellow)),
                    ),
                    Text(
                      Texts.cardTag(card),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: body(12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              key: const ValueKey('card-scroll'),
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                Sheet(
                  heading: 'THIS CARD',
                  rows: Texts.cardRows(card, c.utcOffset),
                  size: 13,
                  gap: 24,
                  pad: 10,
                  expand: false,
                  extra: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: BlockBar(card, height: 8),
                  ),
                ),
                const SizedBox(height: 6),
                Box(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      line(
                        icons > 0 ? 'ON THE CARD' : 'ON THE CARD: nothing yet',
                        bold(12, Look.cyan),
                      ),
                      if (icons > 0) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < icons; i++)
                              SaveIcon(card.saves[i], size: 52, phase: i * 0.7),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Sheet(
                  heading: Texts.cardSavesHeading(card, shown: savesShown),
                  rows: _saves(card, savesShown),
                  size: 12.5,
                  gap: 22,
                  pad: 10,
                  expand: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: PageButtons(
              labels: labels,
              on: st.cardButton,
              taps: taps,
              width: buttonW,
              height: tall ? 52 : 44,
            ),
          ),
        ],
      ),
    );
  }
}
