import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('a widget that fails to build shows the error', (tester) async {
    await tester.pumpWidget(
      shellErrorWidget(
        FlutterErrorDetails(exception: StateError('the cards went missing')),
      ),
    );
    expect(find.textContaining('the cards went missing'), findsOneWidget);
  });
}
