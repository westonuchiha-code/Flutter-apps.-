import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../layouts/layout.dart';
import '../layouts/raw.dart';
import '../model/controls.dart';
import '../model/lab.dart';
import '../model/session.dart';
import 'info_view.dart';
import 'pad_canvas.dart';

/// Ticks [ControllerLab.backButton] must be held to leave (about 1 s).
const holdToLeave = 60;

enum TestTab { test, raw, info }

/// The live test of one controller: its drawing lighting up, stick
/// readouts, the checklist; the raw joystick; what SDL says it is.
class TestView extends StatefulWidget {
  const TestView({
    super.key,
    required this.lab,
    required this.deviceId,
    required this.onClose,
    this.bodyColour = 'white',
  });

  final ControllerLab lab;
  final int deviceId;

  /// Leave the test (held back button, Escape, the close button).
  final VoidCallback onClose;

  /// The Wii U Pro's colour ('white' / 'black').
  final String bodyColour;

  @override
  State<TestView> createState() => _TestViewState();
}

class _TestViewState extends State<TestView> {
  TestTab tab = TestTab.test;
  bool _left = false;
  final FocusNode _focus = FocusNode(debugLabel: 'test view');

  @override
  void initState() {
    super.initState();
    widget.lab.frame.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(TestView old) {
    super.didUpdateWidget(old);
    if (old.lab != widget.lab) {
      old.lab.frame.removeListener(_onFrame);
      widget.lab.frame.addListener(_onFrame);
    }
    if (old.deviceId != widget.deviceId) _left = false;
  }

  @override
  void dispose() {
    widget.lab.frame.removeListener(_onFrame);
    _focus.dispose();
    super.dispose();
  }

  void _onFrame() {
    if (_left) return;
    if ((widget.lab.backHeld[widget.deviceId] ?? 0) >= holdToLeave) {
      _left = true;
      widget.onClose();
    }
  }

  /// Controller keys are the test here, not navigation (Android sends
  /// them as key events too); Escape leaves.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape && e is KeyDownEvent) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    final controllerKey =
        k.keyLabel.startsWith('Game Button') ||
        (defaultTargetPlatform == TargetPlatform.android &&
            (k == LogicalKeyboardKey.arrowUp ||
                k == LogicalKeyboardKey.arrowDown ||
                k == LogicalKeyboardKey.arrowLeft ||
                k == LogicalKeyboardKey.arrowRight ||
                k == LogicalKeyboardKey.goBack ||
                k == LogicalKeyboardKey.select));
    return controllerKey ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.lab,
      builder: (context, _) {
        final d = widget.lab.byId(widget.deviceId);
        if (d == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_off, size: 48),
                  const SizedBox(height: 12),
                  const Text('That controller went away.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: widget.onClose,
                    child: const Text('Back to the list'),
                  ),
                ],
              ),
            ),
          );
        }
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: _content(context, d),
        );
      },
    );
  }

  Widget _content(BuildContext context, PadDevice d) {
    final theme = Theme.of(context);
    final t = d.info.gamepadType;
    final backName =
        t == GamepadType.ps3 || t == GamepadType.ps4 || t == GamepadType.ps5
        ? '○'
        : 'B';
    final screen = MediaQuery.sizeOf(context);
    final stacked = screen.width < 560 && screen.height > screen.width;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.info.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          ValueListenableBuilder(
                            valueListenable: widget.lab.frame,
                            builder: (context, _, _) {
                              final held = widget.lab.backHeld[d.info.id] ?? 0;
                              return Text(
                                !d.info.isGamepad
                                    ? 'Esc or ✕ to go back'
                                    : held > 0
                                    ? 'Keep holding $backName to go back…'
                                    : 'Hold $backName for 1 s (or Esc) to go back',
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SegmentedButton<TestTab>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: TestTab.test, label: Text('Test')),
                    ButtonSegment(value: TestTab.raw, label: Text('Raw')),
                    ButtonSegment(value: TestTab.info, label: Text('Info')),
                  ],
                  selected: {tab},
                  onSelectionChanged: (s) => setState(() => tab = s.first),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.info.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      ValueListenableBuilder(
                        valueListenable: widget.lab.frame,
                        builder: (context, _, _) {
                          final held = widget.lab.backHeld[d.info.id] ?? 0;
                          return Text(
                            !d.info.isGamepad
                                ? 'Esc or ✕ to go back'
                                : held > 0
                                ? 'Keep holding $backName to go back…'
                                : 'Hold $backName for 1 s (or Esc) to go back',
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SegmentedButton<TestTab>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: TestTab.test, label: Text('Test')),
                    ButtonSegment(value: TestTab.raw, label: Text('Raw')),
                    ButtonSegment(value: TestTab.info, label: Text('Info')),
                  ],
                  selected: {tab},
                  onSelectionChanged: (s) => setState(() => tab = s.first),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
    );
    final body = switch (tab) {
      TestTab.test => _testTab(context, d, widget.lab.session(d)),
      TestTab.raw => _testTab(context, d, widget.lab.rawSession(d)),
      TestTab.info => InfoView(
        info: d.info,
        layout: layoutFor(d.info),
        details: widget.lab.backend.details,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(child: body),
      ],
    );
  }

  Widget _testTab(BuildContext context, PadDevice d, TestSession session) {
    final palette = padPalette(context, variant: widget.bodyColour);
    final drawing = PadCanvas(
      layout: session.layout,
      info: d.info,
      state: d.state,
      session: session,
      repaint: widget.lab.frame,
      palette: palette,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final side = c.maxWidth >= 420 && c.maxWidth > c.maxHeight * 1.15;
        final raw = session.layout is RawLayout;
        Widget drawingBox = Padding(
          padding: const EdgeInsets.all(8),
          child: Center(child: drawing),
        );
        // Raw drawings can be tall (many buttons): let them scroll.
        if (raw) {
          drawingBox = SingleChildScrollView(child: drawingBox);
        }
        final panel = _Panel(lab: widget.lab, device: d, session: session);
        if (side) {
          final panelWidth = (c.maxWidth * 0.3).clamp(150.0, 340.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: drawingBox),
              SizedBox(
                width: panelWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
                  child: panel,
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: raw ? double.infinity : c.maxHeight * 0.62,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(heightFactor: 1, child: drawing),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: panel,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Progress, actions, stick/trigger readouts and the checklist.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.lab,
    required this.device,
    required this.session,
  });

  final ControllerLab lab;
  final PadDevice device;
  final TestSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: lab.frame,
      builder: (context, _, _) {
        final hasSticks = session.parts.any((p) => p.kind == PartKind.stick);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.complete
                        ? 'Every button checked'
                        : '${session.done} of ${session.total} checked',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: session.complete ? const Color(0xFF2E9E4F) : null,
                    ),
                  ),
                ),
                if (session.complete)
                  const Icon(Icons.verified, color: Color(0xFF2E9E4F)),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: session.total == 0 ? 0 : session.done / session.total,
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, c) {
                final measuring = session.sticks.values.any((s) => s.measuring);
                final actions = [
                  if (hasSticks)
                    (
                      Icons.adjust,
                      'Measure rest',
                      measuring ? null : () => session.measureRest(),
                    ),
                  if (lab.backend.canRumble)
                    (
                      Icons.vibration,
                      'Rumble',
                      () => lab.backend.rumble(device.info.id),
                    ),
                  (Icons.restart_alt, 'Reset', () => lab.reset(device)),
                ];
                // A narrow side panel (the Retroid): icons only.
                if (c.maxWidth < 240) {
                  return Wrap(
                    children: [
                      for (final (icon, label, onTap) in actions)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: label,
                          onPressed: onTap,
                          icon: Icon(icon),
                        ),
                    ],
                  );
                }
                return Wrap(
                  spacing: 2,
                  children: [
                    for (final (icon, label, onTap) in actions)
                      TextButton.icon(
                        onPressed: onTap,
                        icon: Icon(icon, size: 18),
                        label: Text(label),
                      ),
                  ],
                );
              },
            ),
            for (final p in session.parts)
              if (p.kind == PartKind.stick)
                _StickReadout(part: p, state: device.state, session: session)
              else if (p.kind == PartKind.trigger)
                _line(
                  context,
                  '${p.label}: ${(p.value(device.state) * 100).round()}%'
                  '${session.axes[p.id] != null ? ' (max ${(session.axes[p.id]!.max * 100).round()}%)' : ''}',
                ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final p in session.parts)
                  _CheckChip(
                    label: p.label,
                    checked: session.checked.contains(p.id),
                    active: p.active(device.state),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  static Widget _line(BuildContext context, String s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      s,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    ),
  );
}

String _signed(double v) => '${v < 0 ? '−' : '+'}${v.abs().toStringAsFixed(2)}';

class _StickReadout extends StatelessWidget {
  const _StickReadout({
    required this.part,
    required this.state,
    required this.session,
  });

  final LayoutPart part;
  final PadState state;
  final TestSession session;

  @override
  Widget build(BuildContext context) {
    final (x, y) = part.stick(state);
    final st = session.sticks[part.id];
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final dirs = st == null
        ? ''
        : [
            if (!st.up) '↑',
            if (!st.down) '↓',
            if (!st.left) '←',
            if (!st.right) '→',
          ].join();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${part.label}: x ${_signed(x)}  y ${_signed(y)}  '
            '(${(part.value(state) * 100).round()}%)',
            style: style?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (st != null)
            Text(
              'Range x ${_signed(st.minX)}..${_signed(st.maxX)}, '
              'y ${_signed(st.minY)}..${_signed(st.maxY)}'
              '${dirs.isEmpty ? '' : '  · still to reach: $dirs'}',
              style: style,
            ),
          if (st != null && st.measuring)
            Text('Measuring at rest: let go of the sticks…', style: style)
          else if (st?.restDrift != null)
            Text(
              'At rest it drifts ${(st!.restDrift! * 100).toStringAsFixed(1)}%'
              ' → deadzone ≈ ${(st.suggestedDeadzone! * 100).round()}%',
              style: style,
            ),
        ],
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({
    required this.label,
    required this.checked,
    required this.active,
  });

  final String label;
  final bool checked, active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF29B6F6)
            : checked
            ? const Color(0xFF2E9E4F).withValues(alpha: 0.16)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            checked ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: checked ? const Color(0xFF2E9E4F) : cs.outline,
          ),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
