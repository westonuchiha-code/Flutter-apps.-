import 'library/scanner.dart';
import 'library/systems.dart';

/// An Android intent, as the platform side expects it.
class LaunchSpec {
  const LaunchSpec({
    required this.package,
    this.activity,
    this.action,
    this.dataPath,
    this.mimeType,
    this.extras = const {},
  });

  final String package;

  /// Full class name, or null to let Android pick the package's activity.
  final String? activity;
  final String? action;

  /// A file path given as the intent's data (file://).
  final String? dataPath;
  final String? mimeType;

  /// String or List of String values.
  final Map<String, Object> extras;

  Map<String, Object?> toMap() => {
    'package': package,
    'activity': activity,
    'action': action,
    'data': dataPath,
    'type': mimeType,
    'extras': extras,
  };
}

/// Android packages of each emulator, preferred first (Play Store and
/// sideloaded builds have different names).
const runnerPackages = <Runner, List<String>>{
  Runner.retroarch: [
    'com.retroarch.aarch64',
    'com.retroarch',
    'com.retroarch.ra32',
  ],
  Runner.ppsspp: ['org.ppsspp.ppssppgold', 'org.ppsspp.ppsspp'],
  Runner.duckstation: ['com.github.stenzek.duckstation'],
  Runner.dolphin: ['org.dolphinemu.dolphinemu', 'org.dolphinemu.mmjr'],
};

List<String> get allRunnerPackages => [
  for (final l in runnerPackages.values) ...l,
];

/// How a game will start: which emulator, core and package.
class LaunchChoice {
  const LaunchChoice(this.runner, this.package, {this.core});
  final Runner runner;
  final String package;
  final String? core;

  String get label =>
      core == null ? runner.label : '${runner.label} · ${core!}';
}

/// Picks the emulator for [system] from what is installed. [core] overrides
/// the system's first RetroArch core; [preferRetroArch] skips standalone
/// emulators (for consoles RetroArch also runs).
LaunchChoice? chooseRunner(
  GameSystem system,
  Set<String> installed, {
  String? core,
  bool preferRetroArch = false,
}) {
  final order = preferRetroArch && system.runners.contains(Runner.retroarch)
      ? [Runner.retroarch]
      : system.runners;
  for (final r in order) {
    for (final pkg in runnerPackages[r]!) {
      if (installed.contains(pkg)) {
        return LaunchChoice(
          r,
          pkg,
          core: r == Runner.retroarch ? (core ?? system.cores.first) : null,
        );
      }
    }
  }
  return null;
}

/// The intent that starts [game] with [choice]. [raConfig]: RetroArch's
/// settings file (the menu's own, so saves land where the sync looks).
LaunchSpec launchSpec(Game game, LaunchChoice choice, {String? raConfig}) {
  final pkg = choice.package;
  switch (choice.runner) {
    case Runner.retroarch:
      // RetroArch's own documented extras: ROM, core library and config.
      return LaunchSpec(
        package: pkg,
        activity: 'com.retroarch.browser.retroactivity.RetroActivityFuture',
        action: 'android.intent.action.MAIN',
        extras: {
          'ROM': game.path,
          'LIBRETRO':
              '/data/data/$pkg/cores/${choice.core}_libretro_android.so',
          'CONFIGFILE':
              raConfig ??
              '/storage/emulated/0/Android/data/$pkg/files/retroarch.cfg',
          'QUITFOCUS': '',
        },
      );
    case Runner.ppsspp:
      return LaunchSpec(
        package: pkg,
        activity: 'org.ppsspp.ppsspp.PpssppActivity',
        action: 'android.intent.action.VIEW',
        dataPath: game.path,
        mimeType: 'application/octet-stream',
      );
    case Runner.duckstation:
      return LaunchSpec(
        package: pkg,
        activity: 'com.github.stenzek.duckstation.EmulationActivity',
        action: 'android.intent.action.MAIN',
        extras: {'bootPath': game.path},
      );
    case Runner.dolphin:
      return LaunchSpec(
        package: pkg,
        activity: 'org.dolphinemu.dolphinemu.ui.main.MainActivity',
        action: 'android.intent.action.MAIN',
        extras: {
          'AutoStartFiles': [game.path],
        },
      );
  }
}
