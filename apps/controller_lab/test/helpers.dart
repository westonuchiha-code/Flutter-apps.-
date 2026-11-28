import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:controller_lab/main.dart';
import 'package:controller_lab/src/model/lab.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads real fonts where this machine has them (screenshots read better);
/// without them the test font is used.
Future<void> loadFonts() async {
  for (final (fam, files) in [
    (
      'Roboto',
      [
        '/usr/share/fonts/opentype/inter/Inter-Regular.otf',
        '/usr/share/fonts/opentype/inter/Inter-Medium.otf',
        '/usr/share/fonts/opentype/inter/Inter-SemiBold.otf',
      ],
    ),
    (
      'MaterialIcons',
      [
        '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
            '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    ),
  ]) {
    final present = files.where((f) => File(f).existsSync()).toList();
    if (present.isEmpty) continue;
    final l = FontLoader(fam);
    for (final f in present) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }
}

/// Puts the app on screen with [lab] (ticked by hand).
Future<void> pumpApp(
  WidgetTester tester,
  ControllerLab lab, {
  bool fonts = false,
}) async {
  final dir = Directory.systemTemp.createTempSync('controller_lab_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final services = (await tester.runAsync(() async {
    if (fonts) await loadFonts();
    return ShellServices.create(appConfig, root: dir);
  }))!;
  await tester.pumpWidget(
    ShellApp(
      services: services,
      home: (_) => HomePage(lab: lab, autoTick: false),
    ),
  );
  await tester.pump();
}

/// Ticks the lab and lets the screen catch up.
Future<void> tickAndPump(WidgetTester tester, ControllerLab lab) async {
  lab.tick();
  await tester.pump();
}
