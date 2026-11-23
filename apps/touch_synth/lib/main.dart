import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'app/synth_controller.dart';
import 'audio/poly_output.dart';
import 'ui/home.dart';
import 'ui/style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final controller = SynthController(
    output: SoLoudPolyOutput(),
    store: FileSettingsStore(await getApplicationSupportDirectory()),
  );
  await controller.init();
  runApp(TouchSynthApp(controller: controller));
}

class TouchSynthApp extends StatelessWidget {
  const TouchSynthApp({super.key, required this.controller});

  final SynthController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Touch Synth',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: SynthHome(controller: controller),
    );
  }
}
