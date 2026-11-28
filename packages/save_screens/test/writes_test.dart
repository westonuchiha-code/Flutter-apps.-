import 'package:flutter_test/flutter_test.dart';
import 'package:save_screens/src/controller.dart';

void main() {
  test('jobs that make files in an emulator folder ask about the emulator', () {
    // CardStore refuses these without the answer ("can't tell"), so the
    // controller must ask first on Android.
    for (final verb in ['new_card', 'duplicate', 'copy', 'delete', 'format']) {
      expect(SaveManagerController.writes, contains(verb), reason: verb);
    }
  });
}
