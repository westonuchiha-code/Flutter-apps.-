import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'ambience_machine',
  name: 'Ambience Machine',
  version: '0.1.0',
  description:
      'Layered, slowly drifting atmospheres from your recordings, Sound Lab '
      'sounds and built-in textures. Crossfade between scenes, sleep timer, '
      'keeps playing with the screen off.',
  accent: Color(0xFF5C8DF2),
);

void main() => runShellApp(appConfig, (_) => const HomePage());
