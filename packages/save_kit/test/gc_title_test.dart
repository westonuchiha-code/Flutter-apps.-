import 'dart:io';

import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

void main() {
  final root = Platform.environment['POKE_SAMPLES'] ?? '';
  test(
    "a US GameCube save's title is Windows-1252, not Shift-JIS",
    skip: root.isEmpty ? 'POKE_SAMPLES not set' : false,
    () {
      final f = File('$root/saves/dolphin/GC/USA/Card A/01-GXXE-PokemonXD.gci');
      final s = GcCard.saveFrom(f.readAsBytesSync());
      expect(s.titleLines.first, startsWith('POKéMON XD'));
    },
  );
  test('Windows-1252 text', () {
    expect(
      Bytes.western([0x50, 0x4F, 0x4B, 0xE9, 0x4D, 0x99, 0], 0, 10),
      'POKéM™',
    );
  });
}
