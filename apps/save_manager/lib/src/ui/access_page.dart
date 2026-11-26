/// Android: the saves live in the emulators' own folders, which only an
/// app with "All files access" can read. This page asks for it, and
/// checks again whenever the app comes back.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import 'kit.dart';

class AccessPage extends StatelessWidget {
  const AccessPage({super.key, required this.onAllow, required this.onCheck});

  /// Opens Android's "All files access" page.
  final VoidCallback onAllow;

  /// Checks again.
  final VoidCallback onCheck;

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.select) {
      onAllow();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.gameButtonY ||
        k == LogicalKeyboardKey.gameButtonX) {
      onCheck();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _key,
    child: MemoryBackdrop(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Box(
                fill: Tone.panelOn,
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FittedBox(
                      child: OutlinedText(
                        'ONE THING FIRST',
                        size: 26,
                        color: Look.yellow,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Your memory cards are in the emulators\' own folders '
                      '(RetroArch, DuckStation, NetherSX2, Dolphin, Flycast...). '
                      'Android only lets an app reach those with "All files '
                      'access".',
                      textAlign: TextAlign.center,
                      style: body(15),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Turn it on for Save Manager on the next screen, then come '
                      'back. Nothing is changed without asking, and every change '
                      'is backed up first.',
                      textAlign: TextAlign.center,
                      style: body(13.5, Look.soft),
                    ),
                    const SizedBox(height: 18),
                    PaintButton(
                      'ALLOW ACCESS',
                      key: const ValueKey('allow-access'),
                      selected: true,
                      width: 240,
                      height: 64,
                      onTap: onAllow,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onCheck,
                      child: Text(
                        'I turned it on: check again',
                        style: body(13, Look.cyan),
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
