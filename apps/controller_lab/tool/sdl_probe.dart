// ignore_for_file: avoid_print
// Lists every controller the way SDL3 sees it, through Controller Lab's own
// bindings (no Flutter), and prints buttons as they're pressed:
//   dart run tool/sdl_probe.dart              (Ctrl+C to stop)
//   dart run tool/sdl_probe.dart --virtual    (adds an SDL virtual pad named
//                                              like a Wii U Pro and presses
//                                              its buttons: checks the
//                                              bindings with no controller)
// Set CONTROLLER_LAB_SDL3 to the library's path if it isn't installed.
import 'dart:ffi';
import 'dart:io';

import 'package:controller_lab/src/model/controls.dart';
import 'package:controller_lab/src/sdl/sdl_backend.dart';
import 'package:controller_lab/src/sdl/sdl_ffi.dart';
import 'package:ffi/ffi.dart';

Future<void> main(List<String> args) async {
  final (sdl, problem) = FfiSdl.load();
  if (sdl == null) {
    stderr.writeln(problem);
    exit(1);
  }
  final backend = SdlBackend(sdl);
  if (!backend.start()) {
    stderr.writeln(backend.problem);
    exit(1);
  }
  print('${backend.title}; hints: ${backend.details.join(' ')}');
  final virtual = args.contains('--virtual');
  final lib = DynamicLibrary.open(
    Platform.environment['CONTROLLER_LAB_SDL3'] ?? 'libSDL3.so.0',
  );
  int? vid;
  if (virtual) vid = _attachVirtual(lib);

  final pressed = <String>{};
  for (var frame = 0; virtual ? frame < 40 : true; frame++) {
    if (virtual && vid != null) _driveVirtual(lib, vid, frame);
    if (backend.poll()) {
      for (final d in backend.devices) {
        final i = d.info;
        print(
          '#${i.id} "${i.name}" ${i.vidPid} guid ${i.guid}\n'
          '   ${i.joystickTypeName}, ${i.summary}, '
          '${i.buttonCount} buttons ${i.axisCount} axes ${i.hatCount} hats\n'
          '   type ${i.gamepadType.sdlName} (real ${i.realGamepadType.sdlName})'
          ' labels ${i.labels}\n'
          '   mapping: ${i.mapping.isEmpty ? '(none)' : i.mapping}',
        );
      }
    }
    for (final d in backend.devices) {
      for (final b in GButton.values) {
        final key = '${d.info.id}:${b.name}';
        if (d.state.button(b) && pressed.add(key)) print('  down $key');
        if (!d.state.button(b) && pressed.remove(key)) print('  up   $key');
      }
      if (virtual && frame == 30) {
        print(
          '  axes ${[for (final a in GAxis.values) '${a.name}=${d.state.axis(a)}'].join(' ')}',
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  backend.dispose();
}

int _attachVirtual(DynamicLibrary lib) {
  final attach = lib
      .lookupFunction<
        Uint32 Function(Pointer<Uint8>),
        int Function(Pointer<Uint8>)
      >('SDL_AttachVirtualJoystick');
  // SDL_VirtualJoystickDesc on 64-bit (136 bytes, SDL_INIT_INTERFACE).
  final desc = calloc<Uint8>(136);
  void u16(int o, int v) => (desc + o).cast<Uint16>().value = v;
  void u32(int o, int v) => (desc + o).cast<Uint32>().value = v;
  u32(0, 136);
  u16(4, 1); // SDL_JOYSTICK_TYPE_GAMEPAD
  u16(8, 0x057e);
  u16(10, 0x0330);
  u16(12, 6); // axes
  u16(14, 15); // buttons
  u32(28, (1 << 15) - 1); // south..dpadRight
  u32(32, (1 << 6) - 1);
  (desc + 40).cast<Pointer<Utf8>>().value = 'Nintendo Wii U Pro Controller'
      .toNativeUtf8();
  final id = attach(desc);
  if (id == 0) stderr.writeln('SDL_AttachVirtualJoystick failed');
  return id;
}

void _driveVirtual(DynamicLibrary lib, int id, int frame) {
  final open = lib
      .lookupFunction<
        Pointer<Void> Function(Uint32),
        Pointer<Void> Function(int)
      >('SDL_GetJoystickFromID');
  final setButton = lib
      .lookupFunction<
        Bool Function(Pointer<Void>, Int32, Bool),
        bool Function(Pointer<Void>, int, bool)
      >('SDL_SetJoystickVirtualButton');
  final setAxis = lib
      .lookupFunction<
        Bool Function(Pointer<Void>, Int32, Int16),
        bool Function(Pointer<Void>, int, int)
      >('SDL_SetJoystickVirtualAxis');
  final js = open(id);
  if (js == nullptr) return;
  if (frame == 10) setButton(js, GButton.east.index, true);
  if (frame == 14) setButton(js, GButton.east.index, false);
  if (frame == 20) {
    setAxis(js, GAxis.leftX.index, 32767);
    setAxis(js, GAxis.leftTrigger.index, 32767);
  }
}
