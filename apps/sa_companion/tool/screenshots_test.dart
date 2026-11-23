// Renders phone-size screenshots of each tab with the real fonts.
// Run: flutter test tool/screenshots_test.dart --dart-define=OUT=/some/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sa_companion/app/app_state.dart';
import 'package:sa_companion/app/progress_store.dart';
import 'package:sa_companion/main.dart';

Future<void> loadFonts() async {
  final families = {
    'BowlbyOne': ['assets/fonts/BowlbyOne-400.ttf'],
    'Barlow': [
      'assets/fonts/Barlow-400.ttf',
      'assets/fonts/Barlow-600.ttf',
      'assets/fonts/Barlow-700.ttf',
    ],
    'BarlowCondensed': [
      'assets/fonts/BarlowCondensed-600.ttf',
      'assets/fonts/BarlowCondensed-700.ttf',
    ],
    'MaterialIcons': [
      '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
          '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final path in e.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: 'screenshots');
  testWidgets('screenshots', (tester) async {
    await tester.runAsync(loadFonts);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final state = AppState(
      MemoryProgressStore(
        '{"m":{"big-smoke":1,"ryder":1,"tagging-up-turf":1,"cleaning-the-hood":1},'
        '"k":{"medic":1,"ex-patriot":1},"c":{"tags":37,"oysters":12},'
        '"f":{"Jetpack":1,"Rhino tank":1}}',
      ),
    );
    await state.load();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: SaCompanionApp(state: state),
      ),
    );
    await tester.pumpAndSettle();
    Directory(out).createSync(recursive: true);

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('shot')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot('1-home');
    for (final (label, name) in [
      ('CHEATS', '2-cheats'),
      ('MISSIONS', '3-missions'),
      ('100%', '4-tracker'),
      ('GUIDE', '5-guide'),
    ]) {
      await tester.tap(find.text(label).last);
      await shot(name);
    }
    await tester.tap(find.text('CHEATS').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Infinite health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PRESSED IT'));
    await tester.tap(find.text('PRESSED IT'));
    await shot('6-follow-along');
  });
}
