import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model/game_state.dart';
import 'render/monster_art.dart';
import 'ui/app_shell.dart';
import 'ui/scan_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final game = GameState(FileSaveStore(Directory(p.join(dir.path, 'save'))));
  await Future.wait([game.load(), MonsterArt.instance.load()]);
  runApp(ScanRanchApp(game: game));
}

class ScanRanchApp extends StatelessWidget {
  const ScanRanchApp({super.key, required this.game, this.scanner});

  final GameState game;

  /// Replaces the camera scanner (tests).
  final ScannerBuilder? scanner;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scan Ranch',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AppShell(game: game, scanner: scanner),
    );
  }
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF7CFF4F),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF111318),
        primary: const Color(0xFF8CFF5A),
        onPrimary: const Color(0xFF0B1A05),
      );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0B0C10),
  );
}
