import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/ui/home.dart';

const appConfig = AppShellConfig(
  id: 'sample_pad',
  name: 'Sample Pad',
  version: '0.1.0',
  description:
      'Sample pads, a step sequencer and a loop station. Sounds come from '
      'the Asset Locker or the mic; kits and mixes save back to it.',
  accent: Color(0xFFB65CF2),
  settings: [loopTimingSetting, masterSetting],
);

void main() => runShellApp(appConfig, (_) => const HomePage());
