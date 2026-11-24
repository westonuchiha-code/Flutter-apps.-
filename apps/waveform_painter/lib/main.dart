import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'waveform_painter',
  name: 'Waveform Painter',
  version: '0.1.0',
  description:
      'Draw a wave (or take one from a picture) and play it as an '
      'instrument. Waves save to the Asset Locker for the other apps.',
  accent: Color(0xFF29B6A6),
);

void main() => runShellApp(appConfig, (_) => const HomePage());
