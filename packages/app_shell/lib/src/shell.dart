import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'crash_log.dart';
import 'exporter.dart';
import 'pages.dart';
import 'settings.dart';
import 'storage.dart';

/// Everything that identifies an app built on the shell.
class AppShellConfig {
  const AppShellConfig({
    required this.id,
    required this.name,
    this.version = '0.1.0',
    this.description = '',
    this.accent = const Color(0xFF4F8CFF),
    this.settings = const [],
    this.defaultThemeMode = ThemeMode.system,
  });

  /// Folder name for the app's data (letters, digits, underscores).
  final String id;
  final String name;
  final String version;
  final String description;

  /// Seed colour for the theme.
  final Color accent;

  /// The app's own settings (the shell adds theme and vibration).
  final List<Setting<Object?>> settings;
  final ThemeMode defaultThemeMode;
}

/// Services the shell gives every app; get it with `Shell.of(context)`.
class ShellServices {
  ShellServices({
    required this.config,
    required this.storage,
    required this.settings,
    required this.crashLog,
    this.exporter = const Exporter(),
  });

  final AppShellConfig config;
  final AppStorage storage;
  final SettingsStore settings;
  final CrashLog crashLog;
  final Exporter exporter;

  /// Light haptic tick, if the user has vibration feedback on.
  void tick() {
    if (settings.get(hapticsSetting)) HapticFeedback.selectionClick();
  }

  /// Creates the services, using the app's support folder on the device.
  static Future<ShellServices> create(
    AppShellConfig config, {
    Directory? root,
  }) async {
    final base = root ?? await getApplicationSupportDirectory();
    final storage = AppStorage(Directory(p.join(base.path, config.id)));
    final settings = SettingsStore(storage, [
      themeModeSetting,
      hapticsSetting,
      ...config.settings,
    ]);
    await settings.load();
    return ShellServices(
      config: config,
      storage: storage,
      settings: settings,
      crashLog: CrashLog(storage),
    );
  }
}

class Shell extends InheritedWidget {
  const Shell({super.key, required this.services, required super.child});

  final ShellServices services;

  static ShellServices of(BuildContext context) {
    final shell = context.dependOnInheritedWidgetOfExactType<Shell>();
    assert(shell != null, 'No Shell above this widget. Use runShellApp.');
    return shell!.services;
  }

  @override
  bool updateShouldNotify(Shell old) => old.services != services;
}

/// Starts an app on the shell: storage, settings, error logging and theme.
Future<void> runShellApp(
  AppShellConfig config,
  Widget Function(BuildContext context) home,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await ShellServices.create(config);
  installErrorHandlers(services.crashLog);
  runApp(ShellApp(services: services, home: home));
}

/// Sends uncaught Flutter and Dart errors to [log] (and still prints them).
void installErrorHandlers(CrashLog log) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(
      log.record(
        details.exception,
        details.stack,
        context: details.context?.toString(),
      ),
    );
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(log.record(error, stack, fatal: true));
    return false; // keep default handling (logs to console)
  };
}

ThemeData shellTheme(Color accent, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

class ShellApp extends StatelessWidget {
  const ShellApp({super.key, required this.services, required this.home});

  final ShellServices services;
  final Widget Function(BuildContext context) home;

  @override
  Widget build(BuildContext context) {
    final config = services.config;
    return Shell(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) {
          final mode = switch (services.settings.get(themeModeSetting)) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => config.defaultThemeMode,
          };
          return MaterialApp(
            title: config.name,
            debugShowCheckedModeBanner: false,
            theme: shellTheme(config.accent, Brightness.light),
            darkTheme: shellTheme(config.accent, Brightness.dark),
            themeMode: mode,
            home: Builder(builder: home),
          );
        },
      ),
    );
  }
}

/// App-bar actions most apps want: Settings and About.
List<Widget> shellActions(BuildContext context) => [
  IconButton(
    tooltip: 'Settings',
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
  ),
  IconButton(
    tooltip: 'About',
    icon: const Icon(Icons.info_outline),
    onPressed: () => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AboutShellPage())),
  ),
];
