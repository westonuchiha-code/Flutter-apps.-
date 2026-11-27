import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'src/diag.dart';
import 'src/tv_controller.dart';
import 'src/ui/tv_page.dart';

/// How long the first picture may take before the program gives up.
const _startupPatience = Duration(seconds: 30);

/// The shared shell (packages/app_shell), used here only for its error log,
/// which the Dev Dashboard reads through the Asset Locker.
const appConfig = AppShellConfig(
  id: 'crt_tv',
  name: 'CRT TV',
  version: '0.1.0',
  description:
      'A personal retro TV: folders of shows, movies and commercials become '
      'channels that play around the clock.',
  accent: Color(0xFF5CFF3A),
  defaultThemeMode: ThemeMode.dark,
);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // On a console there's no keyboard to get out with, so a start-up that
  // never produces a picture must not sit there holding the screen.
  // (Desktop only: a phone app can start behind the lock screen, where
  // nothing is drawn until it's unlocked.)
  var pictureUp = false;
  Timer(_startupPatience, () {
    if (pictureUp || Platform.isAndroid || Platform.isIOS) return;
    stderr.writeln(
      'CRT TV: no picture after ${_startupPatience.inSeconds} seconds, giving up.',
    );
    exit(3);
  });
  MediaKit.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    // Hide the phone's status and navigation bars while watching.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }
  ShellServices? shell;
  try {
    shell = await ShellServices.create(appConfig);
    installErrorHandlers(shell.crashLog);
  } catch (error) {
    // The TV works without its error log.
    stderr.writeln('CRT TV: no error log ($error)');
  }
  final controller = await TvController.create();
  // For consoles and living-room boxes: `crt_tv --fullscreen`.
  final fullscreen =
      args.contains('--fullscreen') ||
      Platform.environment['CRT_TV_FULLSCREEN'] == '1';
  final app = CrtTvApp(controller: controller, startFullscreen: fullscreen);
  runApp(shell == null ? app : Shell(services: shell, child: app));
  // The engine reports a frame's timings only once that frame has really
  // been drawn to the screen. (A callback after the first *layout* isn't
  // proof: it runs even when the graphics surface failed and nothing shows.)
  void onFirstPicture(List<FrameTiming> _) {
    if (pictureUp) return;
    pictureUp = true;
    WidgetsBinding.instance.removeTimingsCallback(onFirstPicture);
    // A launcher script watches for this line to know the screen is up.
    // The size is there for troubleshooting: it should match the display.
    // ignore: avoid_print
    print('CRT_TV_READY ${_pictureSize()}');
    Timer(const Duration(seconds: 3), () {
      // ignore: avoid_print
      print('CRT_TV_SIZE ${_pictureSize()} three seconds in');
    });
  }

  WidgetsBinding.instance.addTimingsCallback(onFirstPicture);
  startFrameReport();
}

/// The size, in real pixels, that the program is drawing at, and how many
/// real pixels it counts per layout pixel.
String _pictureSize() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return 'no window';
  final size = views.first.physicalSize;
  return '${size.width.round()}x${size.height.round()} scale ${views.first.devicePixelRatio}';
}

class CrtTvApp extends StatelessWidget {
  const CrtTvApp({
    super.key,
    required this.controller,
    this.startFullscreen = false,
  });

  final TvController controller;
  final bool startFullscreen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CRT TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5CFF3A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // Flutter's Windows accessibility bridge crashes the app when the screen
      // changes while something is reading the accessibility tree. Other
      // systems keep theirs, so screen readers still work there.
      builder: (context, child) => Platform.isWindows
          ? ExcludeSemantics(child: child)
          : child ?? const SizedBox.shrink(),
      home: TvPage(controller: controller, startFullscreen: startFullscreen),
    );
  }
}
