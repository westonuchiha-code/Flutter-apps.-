/// The shapes cards come in on disk: whole files, four N64 paks in one,
/// byte-expanded or gzipped Saturn carts, packed Neo Geo cards (ported from
/// the PC's CardImage.gd). take() gives a card's own bytes out of its
/// file; put() hands back the file's bytes with the card changed.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'bytes.dart';
import 'formats/dreamcast.dart';
import 'formats/gamecube.dart';
import 'formats/n64.dart';
import 'formats/neogeo.dart';
import 'formats/ps1.dart';
import 'formats/ps2.dart';
import 'formats/saturn.dart';
import 'model.dart';

typedef CardPart = ({String system, int offset, int span, bool gzip});

abstract final class CardImage {
  static const exts = {
    'PS1': ['mcd', 'mcr', 'srm', 'mc'],
    'PS2': ['ps2', 'mc2'],
    'DC': ['bin', 'vmu', 'srm'],
    'GC': ['raw', 'gcp'],
    'N64': ['mpk', 'pak', 'cpk', 'srm'],
    'SATURN': ['bkr', 'bcr', 'srm', 'sav'],
    'NEO GEO': ['mcr', 'bin', 'srm', 'mem', 'sav'],
  };

  /// mupen64plus-next's .srm: four paks after 0x800 bytes of other saves.
  static const n64Combined = 296960, n64PaksAt = 0x800;
  static const ps2Max = 70 << 20, unpackedMax = 1 << 20;

  static bool _is(String system, String ext) => exts[system]!.contains(ext);

  static Uint8List? _gunzip(Uint8List b) {
    try {
      final out = const GZipDecoder().decodeBytes(b);
      return out.length <= unpackedMax ? Uint8List.fromList(out) : null;
    } catch (_) {
      return null;
    }
  }

  /// Cheap to rule out: size and extension before any reading is trusted.
  static List<CardPart> find(Uint8List file, String ext) {
    final size = file.length;
    if (size < 2) return [];
    CardPart whole(String system) =>
        (system: system, offset: 0, span: size, gzip: false);
    if (_is('PS1', ext) && Ps1Card.isCard(file)) return [whole('PS1')];
    if (_is('PS2', ext) && Ps2Card.isCard(file)) return [whole('PS2')];
    if (_is('DC', ext) && VmuWriter.isCard(file)) return [whole('DC')];
    if (_is('GC', ext) && GcWriter.isCard(file)) return [whole('GC')];
    if (_is('SATURN', ext) && SaturnWriter.plain(file).isNotEmpty) {
      return [whole('SATURN')];
    }
    if (_is('NEO GEO', ext) && NeoWriter.plain(file).isNotEmpty) {
      return [whole('NEO GEO')];
    }
    if (_is('SATURN', ext) && file[0] == 0x1F && file[1] == 0x8B) {
      final inner = _gunzip(file);
      if (inner != null && SaturnWriter.plain(inner).isNotEmpty) {
        return [(system: 'SATURN', offset: 0, span: size, gzip: true)];
      }
      return [];
    }
    if (_is('N64', ext)) {
      var start = -1, count = 0;
      if (size == n64Combined) {
        start = n64PaksAt;
        count = 4;
      } else if (size % PakWriter.size == 0 && size <= PakWriter.size * 4) {
        start = 0;
        count = size ~/ PakWriter.size;
      }
      return [
        for (var i = 0; i < count; i++)
          if (PakWriter.idFine(
            Uint8List.sublistView(
              file,
              start + i * PakWriter.size,
              start + (i + 1) * PakWriter.size,
            ),
          ))
            (
              system: 'N64',
              offset: start + i * PakWriter.size,
              span: PakWriter.size,
              gzip: false,
            ),
      ];
    }
    return [];
  }

  /// Could a file of this size be a card at all? Saves reading every
  /// ROM-sized file in a saves folder.
  static bool worthReading(int size, String ext) {
    if (_is('PS2', ext)) return size >= 0x150 && size <= ps2Max;
    if (_is('GC', ext)) {
      return size >= 4 * GcWriter.mbit && size <= 128 * GcWriter.mbit;
    }
    if (ext == 'bcr') return size >= 2 && size <= 2 * SaturnWriter.cart;
    if (NeoWriter.goodSize(size) || size == NeoWriter.mister) return true;
    return const [
      2048,
      4096,
      32768,
      65536,
      98304,
      131072,
      n64Combined,
      524288,
      1048576,
    ].contains(size);
  }

  /// PCSX2 makes slot 2's card as 8 MB of FF until a game formats it.
  static bool isBlankPs2(Uint8List file, String ext) {
    final whole =
        file.length == Ps2Writer.total * 2 * 528 ||
        file.length == Ps2Writer.total * 2 * 512;
    return whole && _is('PS2', ext) && file.every((b) => b == 0xFF);
  }

  static Uint8List take(Uint8List file, MemoryCard card) {
    if (!Bytes.has(file, card.offset, card.span)) return Uint8List(0);
    var part = Uint8List.sublistView(
      file,
      card.offset,
      card.offset + card.span,
    );
    if (card.gzip) part = _gunzip(part) ?? Uint8List(0);
    return switch (card.system) {
      'SATURN' => SaturnWriter.plain(part),
      'NEO GEO' => NeoWriter.plain(part),
      _ => Uint8List.fromList(part),
    };
  }

  /// Empty = it doesn't fit back into that file.
  static Uint8List put(Uint8List file, MemoryCard card, Uint8List bytes) {
    if (!Bytes.has(file, card.offset, card.span) || bytes.isEmpty) {
      return Uint8List(0);
    }
    var part = Uint8List.fromList(
      file.sublist(card.offset, card.offset + card.span),
    );
    if (card.gzip) part = _gunzip(part) ?? Uint8List(0);
    switch (card.system) {
      case 'SATURN':
        part = SaturnWriter.packed(part, bytes);
      case 'NEO GEO':
        part = NeoWriter.packed(part, bytes);
      default:
        if (part.length != bytes.length) return Uint8List(0);
        part = bytes;
    }
    if (part.isEmpty) return part;
    if (card.gzip) return Uint8List.fromList(const GZipEncoder().encode(part));
    return Uint8List.fromList([
      ...file.sublist(0, card.offset),
      ...part,
      ...file.sublist(card.offset + card.span),
    ]);
  }
}
