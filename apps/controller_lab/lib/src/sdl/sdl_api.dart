import '../model/controls.dart';

/// The few SDL3 calls Controller Lab needs, by joystick instance id, in
/// plain Dart types. [FfiSdl] makes them through dart:ffi; tests use a
/// fake. Every call must come from the isolate (thread) that called
/// [init]: SDL's joystick code is not thread-safe.
abstract interface class SdlApi {
  /// "3.4.20" (the library that was loaded).
  String get version;

  /// Sets [hints] (`SDL_SetHint`), then
  /// `SDL_Init(SDL_INIT_GAMEPAD | SDL_INIT_JOYSTICK)`.
  bool init(Map<String, String> hints);

  /// `SDL_GetError()`.
  String lastError();

  /// Drains SDL's event queue (which also reads the controllers). True
  /// when a controller came, went, was remapped or its battery changed.
  bool pumpEvents();

  /// `SDL_GetJoysticks()`.
  List<int> joystickIds();

  /// Opens the joystick (and the gamepad, when SDL has a mapping).
  bool open(int id);
  void close(int id);

  /// What the opened controller [id] is.
  ControllerInfo info(int id, String source);

  /// Connection, power state and battery percent (-1 unknown).
  (Connection, PowerState, int) power(int id);

  /// Reads every button, axis and hat of [id] into [into].
  void readState(int id, PadState into);

  /// `SDL_RumbleJoystick` (0..65535 strengths).
  bool rumble(int id, int low, int high, int ms);

  /// Closes everything and `SDL_Quit()`.
  void quit();
}
