// The drawings at a desktop, the Retroid Pocket Classic (1240×1080 at
// density 2.75, about 450×390 dp) and a phone, saved to build/shots/ for a
// look check. Also fails on any overflow or paint error.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:controller_lab/main.dart';
import 'package:controller_lab/src/model/controls.dart';
import 'package:controller_lab/src/model/lab.dart';
import 'package:controller_lab/src/sdl/sdl_backend.dart';
import 'package:controller_lab/src/ui/test_view.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_sdl.dart';
import 'helpers.dart';

const out = 'build/shots';

Future<void> shot(
  WidgetTester tester,
  String name,
  Size physical,
  double dpr,
  FakeSdl sdl, {
  String open = 'Nintendo Wii U Pro Controller',
  String? tab,
  String body = 'white',
  void Function(FakeSdl sdl, ControllerLab lab)? press,
}) async {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final lab = ControllerLab(SdlBackend(sdl));
  addTearDown(lab.dispose);
  final dir = Directory.systemTemp.createTempSync('controller_lab_shot');
  addTearDown(() => dir.deleteSync(recursive: true));
  final services = (await tester.runAsync(() async {
    await loadFonts();
    return ShellServices.create(appConfig, root: dir);
  }))!;
  if (body != 'white') services.settings.set(wiiUBodySetting, body);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('shot'),
      child: ShellApp(
        services: services,
        home: (_) => HomePage(lab: lab, autoTick: false),
      ),
    ),
  );
  await tester.pump();
  if (open.isNotEmpty) {
    await tester.tap(find.text(open).first);
    await tester.pumpAndSettle();
    expect(find.byType(TestView), findsOneWidget);
    if (tab != null) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }
  }
  press?.call(sdl, lab);
  lab.tick();
  await tester.pumpAndSettle();
  final b = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
  await tester.runAsync(() async {
    final img = await b.toImage(pixelRatio: dpr);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(out).createSync(recursive: true);
    File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  await tester.pump(const Duration(seconds: 1)); // settings save timer
}

/// Some of the pad tested, A and ZR held, the left stick pushed.
void midTest(FakeSdl sdl, ControllerLab lab) {
  final p = sdl.pads[1]!;
  for (final b in [
    GButton.south,
    GButton.dpadUp,
    GButton.start,
    GButton.guide,
  ]) {
    p.down.add(b);
    lab.tick();
    p.down.remove(b);
  }
  for (final (x, y) in [(0, -32768), (32767, 0), (0, 32767), (-32768, 0)]) {
    p.axis[GAxis.rightX] = x;
    p.axis[GAxis.rightY] = y;
    lab.tick();
  }
  p.axis[GAxis.rightX] = 900;
  p.axis[GAxis.rightY] = -700;
  lab.tick();
  p.down.addAll([GButton.east, GButton.leftStick]);
  p.axis[GAxis.rightTrigger] = 32767;
  p.axis[GAxis.leftX] = 20000;
  p.axis[GAxis.leftY] = -21000;
}

FakeSdl wiiU() => FakeSdl()..plug(FakeSdl.wiiUPro());

void main() {
  testWidgets('desktop 1920x1080', (tester) async {
    await shot(
      tester,
      'wiiu_desktop',
      const Size(1920, 1080),
      1,
      wiiU()..plug(
        FakePad(id: 2, name: 'Xbox 360 Controller', type: GamepadType.xbox360),
      ),
      press: midTest,
    );
  });

  testWidgets('desktop, black Wii U Pro', (tester) async {
    await shot(
      tester,
      'wiiu_desktop_black',
      const Size(1920, 1080),
      1,
      wiiU(),
      body: 'black',
      press: midTest,
    );
  });

  testWidgets('Retroid 450x390 dp', (tester) async {
    await shot(
      tester,
      'wiiu_retroid',
      const Size(1240, 1080),
      2.75,
      wiiU(),
      press: midTest,
    );
  });

  testWidgets('Retroid list', (tester) async {
    await shot(
      tester,
      'list_retroid',
      const Size(1240, 1080),
      2.75,
      wiiU()
        ..plug(
          FakePad(
            id: 2,
            name: 'Sony DualSense Wireless Controller',
            type: GamepadType.ps5,
          ),
        )
        ..plug(
          FakePad(
            id: 3,
            name: 'USB Gamepad',
            mapped: false,
            buttons: 10,
            axes: 2,
            hats: 1,
          ),
        ),
      open: '',
    );
  });

  testWidgets('phone 390x844', (tester) async {
    await shot(
      tester,
      'wiiu_phone',
      const Size(1170, 2532),
      3,
      wiiU(),
      press: midTest,
    );
  });

  testWidgets('phone: info', (tester) async {
    await shot(
      tester,
      'wiiu_phone_info',
      const Size(1170, 2532),
      3,
      wiiU(),
      tab: 'Info',
    );
  });

  testWidgets('desktop: DualSense on the generic pad drawing', (tester) async {
    await shot(
      tester,
      'dualsense_standard_desktop',
      const Size(1920, 1080),
      1,
      FakeSdl()..plug(
        FakePad(
          id: 1,
          name: 'DualSense Wireless Controller',
          type: GamepadType.ps5,
        ),
      ),
      open: 'DualSense Wireless Controller',
      press: (sdl, lab) {
        sdl.pads[1]!.down.addAll([GButton.south, GButton.leftShoulder]);
        sdl.pads[1]!.axis[GAxis.leftTrigger] = 16000;
      },
    );
  });

  testWidgets('Retroid: an unmapped pad, raw', (tester) async {
    await shot(
      tester,
      'raw_retroid',
      const Size(1240, 1080),
      2.75,
      FakeSdl()..plug(
        FakePad(
          id: 1,
          name: 'USB Gamepad',
          mapped: false,
          buttons: 12,
          axes: 4,
          hats: 1,
        ),
      ),
      open: 'USB Gamepad',
      press: (sdl, lab) {
        final p = sdl.pads[1]!;
        p.rawButtons[2] = true;
        p.rawAxes[0] = -32768;
        p.rawHats[0] = 1;
      },
    );
  });
}
