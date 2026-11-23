import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/models.dart';
import 'glyphs.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the button-by-button guide for [cheat].
Future<void> showFollowAlong(BuildContext context, Cheat cheat) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8000000),
    builder: (_) => FollowAlongSheet(cheat: cheat),
  );
}

/// Steps through a cheat one button at a time. Keeps the screen on while
/// open (you're looking at the TV, not the phone) and buzzes on each step.
class FollowAlongSheet extends StatefulWidget {
  const FollowAlongSheet({super.key, required this.cheat});

  final Cheat cheat;

  @override
  State<FollowAlongSheet> createState() => _FollowAlongSheetState();
}

class _FollowAlongSheetState extends State<FollowAlongSheet> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _setWakelock(true);
  }

  @override
  void dispose() {
    _setWakelock(false);
    super.dispose();
  }

  static Future<void> _setWakelock(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // Not available (e.g. in tests): nothing to do.
    }
  }

  void _next() {
    final n = widget.cheat.buttons.length;
    if (_i >= n) {
      Navigator.pop(context);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _i++);
    if (_i >= n) HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final buttons = widget.cheat.buttons;
    final n = buttons.length;
    final done = _i >= n;
    final note = widget.cheat.note.isEmpty
        ? 'Enter this during play, not on the pause screen.'
        : widget.cheat.note;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF171C19), Color(0xFF0E1110)],
            ),
            border: Border(
              top: BorderSide(color: Colors.black, width: 2),
              left: BorderSide(color: Colors.black, width: 2),
              right: BorderSide(color: Colors.black, width: 2),
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            18 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF36413C),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              OutlinedText(
                widget.cheat.name,
                size: 20,
                stroke: 4,
                letterSpacing: 0.4,
              ),
              const SizedBox(height: 4),
              Text(
                note,
                style: const TextStyle(color: SaColors.dim, fontSize: 14.5),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var k = 0; k < n; k++)
                    GestureDetector(
                      onTap: () => setState(() => _i = k),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 120),
                        scale: k == _i ? 1.2 : 1,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: k < _i ? 0.28 : 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: k == _i
                                  ? const [
                                      BoxShadow(
                                        color: Color(0xF2F3B93A),
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ButtonGlyph(
                              buttons[k],
                              size: k == _i ? 52 : 44,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  done
                      ? 'All buttons entered. Look for the cheat activated message.'
                            .toUpperCase()
                      : 'BUTTON ${_i + 1} OF $n',
                  textAlign: TextAlign.center,
                  style: condensed(
                    size: 15,
                    spacing: 1.4,
                    color: done ? SaColors.money : SaColors.dim,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SaButton(
                      'Back',
                      kind: SaButtonKind.ghost,
                      onPressed: _i == 0 ? null : () => setState(() => _i--),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SaButton(
                      done ? 'Done' : 'Pressed it',
                      onPressed: _next,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SaButton(
                    'Start over',
                    small: true,
                    kind: SaButtonKind.ghost,
                    onPressed: () => setState(() => _i = 0),
                  ),
                  SaButton(
                    'Close',
                    small: true,
                    kind: SaButtonKind.ghost,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
