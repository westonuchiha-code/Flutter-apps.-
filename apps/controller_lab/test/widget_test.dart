import 'package:controller_lab/src/model/controls.dart';
import 'package:controller_lab/src/model/lab.dart';
import 'package:controller_lab/src/sdl/sdl_backend.dart';
import 'package:controller_lab/src/ui/test_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sdl.dart';
import 'helpers.dart';

void main() {
  void size(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('no controllers: says how to connect one', (tester) async {
    size(tester, 390, 844);
    final lab = ControllerLab(SdlBackend(FakeSdl()));
    addTearDown(lab.dispose);
    await pumpApp(tester, lab);
    expect(find.text('No controllers yet'), findsOneWidget);
    expect(find.textContaining('SDL 3.4.20'), findsOneWidget);
  });

  testWidgets('SDL missing: says so and falls back', (tester) async {
    size(tester, 390, 844);
    final lab = ControllerLab(
      SdlBackend(null)..loadProblem = 'SDL3 not found. Put SDL3.dll there.',
      fallback: (r) => SdlBackend(FakeSdl()),
    );
    addTearDown(lab.dispose);
    await pumpApp(tester, lab);
    expect(find.textContaining('SDL3 not found'), findsOneWidget);
  });

  testWidgets('phone: list, test page, hold B to go back', (tester) async {
    size(tester, 390, 844);
    final sdl = FakeSdl()..plug(FakeSdl.wiiUPro());
    final lab = ControllerLab(SdlBackend(sdl));
    addTearDown(lab.dispose);
    await pumpApp(tester, lab);
    expect(find.text('Nintendo Wii U Pro Controller'), findsOneWidget);
    expect(find.textContaining('Wii U Pro Controller ·'), findsOneWidget);
    expect(find.text('0/19'), findsOneWidget);

    await tester.tap(find.text('Nintendo Wii U Pro Controller'));
    await tester.pumpAndSettle();
    expect(find.byType(TestView), findsOneWidget);
    expect(find.text('0 of 19 checked'), findsOneWidget);

    sdl.pads[1]!.down.add(GButton.east); // A
    await tickAndPump(tester, lab);
    expect(find.text('1 of 19 checked'), findsOneWidget);

    sdl.pads[1]!.down
      ..clear()
      ..add(GButton.south); // B (held)
    for (var i = 0; i <= holdToLeave; i++) {
      lab.tick();
    }
    await tester.pumpAndSettle();
    expect(find.byType(TestView), findsNothing);
    expect(find.text('2/19'), findsOneWidget); // A, and the B just held
  });

  testWidgets('a controller moves around the list and opens a pad', (
    tester,
  ) async {
    size(tester, 1600, 900);
    final sdl = FakeSdl()
      ..plug(FakeSdl.wiiUPro())
      ..plug(FakePad(id: 2, name: 'Xbox 360 Controller'));
    final lab = ControllerLab(SdlBackend(sdl));
    addTearDown(lab.dispose);
    await pumpApp(tester, lab);
    final pad = sdl.pads[1]!;
    Future<void> press(GButton b) async {
      pad.down.add(b);
      await tickAndPump(tester, lab);
      pad.down.remove(b);
      await tickAndPump(tester, lab);
    }

    await press(GButton.dpadDown);
    await press(GButton.east); // Nintendo A
    await tester.pump();
    expect(find.byType(TestView), findsOneWidget);
    expect(find.text('Xbox 360 Controller'), findsNWidgets(2));
  });

  testWidgets('desktop: list and test side by side; unplug', (tester) async {
    size(tester, 1600, 900);
    final sdl = FakeSdl()..plug(FakeSdl.wiiUPro());
    final lab = ControllerLab(SdlBackend(sdl));
    addTearDown(lab.dispose);
    await pumpApp(tester, lab);
    expect(find.text('Pick a controller to test it.'), findsOneWidget);
    await tester.tap(find.text('Nintendo Wii U Pro Controller'));
    await tester.pump();
    expect(find.byType(TestView), findsOneWidget);
    expect(find.text('Nintendo Wii U Pro Controller'), findsNWidgets(2));

    await tester.tap(find.text('Info'));
    await tester.pump();
    expect(find.text('057e:0330'), findsOneWidget);
    expect(find.text('Wireless'), findsOneWidget);

    sdl.unplug(1);
    await tickAndPump(tester, lab);
    expect(find.byType(TestView), findsNothing);
    expect(find.text('No controllers yet'), findsOneWidget);
  });
}
