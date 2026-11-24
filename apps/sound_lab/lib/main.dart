import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'sound_lab',
  name: 'Sound Lab',
  version: '0.1.0',
  description:
      'Play the synth engines, drawn waves or samples through a chain of up '
      'to 8 effects, watch the waveform and spectrum, and save sounds every '
      'music app can load.',
  accent: Color(0xFFF2A33A),
);

void main() => runShellApp(appConfig, (_) => const HomePage());
