import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'puppet_stage',
  name: 'Puppet Stage',
  version: '0.1.0',
  description:
      'Little 3D movies without skill: pick a set, add people, tap moves '
      'and places to walk to, cut between camera shots, pose by hand for '
      'stop motion, and make a video.',
  accent: Color(0xFFE8A030),
  defaultThemeMode: ThemeMode.dark,
);

void main() => runShellApp(appConfig, (_) => const HomePage());
