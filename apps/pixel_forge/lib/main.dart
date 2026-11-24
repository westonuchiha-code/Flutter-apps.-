import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'pixel_forge',
  name: 'Pixel Forge',
  version: '0.1.0',
  description:
      'Pixel art editor for touch and desktop: layers, palettes, selections, '
      'mirror drawing. Sprites and palettes save to the Asset Locker.',
  accent: Color(0xFFE5484D),
);

void main() => runShellApp(appConfig, (_) => const HomePage());
