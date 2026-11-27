/// Game controllers on Windows (XInput, plus the joystick API for
/// PlayStation / generic pads), Linux (/dev/input/js*, best-effort) and
/// Android (controller key events), as positional [PadButton]s with d-pad
/// repeat: [GamepadInput] reads them, [PadInput] shares one reader across
/// an app, [PadListener] is the widget to use, [PadKeys] reads key events.
library;

export 'src/buttons.dart';
export 'src/gamepad.dart';
export 'src/linux.dart' show LinuxPadSource, applyJsEvents, linuxPadPressed;
export 'src/pad_input.dart';
export 'src/pad_keys.dart';
export 'src/pad_listener.dart';
export 'src/windows.dart' show WindowsPadSource, fromStick;
