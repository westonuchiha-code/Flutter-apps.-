import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/model/lab.dart';
import 'src/platform.dart';
import 'src/sdl/sdl_backend.dart';
import 'src/ui/home.dart';

const wiiUBodySetting = ChoiceSetting(
  key: 'wiiu.body',
  title: 'Wii U Pro colour',
  section: 'Drawings',
  defaultValue: 'white',
  choices: {'white': 'White', 'black': 'Black'},
);

const _sdl = 'SDL (Windows / Linux)';
const _restart = 'Takes effect next time the app starts.';

const sdlWiiSetting = BoolSetting(
  key: 'sdl.wii',
  title: "SDL's Wii driver (Wii U Pro, Wii Remote)",
  subtitle: 'SDL_JOYSTICK_HIDAPI_WII. $_restart',
  section: _sdl,
  defaultValue: true,
);
const sdlPs3Setting = BoolSetting(
  key: 'sdl.ps3',
  title: "SDL's PS3 driver (DualShock 3)",
  subtitle: 'SDL_JOYSTICK_HIDAPI_PS3. $_restart',
  section: _sdl,
  defaultValue: true,
);
const sdlEnhancedSetting = BoolSetting(
  key: 'sdl.enhanced',
  title: 'Enhanced PlayStation / Switch reports',
  subtitle:
      'SDL_JOYSTICK_ENHANCED_REPORTS: gyro, touchpad, rumble over '
      'Bluetooth. $_restart',
  section: _sdl,
  defaultValue: true,
);

const appConfig = AppShellConfig(
  id: 'controller_lab',
  name: 'Controller Lab',
  version: '0.1.0',
  description:
      'Detects your controllers, shows how SDL (and so RetroArch, PCSX2, '
      'RPCS3 and the PC XMB) sees them, and tests every button on a '
      'drawing of the real controller.',
  accent: Color(0xFF29B6F6),
  settings: [wiiUBodySetting, sdlWiiSetting, sdlPs3Setting, sdlEnhancedSetting],
);

void main() => runShellApp(appConfig, (_) => const HomePage());

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.lab, this.autoTick = true});

  /// The controllers to show (default: this platform's; tests pass a fake).
  final ControllerLab? lab;
  final bool autoTick;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ControllerLab? _lab;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_lab != null) return;
    final settings = Shell.of(context).settings;
    _lab =
        widget.lab ??
        createLab(
          hints: SdlHints(
            wii: settings.get(sdlWiiSetting),
            ps3: settings.get(sdlPs3Setting),
            enhancedReports: settings.get(sdlEnhancedSetting),
          ),
        );
  }

  @override
  void dispose() {
    if (widget.lab == null) _lab?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Shell.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => ControllerLabHome(
        lab: _lab!,
        autoTick: widget.autoTick,
        bodyColour: settings.get(wiiUBodySetting),
        title: appConfig.name,
        actions: shellActions(context),
      ),
    );
  }
}
