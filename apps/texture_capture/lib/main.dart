import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'texture_capture',
  name: 'Texture Capture',
  version: '0.1.0',
  description:
      'Turns a photo of a surface into a game texture: flattens the '
      'perspective, evens the lighting, makes it tile, and converts it to '
      'the sizes and formats of old consoles (PS1, N64, PS2, GameCube, '
      'Dreamcast).',
  accent: Color(0xFFC98B4A),
  defaultThemeMode: ThemeMode.dark,
);

void main() => runShellApp(appConfig, (_) => const HomePage());
