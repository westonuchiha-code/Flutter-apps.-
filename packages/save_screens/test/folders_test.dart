import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:save_screens/src/folders.dart';

void main() {
  test("Android reads the XMB Frontend's own save folders", () {
    final root = Directory.systemTemp.createTempSync('folders');
    addTearDown(() => root.deleteSync(recursive: true));
    final at = Places(
      home: root.path,
      documents: p.join(root.path, 'Documents'),
      storage: root.path,
    );
    expect(
      CardFolders.known('android', at),
      contains(p.join(root.path, 'XMB Frontend', 'Saves')),
    );
    // a PS1 card where the XMB's DuckStation keeps it
    final cards = Directory(
      p.join(root.path, 'XMB Frontend', 'Saves', 'DuckStation', 'memcards'),
    )..createSync(recursive: true);
    File(p.join(cards.path, 'Crash Bandicoot_1.mcd'))
        .writeAsBytesSync(Ps1Writer.blank());
    final dirs = CardFolders.toRead('android', at, const []);
    final read = MemoryCards.readCards(dirs);
    expect(read.map((c) => c.name), contains('Crash Bandicoot'));
  });
}
