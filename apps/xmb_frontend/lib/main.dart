import 'package:app_shell/app_shell.dart';
import 'package:pokeville/pokeville.dart' show registerPokevilleLicenses;
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'xmb_frontend',
  name: 'XMB Frontend',
  version: '0.1.0',
  description:
      'The Android companion to the XMB Frontend on the PC: a PS3-style '
      'menu for your games, played in RetroArch, PPSSPP, DuckStation and '
      'Dolphin, with saves that cross over to the PC.',
  accent: Color(0xFF3A7FE0),
  defaultThemeMode: ThemeMode.dark,
);

void main() {
  registerPokevilleLicenses(); // its two OFL fonts
  runShellApp(appConfig, (_) => const HomePage());
}
