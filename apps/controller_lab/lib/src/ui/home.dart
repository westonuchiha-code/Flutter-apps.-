import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../layouts/layout.dart';
import '../model/controls.dart';
import '../model/lab.dart';
import '../model/session.dart';
import '../sdl/sdl_backend.dart';
import 'test_view.dart';

/// Wide enough for the list and the test side by side.
const wideLayout = 760.0;

/// The list of connected controllers, and (side by side on wide screens,
/// as its own page on narrow ones) the test of the selected one.
class ControllerLabHome extends StatefulWidget {
  const ControllerLabHome({
    super.key,
    required this.lab,
    this.autoTick = true,
    this.bodyColour = 'white',
    this.title = 'Controller Lab',
    this.actions = const [],
  });

  final ControllerLab lab;

  /// Read the controllers every frame (tests tick by hand).
  final bool autoTick;
  final String bodyColour;
  final String title;
  final List<Widget> actions;

  @override
  State<ControllerLabHome> createState() => ControllerLabHomeState();
}

class ControllerLabHomeState extends State<ControllerLabHome>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  int? selected;

  /// A test page is open (on narrow screens): pad presses are the test.
  bool _testPageOpen = false;

  ControllerLab get lab => widget.lab;

  @override
  void initState() {
    super.initState();
    lab.start();
    lab.addPressListener(_onPress);
    if (widget.autoTick) {
      _ticker = createTicker((_) => lab.tick())..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    lab.removePressListener(_onPress);
    super.dispose();
  }

  bool get _testing => selected != null || _testPageOpen;

  /// Moving around the app with a controller. SDL's pads don't reach
  /// Flutter as keys, so their presses are turned into focus moves here;
  /// Android's arrive as keys and Flutter already handles them.
  void _onPress(PadDevice d, GButton b) {
    if (!mounted || _testing || lab.backend is! SdlBackend) return;
    final focus = FocusManager.instance.primaryFocus;
    TraversalDirection? dir = switch (b) {
      GButton.dpadUp => TraversalDirection.up,
      GButton.dpadDown => TraversalDirection.down,
      GButton.dpadLeft => TraversalDirection.left,
      GButton.dpadRight => TraversalDirection.right,
      _ => null,
    };
    if (dir != null) {
      if (focus == null || focus.context == null) {
        FocusScope.of(context).nextFocus();
      } else {
        focus.focusInDirection(dir);
      }
      return;
    }
    if (b == confirmButton(d.info)) {
      final ctx = focus?.context;
      if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
    } else if (b == backButton(d.info)) {
      Navigator.of(context).maybePop();
    }
  }

  void _open(PadDevice d, bool wide) {
    if (wide) {
      setState(() => selected = d.info.id);
      return;
    }
    _testPageOpen = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (ctx) => Scaffold(
              body: SafeArea(
                child: TestView(
                  lab: lab,
                  deviceId: d.info.id,
                  bodyColour: widget.bodyColour,
                  onClose: () => Navigator.of(ctx).maybePop(),
                ),
              ),
            ),
          ),
        )
        .whenComplete(() => _testPageOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: widget.actions),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= wideLayout;
          return ListenableBuilder(
            listenable: lab,
            builder: (context, _) {
              if (selected != null && lab.byId(selected) == null) {
                selected = null;
              }
              final list = _DeviceList(
                lab: lab,
                selected: wide ? selected : null,
                onOpen: (d) => _open(d, wide),
              );
              if (!wide) return list;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: selected == null
                        ? const _PickHint()
                        : TestView(
                            key: ValueKey(selected),
                            lab: lab,
                            deviceId: selected!,
                            bodyColour: widget.bodyColour,
                            onClose: () => setState(() => selected = null),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PickHint extends StatelessWidget {
  const _PickHint();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Pick a controller to test it.',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.lab,
    required this.selected,
    required this.onOpen,
  });

  final ControllerLab lab;
  final int? selected;
  final void Function(PadDevice) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = lab.backend;
    final problem = lab.startProblem ?? b.problem;
    final status = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: problem != null
          ? Card(
              color: theme.colorScheme.errorContainer,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  '$problem\nUsing ${b.title} instead: buttons only, '
                  'no sticks or controller names.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            )
          : Text(
              b is SdlBackend
                  ? 'Reading controllers through ${b.title}, the library '
                        'RetroArch, PCSX2, RPCS3 and the PC XMB use.'
                  : 'Reading controllers through ${b.title}.',
              style: theme.textTheme.bodySmall,
            ),
    );
    final devices = lab.devices;
    return ListView(
      children: [
        status,
        if (devices.isEmpty) const _Empty(),
        for (final (i, d) in devices.indexed)
          _DeviceTile(
            device: d,
            session: lab.session(d),
            repaint: lab.frame,
            selected: d.info.id == selected,
            autofocus: i == 0,
            onTap: () => onOpen(d),
          ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.session,
    required this.repaint,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  final PadDevice device;
  final TestSession session;
  final ValueListenable<int> repaint;
  final bool selected, autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = device.info;
    final layout = layoutFor(i);
    return ListTile(
      autofocus: autofocus,
      selected: selected,
      leading: Icon(
        i.isGamepad ? Icons.sports_esports : Icons.gamepad_outlined,
        size: 32,
      ),
      title: Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${i.summary}\n${layout.title} · ${i.vidPid}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: ValueListenableBuilder(
        valueListenable: repaint,
        builder: (context, _, _) => Text(
          '${session.done}/${session.total}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sports_esports_outlined,
                size: 40,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No controllers yet',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Plug one in or pair it over Bluetooth: it shows up here by '
            'itself.\n\n'
            'Wii U Pro on the PC: pair "Nintendo RVL-CNT-01-UC" (red SYNC '
            'button on the back). Controller Lab turns on SDL\'s Wii driver '
            'for itself; other programs need the SDL_JOYSTICK_HIDAPI_WII=1 '
            'variable (docs/controllers/WII_U_PRO_PC_TEST.md).',
          ),
        ],
      ),
    );
  }
}
