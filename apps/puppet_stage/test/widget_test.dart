import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Action;
import 'package:puppet_stage/main.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/export.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/moves.dart';
import 'package:puppet_stage/src/places.dart';
import 'package:puppet_stage/src/sets.dart';
import 'package:puppet_stage/src/ui/home.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a short movie exports to a video file', (tester) async {
    await tester.runAsync(() async {
      final movie = Movie(
        actors: [
          Actor(
            kind: Kind.girl,
            name: 'Cy',
            actions: [
              Action(ActionType.move, move: 'jump', seconds: 0.4),
              Action(ActionType.walk, x: 0.5, z: 0.5),
            ],
          ),
        ],
      );
      final place = BuiltPlace(await buildSet(movie.set));
      final scene = place.scene;
      final c = buildCharacter(Kind.girl, defaultLooks[Kind.girl]!);
      final clips = clipsFor(c);
      scene.root.add(c.root);
      final dir = Directory.systemTemp.createTempSync('puppet_export');
      var last = 0.0;
      final file = await exportMovie(
        movie: movie,
        places: [place],
        pose: (t) => applyState(c, clips, stateAt(movie.actors.first, t)),
        fallbackCamera: Camera(),
        basePath: '${dir.path}${Platform.pathSeparator}m',
        width: 160,
        height: 120,
        fps: 10,
        progress: (p) => last = p,
        cancelled: () => false,
        preferMp4: false,
      );
      expect(file, isNotNull);
      expect(file!.lengthSync(), greaterThan(1000));
      expect(last, 1.0);
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  testWidgets('home page shows the stage and adds actions', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('puppet_ui');
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    await tester.pumpWidget(
      ShellApp(services: services, home: (_) => const HomePage()),
    );
    for (var i = 0; i < 40 && find.byType(Viewport3D).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(Viewport3D), findsOneWidget);
    expect(find.text('Ann'), findsWidgets);
    // Add a dog: its own moves show up (with its call).
    await tester.tap(find.text('Add'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Dog'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Dog 3'), findsWidgets);
    await tester.tap(find.text('Actions'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Bark'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Jump'),
      150,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await tester.pump();
    await tester.tap(find.text('Jump'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Pose'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.textContaining('Start posing'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.scrollUntilVisible(
      find.text('Add frame'),
      150,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await tester.pump();
    await tester.tap(find.text('Add frame'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
