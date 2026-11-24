import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'sprite_pet',
  name: 'Sprite Pet',
  version: '0.1.0',
  description:
      'A pixel pet that lives through your day: sleeps at night, gets '
      'hungry and bored, reacts to the weather, your battery and the things '
      'you make in the other apps. Home-screen widget on Android, a mini '
      'window on PC.',
  accent: Color(0xFF59C9A5),
  defaultThemeMode: ThemeMode.dark,
);

void main() => runShellApp(appConfig, (_) => const HomePage());
