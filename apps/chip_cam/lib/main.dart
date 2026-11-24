import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'chip_cam',
  name: 'Chip Cam',
  version: '0.1.0',
  description:
      'The camera through emulations of old video hardware and signals: '
      'home computers and consoles, composite video, VHS, bad antennas, '
      'lost sync, video synthesizers, slow-scan TV and digital faults.',
  accent: Color(0xFF33C4B3),
  defaultThemeMode: ThemeMode.dark,
);

void main() => runShellApp(appConfig, (_) => const HomePage());
