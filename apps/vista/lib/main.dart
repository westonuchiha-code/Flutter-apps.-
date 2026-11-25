import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'vista',
  name: 'Vista',
  version: '0.1.0',
  description:
      'Make fractal landscapes (mountains, water, skies, fog, sun and moon) '
      'with simple controls, explore them in real time, and render '
      'ray-traced stills and flyover videos.',
  accent: Color(0xFF6FB4E8),
  defaultThemeMode: ThemeMode.dark,
);

void main() => runShellApp(appConfig, (_) => const HomePage());
