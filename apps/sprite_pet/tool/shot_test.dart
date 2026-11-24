// Screenshots on a phone and a desktop window (layout check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sprite_pet/main.dart';
import 'package:sprite_pet/src/controller.dart';
import 'package:sprite_pet/src/store.dart';
import 'package:sprite_pet/src/ui/home.dart';
import 'package:sprite_pet/src/weather.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final (name, size, dpr, species) in [
    ('pet_phone', const Size(1080, 2340), 2.625, 'catgirl'),
    ('pet_desktop', const Size(1400, 860), 1.0, 'shiftbot'),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('pet_shot');
      final (services, c) = (await tester.runAsync(() async {
        for (final (fam, files) in [
          (
            'Roboto',
            [
              'Regular',
              'Medium',
              'SemiBold',
            ].map((w) => '/usr/share/fonts/opentype/inter/Inter-$w.otf'),
          ),
          (
            'MaterialIcons',
            [
              '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ],
          ),
        ]) {
          final l = FontLoader(fam);
          for (final f in files) {
            l.addFont(
              Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
            );
          }
          await l.load();
        }
        final s = await ShellServices.create(appConfig, root: dir);
        s.settings.set(themeModeSetting, 'dark');
        final now = DateTime.now();
        const place = Place('Leeds', 'England, United Kingdom', 53.8, -1.55);
        final store = PetStore(dir);
        final d = PetData(place: place)
          ..weather = Weather(place, now, WeatherHour(now, 61, 8, true), [
            WeatherHour(now, 61, 8, true),
          ]);
        d.pet
          ..species = species
          ..name = species == 'catgirl' ? 'Mika' : 'Vector'
          ..food = 0.7
          ..energy = 0.85
          ..fun = 0.6
          ..bedMinutes = 23 * 60 + 59
          ..wakeMinutes = 0
          ..updated = now;
        d.pet.pet(now);
        d.pet.feed(now.subtract(const Duration(hours: 1)));
        await store.save(d);
        final c = PetController(store: store, online: false);
        await c.init();
        return (s, c);
      }))!;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('s'),
          child: ShellApp(
            services: services,
            home: (_) => HomePage(controller: c),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 230));
      }
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('s')),
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      c.dispose();
    });
  }
}
