/// MemoryCardFlow's screens (the PC's MemoryCardDialogs): the picker, the
/// question, the copy screen, working, customize; and Android's
/// emulators-closed question. Wide ones keep the PC's places; compact
/// ones stack.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

import '../art/art.dart';
import '../controller.dart';
import '../flow.dart';
import '../texts.dart';
import 'kit.dart';
import 'taps.dart';

/// The flow's screen (or the emulators-closed question) for [c].
class FlowDialog extends StatelessWidget {
  const FlowDialog({
    super.key,
    required this.c,
    required this.taps,
    required this.d,
    this.stickerFolder = '',
  });

  final SaveManagerController c;
  final Taps taps;
  final Dims d;

  /// Where your own sticker pictures go (Customize says).
  final String stickerFolder;

  @override
  Widget build(BuildContext context) {
    final q = c.asking;
    if (q != null) {
      return _Ask(
        d: d,
        title: ClosedQuestion.title,
        lines: q.lines,
        answers: ClosedQuestion.answers,
        index: q.index,
        onTap: taps.closedAnswer,
        warnFirst: true,
      );
    }
    final f = c.flow;
    return switch (f.kind) {
      FlowKind.working => _Working(d: d, title: f.title),
      FlowKind.pick => _Pick(f: f, taps: taps, d: d),
      FlowKind.ask => _Ask(
        d: d,
        title: f.title,
        lines: f.lines,
        answers: [for (final it in f.items) it.label],
        index: f.index,
        onTap: taps.item,
        subject: f.subject,
      ),
      FlowKind.copy =>
        d.compact
            ? _CompactCopy(f: f, taps: taps, d: d)
            : _WideCopy(f: f, taps: taps, d: d),
      FlowKind.look => _Look(f: f, taps: taps, d: d, folder: stickerFolder),
      FlowKind.none => const SizedBox.shrink(),
    };
  }
}

/// The heading plaque's words: outlined, shrunk to fit.
Widget plaqueText(String text, double size) => FittedBox(
  fit: BoxFit.scaleDown,
  child: OutlinedText(text, size: size, color: Look.yellow),
);

// ---- working ----------------------------------------------------------------

class _Working extends StatelessWidget {
  const _Working({required this.d, required this.title});

  final Dims d;
  final String title;

  @override
  Widget build(BuildContext context) {
    final u = d.compact ? 0.5 : d.u;
    final box = Box(
      fill: Tone.panelOn,
      width: 4,
      padding: EdgeInsets.symmetric(horizontal: 40 * u, vertical: 26 * u),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          line(title, heavy(36 * u, Look.yellow), align: TextAlign.center),
          SizedBox(height: 14 * u),
          Text(
            Texts.workingNote,
            textAlign: TextAlign.center,
            style: body(23 * u, Look.soft),
          ),
          SizedBox(height: 18 * u),
          SizedBox(
            width: 34 * u,
            height: 34 * u,
            child: CircularProgressIndicator(
              strokeWidth: 4 * u,
              color: Look.yellow,
            ),
          ),
        ],
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: d.compact ? math.min(420, d.size.width - 32) : 840 * d.sx,
        ),
        child: box,
      ),
    );
  }
}

// ---- the picker -------------------------------------------------------------

class _Pick extends StatelessWidget {
  const _Pick({required this.f, required this.taps, required this.d});

  final MemoryCardFlow f;
  final Taps taps;
  final Dims d;

  @override
  Widget build(BuildContext context) {
    final compact = d.compact;
    final u = d.u;
    final stacked = compact && d.size.width < 520;
    final rowH = compact ? (stacked ? 54.0 : 46.0) : 84 * d.sy;
    final titleSize = compact ? 17.0 : 36 * u;
    final labelSize = compact ? 13.5 : 26 * u;
    final detailSize = compact ? 11.5 : 22 * u;
    final counter = Texts.pickCounter(f);
    final list = KeepInSight(
      selected: f.index,
      itemExtent: rowH,
      builder: (context, scroll) => ListView.builder(
        key: const ValueKey('pick-list'),
        controller: scroll,
        padding: EdgeInsets.zero,
        itemExtent: rowH,
        itemCount: f.items.length,
        itemBuilder: (context, i) {
          final it = f.items[i];
          final on = i == f.index;
          final ink = on ? Tone.onYellow : Colors.white;
          return Padding(
            padding: EdgeInsets.only(bottom: compact ? 4 : 6 * d.sy),
            child: ChoiceBox(
              key: ValueKey('pick-$i'),
              on: on,
              dark: Look.chip,
              edge: Tone.edge2,
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 24 * u),
              onTap: () => taps.item(i),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        line(it.label, bold(labelSize, ink)),
                        line(
                          it.detail,
                          body(detailSize, on ? ink : Tone.soft2),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 11,
                          child: line(it.label, bold(labelSize, ink)),
                        ),
                        SizedBox(width: compact ? 6 : 12 * u),
                        Expanded(
                          flex: 8,
                          child: line(
                            it.detail,
                            body(detailSize, on ? ink : Tone.soft2),
                            align: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
    final panel = Box(
      width: 4,
      padding: compact
          ? const EdgeInsets.all(10)
          : EdgeInsets.fromLTRB(28 * d.sx, 30 * d.sy, 28 * d.sx, 10 * d.sy),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(f.title, heavy(titleSize, Look.yellow), align: TextAlign.center),
          SizedBox(height: compact ? 6 : 14 * u),
          for (final l in f.lines)
            Text(
              l,
              textAlign: TextAlign.center,
              style: body(compact ? 12.5 : 26 * u),
            ),
          if (f.lines.isNotEmpty) SizedBox(height: compact ? 6 : 14 * u),
          Expanded(child: list),
          SizedBox(
            height: compact ? 18 : 30 * u,
            child: Center(
              child: line(counter, body(compact ? 11 : 20 * u, Tone.soft2)),
            ),
          ),
        ],
      ),
    );
    if (compact) {
      return Padding(padding: const EdgeInsets.all(8), child: panel);
    }
    return Stack(children: [d.at(360, 70, 1200, 900, panel)]);
  }
}

// ---- a question -------------------------------------------------------------

class _Ask extends StatelessWidget {
  const _Ask({
    required this.d,
    required this.title,
    required this.lines,
    required this.answers,
    required this.index,
    required this.onTap,
    this.subject,
    this.warnFirst = false,
  });

  final Dims d;
  final String title;
  final List<String> lines;
  final List<String> answers;
  final int index;
  final void Function(int i) onTap;
  final CardSave? subject;

  /// The first line is the warning (the emulators-closed question).
  final bool warnFirst;

  @override
  Widget build(BuildContext context) {
    final u = d.u;
    final compact = d.compact;
    final s = subject;
    Widget lineAt(int i) {
      final first = i == 0;
      final warn = Texts.isWarning(lines[i]) || (warnFirst && first);
      final size = compact ? (first ? 15.0 : 12.5) : (first ? 32 * u : 25 * u);
      final style = first && !warnFirst
          ? heavy(size, warn ? Look.warn : Colors.white)
          : body(size, warn ? Look.warn : Colors.white);
      return Padding(
        padding: EdgeInsets.only(bottom: compact ? 4 : 10 * d.sy),
        child: Text(
          lines[i],
          textAlign: TextAlign.center,
          style: shadowedText(style),
        ),
      );
    }

    final buttons = [
      for (final (i, a) in answers.indexed)
        PaintButton(
          a,
          key: ValueKey('ask-$i'),
          seed: 2 + i * 2,
          width: compact
              ? math.min((d.size.width - 40) / math.max(answers.length, 1), 200)
              : 390 * d.sx,
          height: compact ? 52 : 124 * d.sy,
          selected: i == index,
          onTap: () => onTap(i),
        ),
    ];
    if (compact) {
      final icon = d.size.height >= 640 ? 150.0 : 92.0;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          children: [
            Box(
              fill: Tone.panelOn,
              width: 3,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Center(child: plaqueText(title, 20)),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (s != null)
                        Glow(
                          alpha: 0.5,
                          child: SizedBox(
                            width: icon * 1.4,
                            height: icon,
                            child: Center(
                              child: SaveIcon(
                                s,
                                size: icon,
                                kind: 2,
                                selected: true,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      for (var i = 0; i < lines.length; i++) lineAt(i),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: buttons,
            ),
          ],
        ),
      );
    }
    final victim = d.pc(780, 196, 360, 350);
    final top = s != null ? 576.0 : 330.0;
    return Stack(
      children: [
        d.at(
          410,
          70,
          1100,
          96,
          Box(
            fill: Tone.panelOn,
            width: 4,
            padding: EdgeInsets.symmetric(horizontal: 25 * d.sx),
            child: Center(child: plaqueText(title, 42 * u)),
          ),
        ),
        if (s != null) ...[
          Positioned.fromRect(
            rect: victim.inflate(30 * u),
            child: const Glow(alpha: 0.5),
          ),
          Positioned.fromRect(
            rect: victim,
            child: Center(
              child: SaveIcon(
                s,
                size: math.min(victim.width, victim.height),
                kind: 2,
                selected: true,
              ),
            ),
          ),
        ],
        d.at(
          210,
          top,
          1500,
          826 - top,
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (var i = 0; i < lines.length; i++) lineAt(i)],
          ),
        ),
        d.at(
          0,
          846,
          1920,
          124,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (i, b) in buttons.indexed) ...[
                if (i > 0) SizedBox(width: 60 * d.sx),
                b,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Words with the PC's drop shadow (so they read over the backdrop).
TextStyle shadowedText(TextStyle t) => t.copyWith(
  shadows: [
    Shadow(
      color: const Color(0xCC000000),
      offset: Offset(t.fontSize! * 0.06, t.fontSize! * 0.08),
      blurRadius: t.fontSize! * 0.05,
    ),
  ],
);

// ---- the copy screen ------------------------------------------------------

/// One save on the copy screen.
class _CopyCell extends StatelessWidget {
  const _CopyCell({
    super.key,
    required this.save,
    required this.u,
    this.marked = false,
    this.here = false,
    this.arriving = false,
    this.onTap,
    this.nameSize = 19,
  });

  final CardSave save;
  final double u, nameSize;
  final bool marked, here, arriving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Box(
      fill: marked || here ? Tone.markFill : Tone.panelSoft,
      edge: here ? Colors.white : (marked ? Look.yellow : Tone.edge2),
      width: marked || here ? math.max(2, 4 * u) : 2,
      child: LayoutBuilder(
        builder: (context, box) {
          final nameH = nameSize * 1.5;
          final icon = math.max(
            8.0,
            math.min(box.maxWidth * 0.72, box.maxHeight - nameH - 4),
          );
          return Stack(
            children: [
              Column(
                children: [
                  SizedBox(height: 2 * u),
                  SizedBox(
                    height: icon,
                    child: Center(
                      child: SaveIcon(
                        save,
                        size: icon,
                        kind: arriving ? 1 : 0,
                        selected: here,
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: nameH,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4 * u),
                        child: line(
                          Texts.shortName(save.displayName()),
                          (marked ? bold : body)(
                            nameSize,
                            marked && !arriving ? Look.yellow : Colors.white,
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
                  left: 10 * u,
                  top: 8 * u,
                  child: Padlock(size: 24 * u),
                ),
              if (marked && !arriving)
                Positioned(
                  right: 6 * u,
                  top: 4 * u,
                  child: Tick(size: 36 * u),
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// An empty slot.
class _Hole extends StatelessWidget {
  const _Hole();

  @override
  Widget build(BuildContext context) =>
      const Box(fill: Tone.holeFill, edge: Tone.holeEdge, width: 2);
}

class _WideCopy extends StatelessWidget {
  const _WideCopy({required this.f, required this.taps, required this.d});

  final MemoryCardFlow f;
  final Taps taps;
  final Dims d;

  static const fromX = 30.0, toX = 1202.0, paneW = 688.0;

  @override
  Widget build(BuildContext context) {
    final u = d.u;
    final to = f.target();
    final coming = f.arriving();
    const perPage = MemoryCardFlow.copyCols * MemoryCardFlow.copyRows;
    final slotStep = 168 * d.sy;
    final after = Texts.copyTargetText(f);
    final source = f.source;
    Widget pane(double x, Widget name, Widget info) => Stack(
      children: [
        d.at(x, 28, paneW, 112, Center(child: name)),
        d.at(
          x,
          142,
          paneW,
          108,
          Box(
            fill: Tone.panelSoft,
            edge: Tone.edge2,
            padding: EdgeInsets.fromLTRB(22 * u, 14 * u, 24 * u, 14 * u),
            child: info,
          ),
        ),
      ],
    );
    Widget info(MemoryCard? card, String system, String free, Color freeInk) =>
        Row(
          children: [
            CardArt(card, system: system, width: 58 * u),
            SizedBox(width: 24 * u),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(child: line(free, body(21 * u, freeInk))),
                      if (card != null)
                        Flexible(
                          child: line(
                            MemoryCards.place(card),
                            body(21 * u, Look.label),
                            align: TextAlign.right,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 10 * u),
                  if (card != null) BlockBar(card, height: 16 * u),
                ],
              ),
            ),
          ],
        );
    final title = d.pc(0, 0, 470, 112);
    return Stack(
      children: [
        // where they come from
        pane(
          fromX,
          source != null
              ? PaintTitle(
                  source.name,
                  seed: 1,
                  width: title.width,
                  height: title.height,
                )
              : FittedBox(
                  child: OutlinedText(
                    '${f.list.length} SELECTED',
                    size: 28 * u,
                  ),
                ),
          info(
            source,
            f.fromSystem,
            source != null ? source.freeText() : Texts.copyFromText(f),
            Tone.soft2,
          ),
        ),
        d.at(
          fromX + 3,
          268,
          682,
          664,
          KeepInSight(
            selected: f.inButtons ? -1 : f.cell,
            itemExtent: slotStep,
            perRow: MemoryCardFlow.copyCols,
            builder: (context, scroll) => GridView.builder(
              key: const ValueKey('copy-from'),
              controller: scroll,
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MemoryCardFlow.copyCols,
                mainAxisExtent: slotStep,
              ),
              itemCount: math.max(f.list.length, perPage),
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.only(right: 8 * d.sx, bottom: 8 * d.sy),
                child: i >= f.list.length
                    ? const _Hole()
                    : _CopyCell(
                        key: ValueKey('copy-cell-$i'),
                        save: f.list[i],
                        u: u,
                        marked: f.marked.contains(
                          MemoryCardFlow.markKey(f.list[i]),
                        ),
                        here: !f.inButtons && i == f.cell,
                        onTap: () => taps.copyCell(i),
                      ),
              ),
            ),
          ),
        ),
        // where they go
        pane(
          toX,
          to != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (f.targets.length > 1)
                      _Arrow(
                        left: true,
                        size: 40 * u,
                        onTap: () =>
                            taps.copyTarget((f.targetI - 1) % f.targets.length),
                      ),
                    PaintTitle(
                      to.name,
                      seed: 3,
                      width: title.width,
                      height: title.height,
                    ),
                    if (f.targets.length > 1)
                      _Arrow(
                        left: false,
                        size: 40 * u,
                        onTap: () =>
                            taps.copyTarget((f.targetI + 1) % f.targets.length),
                      ),
                  ],
                )
              : const SizedBox.shrink(),
          info(
            to,
            f.fromSystem,
            after,
            after == 'Not enough room' ? Look.danger : Tone.soft2,
          ),
        ),
        d.at(
          toX + 3,
          268,
          682,
          664,
          GridView.count(
            crossAxisCount: MemoryCardFlow.copyCols,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            childAspectRatio: (682 * d.sx / 3) / slotStep,
            children: [
              for (var i = 0; i < perPage; i++)
                Padding(
                  padding: EdgeInsets.only(right: 8 * d.sx, bottom: 8 * d.sy),
                  child: i < coming.length
                      ? _CopyCell(save: coming[i], u: u, arriving: true)
                      : const _Hole(),
                ),
            ],
          ),
        ),
        if (Texts.copyMore(f).isNotEmpty)
          d.at(
            toX,
            944,
            paneW,
            40,
            Center(child: line(Texts.copyMore(f), body(20 * u, Tone.soft2))),
          ),
        // the middle
        d.at(
          760,
          40,
          400,
          78,
          Box(
            fill: Tone.panelOn,
            width: 4,
            padding: EdgeInsets.symmetric(horizontal: 15 * d.sx),
            child: Center(child: plaqueText('COPY SAVES', 34 * u)),
          ),
        ),
        for (final (i, b) in MemoryCardFlow.copyButtons.indexed)
          d.at(
            772,
            190 + i * 126.0,
            376,
            114,
            PaintButton(
              b.label,
              key: ValueKey('copy-button-$i'),
              seed: i * 2,
              width: 376 * d.sx,
              height: 114 * d.sy,
              selected: f.inButtons && i == f.button,
              onTap: () => taps.copyButton(i),
            ),
          ),
        d.at(
          740,
          716,
          440,
          56,
          Center(child: line(Texts.copySummary(f), heavy(28 * u, Look.yellow))),
        ),
        if (f.message.isNotEmpty)
          d.at(
            740,
            780,
            440,
            150,
            Text(
              Texts.wrapped(f.message, 34).join('\n'),
              textAlign: TextAlign.center,
              style: body(22 * u, Look.warn),
            ),
          ),
      ],
    );
  }
}

/// A tappable < or > (another target, another colour...).
class _Arrow extends StatelessWidget {
  const _Arrow({required this.left, required this.size, this.onTap, this.ink});

  final bool left;
  final double size;
  final Color? ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: size * 0.35),
      child: Text(left ? '<' : '>', style: heavy(size, ink ?? Colors.white)),
    ),
  );
}

class _CompactCopy extends StatelessWidget {
  const _CompactCopy({required this.f, required this.taps, required this.d});

  final MemoryCardFlow f;
  final Taps taps;
  final Dims d;

  @override
  Widget build(BuildContext context) {
    final to = f.target();
    final source = f.source;
    final after = Texts.copyTargetText(f);
    final cols = math.max(3, (d.size.width - 16) ~/ 104);
    final cellH = d.landscape ? 92.0 : 104.0;
    Widget cardRow(
      MemoryCard? card,
      String name,
      String text,
      Color ink, {
      List<Widget> lead = const [],
      List<Widget> tail = const [],
    }) => Box(
      fill: Tone.panelSoft,
      edge: Tone.edge2,
      width: 2,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          ...lead,
          CardArt(card, system: f.fromSystem, width: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [line(name, heavy(12.5)), line(text, body(11, ink))],
            ),
          ),
          ...tail,
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              plaqueText('COPY SAVES', 17),
              const Spacer(),
              line(Texts.copySummary(f), heavy(13, Look.yellow)),
            ],
          ),
          const SizedBox(height: 4),
          cardRow(
            source,
            source?.name ?? '${f.list.length} SELECTED',
            source != null ? source.freeText() : Texts.copyFromText(f),
            Tone.soft2,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: KeepInSight(
              selected: f.inButtons ? -1 : f.cell,
              itemExtent: cellH,
              perRow: cols,
              builder: (context, scroll) => GridView.builder(
                key: const ValueKey('copy-from'),
                controller: scroll,
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: cellH,
                ),
                itemCount: f.list.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.all(2),
                  child: _CopyCell(
                    key: ValueKey('copy-cell-$i'),
                    save: f.list[i],
                    u: 0.5,
                    nameSize: 11,
                    marked: f.marked.contains(
                      MemoryCardFlow.markKey(f.list[i]),
                    ),
                    here: !f.inButtons && i == f.cell,
                    onTap: () => taps.copyCell(i),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (to != null)
            cardRow(
              to,
              'To ${to.name}',
              '${f.arriving().length} arriving. $after',
              after == 'Not enough room' ? Look.danger : Tone.soft2,
              lead: [
                if (f.targets.length > 1)
                  _Arrow(
                    left: true,
                    size: 22,
                    onTap: () =>
                        taps.copyTarget((f.targetI - 1) % f.targets.length),
                  ),
              ],
              tail: [
                if (f.targets.length > 1)
                  _Arrow(
                    left: false,
                    size: 22,
                    onTap: () =>
                        taps.copyTarget((f.targetI + 1) % f.targets.length),
                  ),
              ],
            ),
          if (f.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                f.message,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: body(11.5, Look.warn),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (i, b) in MemoryCardFlow.copyButtons.indexed)
                PaintButton(
                  b.label,
                  key: ValueKey('copy-button-$i'),
                  seed: i * 2,
                  width: math.min((d.size.width - 16) / 4, 150),
                  height: d.size.height >= 640 ? 52 : 44,
                  selected: f.inButtons && i == f.button,
                  onTap: () => taps.copyButton(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- customize ----------------------------------------------------------------

class _Look extends StatelessWidget {
  const _Look({
    required this.f,
    required this.taps,
    required this.d,
    required this.folder,
  });

  final MemoryCardFlow f;
  final Taps taps;
  final Dims d;
  final String folder;

  Color _swatch(MemoryCard? card) {
    final hex = CardLooks.palette[f.colorI].$2.split('/')[0];
    if (hex.isEmpty) {
      return card != null ? Look.system(card.system, 'shell') : Colors.grey;
    }
    return Color(0xFF000000 | int.parse(hex, radix: 16));
  }

  Widget _row(int i, double h, double label, double value, double pad) {
    final on = i == f.lookRow;
    final ink = on ? Tone.onYellow : Colors.white;
    final card = f.lookCard;
    final valueStyle = (on ? heavy : body)(value, ink);
    Widget content;
    if (i < 2) {
      content = Row(
        children: [
          _Arrow(
            left: true,
            size: value,
            ink: ink,
            onTap: () => taps.lookChange(i, -1),
          ),
          Flexible(
            child: line(i == 0 ? f.colorName() : f.stickerName(), valueStyle),
          ),
          _Arrow(
            left: false,
            size: value,
            ink: ink,
            onTap: () => taps.lookChange(i, 1),
          ),
        ],
      );
    } else {
      content = line(Texts.lookValues(f)[i], valueStyle);
    }
    return SizedBox(
      height: h,
      child: ChoiceBox(
        key: ValueKey('look-$i'),
        on: on,
        dark: Look.chip,
        edge: Tone.edge2,
        padding: EdgeInsets.symmetric(horizontal: pad),
        onTap: () => taps.lookRow(i),
        child: Row(
          children: [
            SizedBox(
              width: label * 6.2,
              child: line(
                MemoryCardFlow.lookRows[i],
                bold(label, on ? ink : Look.cyan),
              ),
            ),
            Expanded(child: content),
            if (i == 0)
              Container(
                width: h * 0.6,
                height: h * 0.6,
                decoration: BoxDecoration(
                  color: _swatch(card),
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = f.lookCard;
    final help = Texts.lookHelp(
      folder.isNotEmpty ? folder : 'your Stickers folder',
    );
    if (d.compact) {
      final side = d.landscape;
      final art = card == null
          ? const SizedBox.shrink()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                line(card.name, bold(12.5), align: TextAlign.center),
                const SizedBox(height: 6),
                Glow(
                  alpha: 0.45,
                  grow: 8,
                  child: CardArt(card, width: side ? 96 : 110),
                ),
              ],
            );
      final rows = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < MemoryCardFlow.lookRows.length; i++) ...[
            _row(i, 44, 11.5, 14, 10),
            const SizedBox(height: 6),
          ],
          for (final l in help) Text(l, style: body(10.5, Tone.soft2)),
        ],
      );
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Box(
            fill: Tone.panelOn,
            width: 3,
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                plaqueText('CUSTOMIZE CARD', 20),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: side
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 120, child: art),
                              const SizedBox(width: 10),
                              Expanded(child: rows),
                            ],
                          )
                        : Column(
                            children: [art, const SizedBox(height: 12), rows],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final u = d.u;
    final cardAt = d.pc(390, 280, 300, 390);
    return Stack(
      children: [
        d.at(300, 110, 1320, 820, const Box(fill: Tone.panelOn, width: 4)),
        d.at(
          340,
          140,
          1240,
          70,
          Center(child: plaqueText('CUSTOMIZE CARD', 40 * u)),
        ),
        if (card != null) ...[
          d.at(300, 232, 480, 40, Center(child: line(card.name, bold(24 * u)))),
          Positioned.fromRect(
            rect: cardAt.inflate(30 * u),
            child: const Glow(alpha: 0.45),
          ),
          Positioned.fromRect(
            rect: cardAt,
            child: Center(
              child: CardArt(
                card,
                width: math.min(cardAt.width, cardAt.height / CardArt.aspect),
              ),
            ),
          ),
        ],
        for (var i = 0; i < MemoryCardFlow.lookRows.length; i++)
          d.at(
            820,
            260 + i * 114.0,
            720,
            92,
            _row(i, 92 * d.sy, 22 * u, 26 * u, 22 * u),
          ),
        d.at(
          820,
          716,
          720,
          200,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in help)
                Padding(
                  padding: EdgeInsets.only(bottom: 6 * d.sy),
                  child: Text(
                    l,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: body(20 * u, Tone.soft2),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
