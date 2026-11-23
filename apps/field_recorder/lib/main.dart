import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/home_page.dart';
import 'src/model.dart';

const appConfig = AppShellConfig(
  id: 'field_recorder',
  name: 'Field Recorder',
  version: '0.1.0',
  description:
      'Record with the microphone, drop markers, trim, tag and save to the '
      'Asset Locker for the other apps.',
  accent: Color(0xFFE0533D),
  settings: [sampleRateSetting, micSourceSetting, defaultTagsSetting],
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final takes = await Takes.open();
  await runShellApp(appConfig, (_) => HomePage(takes: takes));
}
