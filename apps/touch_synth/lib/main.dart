import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'app/synth_controller.dart';
import 'audio/poly_output.dart';
import 'ui/controls.dart';
import 'ui/pad.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF39E0FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0B12),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(flex: 3, child: TouchPad(controller: controller)),
              const VerticalDivider(width: 1, color: Color(0xFF2A2A3A)),
              SizedBox(
                width: 320,
                child: ControlsPanel(controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
