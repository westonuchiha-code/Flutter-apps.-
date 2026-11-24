import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sprite_pet/main.dart';
import 'package:sprite_pet/src/controller.dart';
import 'package:sprite_pet/src/mood.dart';
import 'package:sprite_pet/src/store.dart';
import 'package:sprite_pet/src/ui/home.dart';
import 'package:sprite_pet/src/widget_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the pet is saved and treats come from new Asset Locker items',
    () async {
      final dir = Directory.systemTemp.createTempSync('pet_store');
      addTearDown(() => dir.deleteSync(recursive: true));
      var items = <String, (String, String)>{'a': ('Sprite', 'Old')};
      final c = PetController(
        store: PetStore(dir),
        lockerItems: () async => items,
        online: false,
      );
      await c.init();
      expect(c.frames.length, 4);
      await c.setSpecies('cat');
      await c.rename('Mochi');
      items = {...items, 'b': ('Video', 'Night drive')};
      await c.refresh(full: true);
      expect(c.data.pet.log.first, contains('Night drive'));
      c.dispose();
      final again = await PetStore(dir).load();
      expect(again.pet.name, 'Mochi');
      expect(again.species.name, 'Cat');
    },
  );

  test('widget plan: one entry per change over the next day', () {
    final d = PetData();
    final plan = widgetPlan(d, DateTime(2026, 11, 25, 20));
    expect(plan.first.from, DateTime(2026, 11, 25, 20));
    expect(plan.map((s) => s.mood), contains(Mood.asleep));
    for (var i = 1; i < plan.length; i++) {
      expect(
        plan[i].key != plan[i - 1].key || plan[i].text != plan[i - 1].text,
        isTrue,
      );
    }
  });

  testWidgets('home page shows the pet and its needs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('pet_ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final c = PetController(store: PetStore(dir), online: false);
    await tester.runAsync(c.init);
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(controller: c),
      ),
    );
    await tester.pump();
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Feed'), findsOneWidget);
    await tester.tap(find.text('Feed'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(c.data.pet.log, isNotEmpty);
    expect(tester.takeException(), isNull);
    c.dispose();
  });
}
