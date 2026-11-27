import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:save_screens/src/folders.dart';

/// A made-up .gci: [game] + maker "01", one block.
Uint8List gci(String game) {
  final b = Uint8List(64 + 8192)..fillRange(64, 64 + 8192, 1);
  b.setAll(0, '${game}01'.codeUnits.take(6));
  b.setAll(8, 'S'.codeUnits);
  Bytes.putBe16(b, 0x38, 1);
  return b;
}

void main() {
  test("Android reads the XMB's Dolphin folder (GC/USA/Card A) as is", () {
    final root = Directory.systemTemp.createTempSync('dolphin');
    addTearDown(() => root.deleteSync(recursive: true));
    final at = Places(
      home: root.path,
      documents: p.join(root.path, 'Documents'),
      storage: root.path,
    );
    // where Cross-Save puts the PC's GameCube saves on the phone
    final card = Directory(
      p.join(
        root.path,
        'XMB Frontend',
        'Saves',
        'Dolphin',
        'GC',
        'USA',
        'Card A',
      ),
    )..createSync(recursive: true);
    File(p.join(card.path, '01-GXXE-PokemonXD.gci'))
        .writeAsBytesSync(gci('GXXE'));
    final dirs = CardFolders.toRead('android', at, const []);
    // no Dolphin entry needed: XMB Frontend/Saves is read with sub-folders
    final read = MemoryCards.readCards(dirs);
    final gc = read.where((c) => c.system == 'GC').toList();
    expect(gc, hasLength(1));
    expect(gc.single.saves.single.file, '01-GXXE-PokemonXD.gci');
  });
}
