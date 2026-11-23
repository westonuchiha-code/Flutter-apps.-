import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'src/app/theremin_controller.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/app/exporter.dart';
import 'src/app/settings_store.dart';
import 'src/audio/synth_output.dart';
import 'src/recording/take_store.dart';
import 'src/input/camera_backend.dart';
import 'src/ui/theremin_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isAndroid) {
    // Camera frames are rotated for portrait; keep the phone upright.
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  final dataDir = await getApplicationSupportDirectory();
  runApp(
    OpticalThereminApp(
      controller: ThereminController(
        cameraBackend: CameraBackend.forCurrentPlatform(),
        synth: SoLoudSynthOutput(),
        takeStore: FileTakeStore(Directory(p.join(dataDir.path, 'recordings'))),
        settingsStore: FileSettingsStore(dataDir),
        exporter: PlatformExporter(),
      ),
    ),
  );
}

class OpticalThereminApp extends StatefulWidget {
  const OpticalThereminApp({super.key, required this.controller});

  final ThereminController controller;

  @override
  State<OpticalThereminApp> createState() => _OpticalThereminAppState();
}

class _OpticalThereminAppState extends State<OpticalThereminApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Optical Theremin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: ThereminPage(controller: widget.controller),
    );
  }
}
