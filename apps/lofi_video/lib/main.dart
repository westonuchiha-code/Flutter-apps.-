import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'lofi_video',
  name: 'Lo-Fi Video Maker',
  version: '0.1.0',
  description:
      'Short 4:3 videos from Chip Cam clips, pictures, Pixel Forge sprites '
      'and title cards, each through an old-hardware video effect, with '
      'music from the Asset Locker. Exports MP4 with sound.',
  accent: Color(0xFFE0457B),
  defaultThemeMode: ThemeMode.dark,
);

void main() => runShellApp(appConfig, (_) => const HomePage());
