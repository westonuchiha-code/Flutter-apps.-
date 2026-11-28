import 'controls.dart';

/// A pad's kind from its USB ids and name, for backends that don't say
/// (Android, key events). SDL tells its own.
GamepadType guessGamepadType(int vendor, int product, String name) {
  final n = name.toLowerCase();
  switch (vendor) {
    case 0x054c: // Sony
      return switch (product) {
        0x0268 => GamepadType.ps3,
        0x05c4 || 0x09cc || 0x0ba0 => GamepadType.ps4,
        0x0ce6 || 0x0df2 => GamepadType.ps5,
        _ => n.contains('dualsense') ? GamepadType.ps5 : GamepadType.ps4,
      };
    case 0x045e: // Microsoft
      return n.contains('360') || product == 0x028e || product == 0x0719
          ? GamepadType.xbox360
          : GamepadType.xboxOne;
    case 0x057e: // Nintendo
      if (product == 0x2009) return GamepadType.switchPro;
      if (product == 0x0337) return GamepadType.gameCube;
      return GamepadType.standard;
  }
  if (n.contains('xbox 360')) return GamepadType.xbox360;
  if (n.contains('xbox')) return GamepadType.xboxOne;
  if (n.contains('dualsense')) return GamepadType.ps5;
  return GamepadType.standard;
}

/// The Wii U Pro Controller: SDL's Wii driver names it "Nintendo Wii U Pro
/// Controller" (057e:0330, the same ids as a newer Wii Remote, so the name
/// settles it); Windows' own Bluetooth name is "Nintendo RVL-CNT-01-UC";
/// Linux's hid-wiimote calls it "Nintendo Wii Remote Pro Controller".
bool isWiiUPro(ControllerInfo i) {
  final n = i.name.toLowerCase();
  return n.contains('wii u pro') ||
      n.contains('rvl-cnt-01-uc') ||
      n.contains('wii remote pro controller');
}
