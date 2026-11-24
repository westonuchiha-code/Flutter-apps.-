import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'speech_chip_lab',
  name: 'Speech Chip Lab',
  version: '0.1.0',
  description:
      'Type text and hear it on recreations of classic speech chips '
      '(TMS5220, SP0256, Votrax SC-01). Sing it on a keyboard, save it as a '
      'sample for the other apps.',
  accent: Color(0xFF7DC84A),
);

void main() => runShellApp(appConfig, (_) => const HomePage());
