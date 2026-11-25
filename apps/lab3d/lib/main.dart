import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/home.dart';

const appConfig = AppShellConfig(
  id: 'lab3d',
  name: '3D Lab',
  version: '0.1.0',
  description:
      'Test ground for the shared 3D engine: walk a courtyard in the PS1 '
      'style (or a clean look), load glTF/OBJ models, put your pictures on '
      'things, and see how fast your device draws it.',
  accent: Color(0xFF7C8CFF),
  defaultThemeMode: ThemeMode.dark,
);

void main() => runShellApp(appConfig, (_) => const HomePage());
