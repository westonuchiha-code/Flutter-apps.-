import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

/// A PARAM.SFO with these text keys.
Uint8List sfo(Map<String, String> keys) {
  final index = BytesBuilder(),
      keyTable = BytesBuilder(),
      data = BytesBuilder();
  for (final e in keys.entries) {
    final v = [...utf8.encode(e.value), 0];
    final entry = Uint8List(16);
    Bytes.put16(entry, 0, keyTable.length);
    Bytes.put16(entry, 2, 0x0204);
    Bytes.put32(entry, 4, v.length);
    Bytes.put32(entry, 8, v.length);
    Bytes.put32(entry, 12, data.length);
    index.add(entry);
    keyTable.add([...utf8.encode(e.key), 0]);
    data.add(v);
  }
  final head = Uint8List(20)..setAll(0, [0, 0x50, 0x53, 0x46, 1, 1, 0, 0]);
  final idx = index.takeBytes(), kt = keyTable.takeBytes();
  Bytes.put32(head, 8, 20 + idx.length);
  Bytes.put32(head, 12, 20 + idx.length + kt.length);
  Bytes.put32(head, 16, keys.length);
  return Uint8List.fromList([...head, ...idx, ...kt, ...data.takeBytes()]);
}

void main() {
  test('zip packing', () {
    expect(Ps3Writer.crc32(ascii.encode('123456789')), 0xCBF43926);
    final files = {
      'PARAM.SFO': sfo({'TITLE': 'X'}),
      'GAME.SAV': [1, 2, 3],
    };
    final packed = Ps3Writer.pack('BCES00052_SAVE_1', files);
    expect(packed.ok, isTrue);
    final back = Ps3Writer.unpack(packed.data);
    expect(back.error, '');
    expect(back.name, 'BCES00052_SAVE_1');
    expect(back.files['GAME.SAV'], [1, 2, 3]);
    expect(Ps3Writer.check(packed.data), '');
    expect(Ps3Writer.idIn(packed.data), 'BCES00052_SAVE_1');
    expect(
      Ps3Writer.pack('BCES00052_SAVE_1', files).data,
      packed.data,
      reason: 'packs the same',
    );
    expect(Ps3Writer.pack('../evil', files).ok, isFalse);
    expect(
      Ps3Writer.pack('X', {
        'GAME.SAV': [1],
      }).ok,
      isFalse,
      reason: 'no PARAM.SFO',
    );
    expect(
      Ps3Writer.pack('X', {
        ...files,
        'a/b': [1],
      }).ok,
      isFalse,
    );
    expect(Ps3Writer.check(Uint8List.fromList([1, 2, 3])), isNot(''));
    // The same zip from another tool, compressed: refused here (Import opens those).
    final a = Archive();
    a.addFile(ArchiveFile.bytes('S/PARAM.SFO', sfo({'TITLE': 'X'})));
    final deflated = Uint8List.fromList(ZipEncoder().encode(a));
    expect(Ps3Writer.unpack(deflated).error, contains('compressed'));
  });

  test('an RPCS3 savedata folder reads', () {
    final root = Directory.systemTemp.createTempSync('ps3');
    final dir = p.join(root.path, 'dev_hdd0', 'home', '00000001', 'savedata');
    final save = Directory(p.join(dir, 'BCES00052_SAVE_1'))
      ..createSync(recursive: true);
    File(p.join(save.path, 'PARAM.SFO')).writeAsBytesSync(
      sfo({
        'TITLE': 'Ratchet & Clank® Future™',
        'SUB_TITLE': 'Planet Kortog',
        'DETAIL': '',
        'SAVEDATA_DIRECTORY': 'BCES00052_SAVE_1',
      }),
    );
    final icon = img.Image(width: 320, height: 176)
      ..clear(img.ColorRgb8(50, 150, 230));
    File(p.join(save.path, 'ICON0.PNG')).writeAsBytesSync(img.encodePng(icon));
    File(p.join(save.path, 'GAME.SAV')).writeAsBytesSync(List.filled(3000, 7));
    Directory(p.join(dir, 'not a save')).createSync();
    expect(Ps3Card.isSavedata(dir), isTrue);
    expect(Ps3Card.cardName(dir), 'PS3 User 1');
    final card = Ps3Card.parseFolder(dir, MemoryCard());
    expect(card.saves, hasLength(1));
    final s = card.saves.single;
    expect(s.ps3Title, 'Ratchet & Clank Future');
    expect(s.titleLines, ['Planet Kortog']);
    expect(s.serial, 'BCES00052');
    expect(s.region, 'Europe');
    expect(Ps3Card.serialText(s.serial), 'BCES-00052');
    expect(s.files, hasLength(3));
    expect(s.wide!.w, 320);
    expect(s.frames.single.w, Ps3Card.tile);
    expect(card.freeText(), startsWith('1 save'));
    final usb = p.join(root.path, 'dev_usb000', 'PS3', 'SAVEDATA');
    Directory(usb).createSync(recursive: true);
    expect(
      Ps3Card.isSavedata(usb),
      isTrue,
      reason: 'an empty stick still counts',
    );
    expect(Ps3Card.cardName(usb), 'PS3 USB');
    root.deleteSync(recursive: true);
  });
}
