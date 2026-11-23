import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sa_companion/app/app_state.dart';
import 'package:sa_companion/app/progress_store.dart';
import 'package:sa_companion/data/progress.dart';
import 'package:sa_companion/main.dart';
import 'package:sa_companion/ui/glyphs.dart';

Future<AppState> pumpApp(WidgetTester tester, {String? saved}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(MemoryProgressStore(saved));
  await state.load();
  await tester.pumpWidget(SaCompanionApp(state: state));
  await tester.pump();
  return state;
}

void main() {
  testWidgets('home shows progress, next mission and quick cheats', (
    tester,
  ) async {
    final state = await pumpApp(tester);
    expect(find.text('SAN ANDREAS'), findsWidgets);
    expect(find.text('Big Smoke'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Jetpack'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Jetpack'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('MARK PASSED'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('MARK PASSED'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MISSION PASSED'), findsWidgets);
    expect(state.progress.storyDone, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Ryder'), findsOneWidget); // next mission
  });

  testWidgets('follow-along steps through a cheat', (tester) async {
    await pumpApp(tester);
    await tester.scrollUntilVisible(
      find.text('Jetpack'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Jetpack'));
    await tester.pumpAndSettle();
    expect(find.text('BUTTON 1 OF 16'), findsOneWidget);
    await tester.tap(find.text('PRESSED IT'));
    await tester.pump();
    expect(find.text('BUTTON 2 OF 16'), findsOneWidget);
    await tester.tap(find.text('BACK'));
    await tester.pump();
    expect(find.text('BUTTON 1 OF 16'), findsOneWidget);
    for (var i = 0; i < 16; i++) {
      await tester.tap(find.text('PRESSED IT'));
      await tester.pump();
    }
    expect(find.textContaining('ALL BUTTONS ENTERED'), findsOneWidget);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ALL BUTTONS ENTERED'), findsNothing);
  });

  testWidgets('cheats tab: search, favorite, filter', (tester) async {
    final state = await pumpApp(tester);
    await tester.tap(find.text('CHEATS').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'jetpack');
    await tester.pump();
    expect(find.text('Jetpack'), findsOneWidget);
    expect(find.text('Rhino tank'), findsNothing);
    await tester.tap(find.byTooltip('Favorite Jetpack'));
    await tester.pump();
    expect(state.progress.favorites, {'Jetpack': 1});

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.text('No cheats match that search.'), findsOneWidget);
  });

  testWidgets('missions tab: tick and expand', (tester) async {
    final semantics = tester.ensureSemantics();
    final state = await pumpApp(tester);
    await tester.tap(find.text('MISSIONS').last);
    await tester.pumpAndSettle();
    expect(find.text('0 / 27'), findsOneWidget); // Los Santos chapter
    await tester.tap(find.bySemanticsLabel('Mark Ryder passed'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.progress.storyDone, 1);
    expect(find.text('1 / 27'), findsOneWidget);

    await tester.tap(find.text('Big Smoke'));
    await tester.pump();
    expect(find.textContaining('Pedal the BMX'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    semantics.dispose();
  });

  testWidgets('100% tab counters and guide reference', (tester) async {
    final semantics = tester.ensureSemantics();
    final state = await pumpApp(tester);
    await tester.tap(find.text('100%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('One more').first);
    await tester.pump();
    expect(state.progress.count('tags'), 1);
    expect(find.text('1 / 100'), findsOneWidget);

    await tester.tap(find.text('GUIDE').last);
    await tester.pumpAndSettle();
    expect(find.text('Grove Street and the Johnson house'), findsOneWidget);
    await tester.tap(find.text('REFERENCE'));
    await tester.pumpAndSettle();
    expect(find.text('Run / tap to sprint'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('android back returns to home first', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('GUIDE').last);
    await tester.pumpAndSettle();
    expect(find.text('PLACES & REFERENCE'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('PS2 · UNOFFICIAL'), findsOneWidget);
  });

  testWidgets('shoulder button glyphs stay compact', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: ButtonSequence(['R1', 'X', 'L2'])),
        ),
      ),
    );
    expect(tester.getSize(find.text('R1')).width, lessThan(40));
    final keycap = find
        .ancestor(of: find.text('R1'), matching: find.byType(Container))
        .first;
    expect(tester.getSize(keycap).width, lessThan(60));
  });
}
