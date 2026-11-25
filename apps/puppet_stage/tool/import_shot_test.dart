// Screenshots on a phone and a desktop window (look check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:engine3d/engine3d.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Action;
import 'package:puppet_stage/main.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/sets.dart';
import 'package:puppet_stage/src/ui/home.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final (name, size, dpr) in [
    ('import_desktop', const Size(1400, 860), 1.0),
  ]) {
    testWidgets(name, (tester) async {
      late Movie land;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('puppet_shot');
      final services = (await tester.runAsync(() async {
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
        await s.locker.connect();
        const mdir = String.fromEnvironment('MODELS');
        Future<Actor> add(String f, String n, double x, String move) async {
          final info = await s.locker.save(
            type: AssetType.model,
            name: n,
            bytes: File('$mdir/$f').readAsBytesSync(),
            extension: 'glb',
          );
          return Actor(
            kind: Kind.man,
            name: n,
            model: ModelRef(info.id, 'glb', n),
            x: x,
            ownWalk: false,
            actions: [Action(ActionType.move, move: move, seconds: 3)],
          );
        }

        land = Movie(
          set: StageSet.room,
          actors: [
            await add('Xbot.glb', 'Xbot', -1.6, 'wave'),
            await add('Soldier.glb', 'Soldier', -0.4, 'cheer'),
            await add('RobotExpressive.glb', 'Robot', 0.9, 'own:Dance'),
            Actor(
              kind: Kind.girl,
              name: 'Cy',
              x: 2,
              actions: [Action(ActionType.move, move: 'clap', seconds: 3)],
            ),
          ],
          shots: [Shot(0, 0.2, 1.4, 5.2, 0, -0.08)],
        );
        return s;
      }))!;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('s'),
          child: ShellApp(
            services: services,
            home: (_) => HomePage(movie: land),
          ),
        ),
      );
      for (
        var i = 0;
        i < 60 && find.byType(Viewport3D).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 33));
      }
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('s')),
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
