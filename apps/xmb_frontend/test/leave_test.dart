import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pokeville/pokeville.dart';
import 'package:xmb_frontend/src/ui/home.dart' show leaveRoute;

void main() {
  testWidgets('Back in Pokéville returns to the menu', (tester) async {
    final temp = Directory.systemTemp.createTempSync('leave');
    addTearDown(() => temp.deleteSync(recursive: true));
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: key, home: const Text('the menu')),
    );
    late final MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      // no box.json yet: the "No Pokéville here yet" page and its Back
      builder: (_) => PokevilleHome(
        temp.path,
        temp.path,
        onLeave: () => leaveRoute(key.currentState!, route),
      ),
    );
    final opened = key.currentState!.push(route);
    await tester.pumpAndSettle();
    expect(find.text('the menu'), findsNothing);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('the menu'), findsOneWidget);
    await opened;
  });
}
