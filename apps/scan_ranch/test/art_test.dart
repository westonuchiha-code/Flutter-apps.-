import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_ranch/render/monster_art.dart';

void main() {
  test('palettes and colourising a material map', () {
    expect(monsterPalettes, hasLength(12));
    // One body pixel (tone 2), one outline pixel touching body, one eye.
    final map = Uint8List.fromList([
      ArtMat.body.index,
      100,
      0,
      255,
      ArtMat.outline.index,
      ArtMat.body.index,
      0,
      255,
      ArtMat.eye.index,
      0,
      0,
      255,
      0,
      0,
      0,
      0,
    ]);
    final pal = monsterPalettes.first;
    final out = MonsterArt.instance.colourise(map, pal);
    final body = pal.ramps[ArtMat.body]![2].toARGB32();
    expect(out.sublist(0, 3), [
      (body >> 16) & 255,
      (body >> 8) & 255,
      body & 255,
    ]);
    final eye = pal.eye.toARGB32();
    expect(out.sublist(8, 11), [
      (eye >> 16) & 255,
      (eye >> 8) & 255,
      eye & 255,
    ]);
    expect(out[15], 0); // transparent stays transparent
  });

  testWidgets('assets load and the CRT image is built', (tester) async {
    await tester.runAsync(() async {
      await MonsterArt.instance.load();
      final img = await MonsterArt.instance.imageAsync(0, 3);
      expect(img.width, 64 * MonsterArt.crtScale + MonsterArt.pad * 2);
    });
  });
}
