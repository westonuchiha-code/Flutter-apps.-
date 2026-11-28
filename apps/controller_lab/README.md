# Controller Lab

Pick up any of your real controllers and see exactly how the software sees it.
Controller Lab lists every connected controller, shows what SDL (and so the PC
XMB in Godot 4.7, RetroArch's sdl2 driver, PCSX2 and RPCS3) calls it, and tests
every button on a drawing of the real controller.

Platforms: **Windows** and **Linux** read controllers through **SDL3**;
**Android** (phone, Retroid) reads Android's own input devices.

## Part 1 (this version): detect + live test

- **The list**: every controller, live as they're plugged in or paired: name,
  wired / wireless, battery, what SDL calls it (`SDL_GAMEPAD_TYPE_…`), whether
  SDL has a gamepad mapping, vendor:product id, and how much of it you've tested.
- **The test** (tap a controller; side by side on a wide screen):
  - a drawing of the controller where each button lights while pressed and gets
    a tick once tested, sticks move with yours, triggers show how far they're
    pulled;
  - **every button checked** list and progress;
  - stick readouts: position, the range reached each way, the *gate* (the
    outline of how far it goes in each direction, drawn on the stick), and
    **Measure rest**: let go, and it measures the drift at rest and suggests a
    deadzone (orange ring);
  - **Rumble** (if the pad has a motor), **Reset**;
  - **Raw**: the joystick as numbered buttons, axes and hats (what SDL gets
    before any mapping);
  - **Info**: name, GUID, path, serial, types, connection, battery, and SDL's
    mapping string (copy button).
- Drawings: the **Wii U Pro Controller** (white or black body, in Settings);
  any other pad SDL has a mapping for gets a generic modern pad with its own
  button names (✕○□△, A/B/X/Y, L1/LB/L…); anything else (odd Bluetooth pads,
  adapters) gets the raw drawing, so it can still be tested.
- Moving around with a controller: D-pad and A on the list (A is wherever A is
  printed: on Nintendo pads that's the right button). On the test page the
  buttons are the test, so **hold B for a second** (○ on PlayStation pads) or
  press Esc to go back.

## Wii U Pro Controller on the PC

Follow [docs/controllers/WII_U_PRO_PC_TEST.md](../../docs/controllers/WII_U_PRO_PC_TEST.md):
pair "Nintendo RVL-CNT-01-UC" with the red SYNC button, then open Controller
Lab. It turns on SDL's Wii driver (`SDL_JOYSTICK_HIDAPI_WII=1`) for itself, so
it should appear as **Nintendo Wii U Pro Controller** (057e:0330) with the
drawing. The other programs only see it that way once the
`SDL_JOYSTICK_HIDAPI_WII=1` user environment variable is set (step 1 of that
page). If Controller Lab shows it but they don't, that variable is the reason;
if Controller Lab doesn't show it either, say whether its lights keep running.

Through SDL's Wii driver the buttons are by position: Nintendo's A (right) is
SDL's "east", B (bottom) "south", X "north", Y "west". ZL/ZR are digital but
SDL reports them as triggers at 0 or 100%. POWER and SYNC can't be read by any
program, so they're drawn but not tested.

## How it works

- **SDL3 through dart:ffi** (`lib/src/sdl/sdl_ffi.dart`): small hand-written
  bindings for just the calls needed. Before `SDL_Init(GAMEPAD | JOYSTICK)` it
  sets these hints (Settings → SDL can turn the first three off; they take
  effect at the next start):
  - `SDL_JOYSTICK_HIDAPI_WII=1`: SDL's own Wii U Pro / Wii Remote driver;
  - `SDL_JOYSTICK_HIDAPI_PS3=1`: read a DualShock 3 directly (on Windows it
    needs a HID driver such as DsHidMini);
  - `SDL_JOYSTICK_ENHANCED_REPORTS=1`: full Bluetooth reports from
    DualSense / DualShock 4 / Switch pads;
  - `SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1`: the Flutter window isn't an SDL
    window, so without this SDL would drop input as "in the background";
  - player LEDs on for Wii and PS5 pads.

  A user environment variable of the same name overrides these (SDL's rule).
  The calls run on the UI isolate, from a per-frame ticker (SDL's joystick
  code must stay on one thread, and Dart isolates aren't pinned to threads,
  so no background isolate). The state is read directly each frame; SDL's
  event queue only tells it when controllers come and go.
- **Where SDL3 comes from**: Windows: `SDL3.dll` next to `controller_lab.exe`
  (CI downloads the official SDL 3.4.20 release zip, checks its SHA-256 and
  adds it with `SDL3-LICENSE.txt`; zlib licence). Linux: the bundle's `lib/`
  (CI copies Ubuntu's `libsdl3-0` there when the runner has it), else the
  system's `libSDL3.so.0` (`sudo apt install libsdl3-0`, Ubuntu 25.04+ /
  Debian 13). `CONTROLLER_LAB_SDL3=/path/to/lib` overrides both.
- **No SDL3**: the app says so at the top of the list and falls back to Flutter
  key events (buttons only, no sticks or names).
- **Android**: `MainActivity.kt` lists InputDevices (name, vendor/product,
  axes, battery), and forwards controller key presses and stick/trigger motion
  over `controller_lab/input` + `controller_lab/events`. Android doesn't say
  whether a pad is wired or Bluetooth.
- **Model** (`lib/src/model`): pure Dart, driven by tests through a fake SDL
  (`test/fake_sdl.dart`). A drawing is a `ControllerLayout` (its parts and a
  painter); new controllers are a new layout added to `layouts` in
  `lib/src/layouts/layout.dart`.
- `dart run tool/sdl_probe.dart` prints every controller as SDL sees it from a
  terminal (`--virtual` checks the bindings with an SDL virtual pad).

## Linux gaps

- SDL3 needs `libsdl3-0` (not in Ubuntu 24.04); without it the app falls back
  to key events.
- Reading HID devices directly (the Wii driver) needs udev permission for
  `/dev/hidraw*`; without it SDL uses the kernel's own driver, which names the
  Wii U Pro "Nintendo Wii Remote Pro Controller" (still drawn as a Wii U Pro).

## Roadmap

1. **Detect + live test** (this version), Wii U Pro drawn.
2. More drawn controllers: DualShock 3, DualSense, Xbox 360, N64, Saturn
   standard + 3D pad, Genesis 3/6-button, PS1/PS2 (incl. odd pads), GameCube,
   Wii Remote + Nunchuk / Classic, Dreamcast, arcade sticks.
3. Mapping with each console's own button names; retro pads set up for their
   own console, modern pads for every console.
4. Per-program profiles (RetroArch, PCSX2, RPCS3, DuckStation, Dolphin, the
   PC XMB), and the PC XMB picking the held controller's profile.
