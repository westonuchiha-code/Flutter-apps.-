// Never change a game save while its emulator runs: it writes its own copy
// back over the change. Android can't see other apps, so the player is asked
// ("Close RetroArch fully first (not just Home). Is it closed?", NOT YET
// first), and a yes counts for 2 minutes (as packages/save_screens'
// EmulatorCheck). Windows and Linux look at the running programs (save_kit's
// CardOwners, the PC's PokeSaves.in_use); when they can't be listed, the
// question is asked instead.
import 'dart:io';

import 'games.dart';

enum GuardMode {
  /// Ask the player (Android).
  ask,

  /// Look at the running programs (Windows, Linux).
  processes,

  /// Tests only: nothing is checked.
  none,
}

class SaveGuard {
  SaveGuard.ask({this.remember = const Duration(minutes: 2), this.now})
    : mode = GuardMode.ask,
      check = null;

  /// [check]: '' when nothing has the save open, why when something does,
  /// null when it can't tell (top-level: it runs in the background).
  SaveGuard.processes({
    this.check = emulatorRunning,
    this.remember = const Duration(minutes: 2),
    this.now,
  }) : mode = GuardMode.processes;

  /// Tests: never asks, never checks.
  SaveGuard.none()
    : mode = GuardMode.none,
      check = null,
      remember = Duration.zero,
      now = null;

  /// Android asks; Windows / Linux look.
  factory SaveGuard.forPlatform() =>
      Platform.isAndroid ? SaveGuard.ask() : SaveGuard.processes();

  final GuardMode mode;
  final String? Function(String path)? check;

  /// How long a yes counts.
  final Duration remember;
  final DateTime Function()? now;

  DateTime? _yesAt;

  DateTime _now() => (now ?? DateTime.now)();

  /// The player said yes, and it still counts.
  bool get fresh {
    final at = _yesAt;
    return at != null && _now().difference(at) < remember;
  }

  /// The player said the emulator is closed.
  void yes() => _yesAt = _now();

  void reset() => _yesAt = null;

  /// The emulator a save belongs to ("RetroArch" for the menu's folders).
  static String nameFor(String path) => emulatorNamed(path) ?? 'RetroArch';
}

/// The question asked before the first change to a game save (and again
/// after [SaveGuard.remember]).
class ClosedQuestion {
  ClosedQuestion(this.name, this.run);

  /// "RetroArch".
  final String name;

  /// The change waiting for a yes.
  final Future<void> Function() run;

  /// The answers, the safe one first.
  static const answers = ['NOT YET', "YES, IT'S CLOSED"];

  /// The answer highlighted (NOT YET to start with).
  int index = 0;

  String get title => 'IS ${name.toUpperCase()} CLOSED?';

  List<String> get lines => [
    'Close $name fully first (not just Home). Is it closed?',
    "If it's still open it writes its own copy of the save back over "
        'the change.',
  ];
}
