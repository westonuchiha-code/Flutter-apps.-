import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'photo_quilt',
  name: 'Photo Tile Quilt',
  version: '0.1.0',
  description:
      'Turns a photo into a patchwork quilt: classic blocks (plain, '
      'half-square triangles, four-patch, stripes) in a limited palette, '
      'with seams and stitches.',
  accent: Color(0xFFD9824B),
  defaultThemeMode: ThemeMode.dark,
);

void main() => runShellApp(appConfig, (_) => const HomePage());
