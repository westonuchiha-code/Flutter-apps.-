// Copied from packages/save_screens/test: the app's own smoke test needs them.
// Made-up save files and cards for the save manager's tests (the same
// shapes as save_kit's own tests and the PC's CardWriteTests.gd etc.).
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';

/// A made-up .mcs: its directory frame, then [blocks] blocks of [fill].
Uint8List mcs(String name, int blocks, int fill) {
  final b = Uint8List(128 + blocks * 8192)
    ..fillRange(128, 128 + blocks * 8192, fill);
  b[0] = 0x51;
  Bytes.put32(b, 4, blocks * 8192);
  Bytes.put16(b, 8, 0xFFFF);
  for (var i = 0; i < name.length; i++) {
    b[10 + i] = name.codeUnitAt(i);
  }
  return b;
}

/// A made-up .dci: every body byte = [blocks].
Uint8List dci(String name, int blocks, int type) {
  final b = Uint8List(32 + blocks * 512)
    ..fillRange(32, 32 + blocks * 512, blocks);
  b[0] = type;
  b.setAll(4, name.padRight(12).codeUnits);
  b[0x18] = blocks & 0xFF;
  b[0x19] = blocks >> 8;
  return b;
}

/// A .psu holding files of [sizes], each filled with a counting pattern.
Uint8List psu(String saveName, List<int> sizes) {
  const when = 1795355442;
  final b = BytesBuilder()
    ..add(Ps2Writer.newEntry(0x8427, sizes.length + 2, saveName, when))
    ..add(Ps2Writer.newEntry(0x8427, 0, '.', when))
    ..add(Ps2Writer.newEntry(0x8427, 0, '..', when));
  for (var i = 0; i < sizes.length; i++) {
    final size = sizes[i];
    b.add(Ps2Writer.newEntry(0x8497, size, 'file$i', when));
    final data = Uint8List((size / 1024).ceil() * 1024);
    for (var k = 0; k < size; k++) {
      data[k] = (k + i) & 0xFF;
    }
    b.add(data);
  }
  return b.takeBytes();
}

/// Writes [bytes] to [path], making its folder.
void put(String path, List<int> bytes) {
  Directory(p.dirname(path)).createSync(recursive: true);
  File(path).writeAsBytesSync(bytes, flush: true);
}

/// Two made-up cards of [system], four saves each (no files behind them).
List<MemoryCard> fakeCards([String system = 'PS2']) {
  final out = <MemoryCard>[];
  for (var i = 0; i < 2; i++) {
    final c = MemoryCard()
      ..system = system
      ..name = 'Card $i'
      ..path = 'card$i'
      ..total = 8000
      ..free = 4000;
    for (var k = 0; k < 4; k++) {
      c.saves.add(
        CardSave()
          ..system = system
          ..id = 'SAVE$i$k'
          ..kb = 10
          ..blocks = 1
          ..card = c,
      );
    }
    out.add(c);
  }
  return out;
}

/// Every save of [cards].
List<CardSave> savesOf(List<MemoryCard> cards) => [
  for (final c in cards) ...c.saves,
];
