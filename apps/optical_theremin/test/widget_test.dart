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

    final tone = FakeTone();
    final controller = ThereminController(
      cameraBackend: FakeCameraBackend(),
      tone: tone,
    );
    await tester.pumpWidget(OpticalThereminApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Optical Theremin'), findsOneWidget);
    expect(find.text('Touch pad'), findsOneWidget);
    expect(find.textContaining('No camera'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(tone.started, isTrue);
    expect(find.text('Stop'), findsOneWidget);

    // Settings open in a bottom sheet on narrow screens.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Two zones'), findsOneWidget);

    await tester.tapAt(Offset.zero); // close sheet
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tone.started, isFalse);
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
      tone: FakeTone(),
    );
    await tester.pumpWidget(OpticalThereminApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // exposure lock delay
    backend.emit(splitImage(30, 200, width: 16, height: 12));
    await tester.pump();

    expect(find.text('PITCH'), findsOneWidget);
    expect(find.text('VOLUME'), findsOneWidget);
    expect(find.text('Two zones'), findsOneWidget); // side panel visible
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.textContaining('tap Calibrate'), findsOneWidget);
  });
}
