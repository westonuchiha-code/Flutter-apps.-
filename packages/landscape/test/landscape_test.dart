import 'package:flutter_test/flutter_test.dart';
import 'package:landscape/landscape.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a seed always makes the same land, within its height range', () {
    const s = LandSettings(seed: 9);
    final a = generate(s, n: 33), b = generate(s, n: 33);
    expect(a.h, b.h);
    expect(
      a.h.every((v) => v >= -1 && v <= LandSettings.maxHeight + 5),
      isTrue,
    );
  });

  test('night is dark and noon is bright', () {
    expect(skyFor(const LandSettings(time: 12)).sunHeight, greaterThan(0.5));
    expect(skyFor(const LandSettings(time: 23)).night, greaterThan(0.5));
  });

  test('a world builds as an engine3d scene', () async {
    const s = LandSettings(seed: 3, clouds: 0);
    final w = await VistaWorld.build(s, generate(s, n: 33), detail: 17);
    expect(w.scene.root.find('land'), isNotNull);
    expect(w.groundAt(0, 0), isA<double>());
  });
}
