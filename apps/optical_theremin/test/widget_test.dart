import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:optical_theremin/main.dart';
import 'package:optical_theremin/src/app/theremin_controller.dart';
import 'package:optical_theremin/src/input/camera_backend.dart';

import 'fakes.dart';

void main() {
  testWidgets('phone layout with touch pad', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final synth = FakeSynth();
    final controller = ThereminController(
      cameraBackend: FakeCameraBackend(),
      synth: synth,
    );
    await tester.pumpWidget(OpticalThereminApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Optical Theremin'), findsOneWidget);
    expect(find.text('Touch pad'), findsOneWidget);
    expect(find.textContaining('No camera'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(controller.playing, isTrue);
    expect(find.text('Stop'), findsOneWidget);

    // Settings open in a bottom sheet on narrow screens.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Sound chip'), findsOneWidget);

    await tester.tapAt(Offset.zero); // close sheet
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.playing, isFalse);
  });

  testWidgets('desktop layout with camera shows zones and settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeCameraBackend(
      cameras: [const CameraOption(id: 'cam', label: 'Webcam')],
    );
    final controller = ThereminController(
      cameraBackend: backend,
      synth: FakeSynth(),
    );
    await tester.pumpWidget(OpticalThereminApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // exposure lock delay
    backend.emit(splitImage(30, 200, width: 16, height: 12));
    await tester.pump();

    expect(find.text('PITCH'), findsOneWidget);
    expect(find.text('VOLUME'), findsOneWidget);
    expect(find.text('Game Boy'), findsWidgets); // chip picker
    expect(find.text('Sound chip'), findsOneWidget); // side panel visible
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.textContaining('tap Calibrate'), findsOneWidget);
  });

  testWidgets('record, then open recordings and see the take', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = ThereminController(
      cameraBackend: FakeCameraBackend(),
      synth: FakeSynth(),
    );
    await tester.pumpWidget(OpticalThereminApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record'));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('0:01'), findsOneWidget); // recording timer
    await tester.tap(find.text('0:01'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Saved'), findsOneWidget);

    await tester.tap(find.byTooltip('Recordings'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.textContaining('Game Boy Pulse'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Export WAV'), findsOneWidget);
    expect(find.text('Change sound'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
  });
}
