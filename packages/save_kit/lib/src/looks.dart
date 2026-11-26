/// How each card looks in this app (its colour, finish and sticker) and
/// where it sits in the list. Only this app reads it: the card file is
/// never touched. A card that went into a console slot keeps its look
/// there (it goes by MemoryCard.home). Ported from the PC's CardLooks.gd.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'model.dart';
import 'store.dart';

abstract final class CardLooks {
  static const stickerDir = 'XMB Card Stickers';
  static const stickerExt = ['png', 'jpg', 'jpeg', 'webp', 'bmp'];
  static const stickerMax = 160;

  /// Like the real cards: solid plastic, see-through "crystal" plastic and
  /// the patterned ones. (name, value): value = "rrggbb" or
  /// "rrggbb/finish"; '' = the console's own.
  static const palette = [
    ("Console's own", ''),
    ('Midnight Black', '1c1d24'),
    ('Satin Silver', 'b8bdc8'),
    ('Ice White', 'eef1f6'),
    ('Crimson Red', 'b4202f'),
    ('Ocean Blue', '1f56c2'),
    ('Emerald', '1f9a55'),
    ('Sunshine Yellow', 'f2c81f'),
    ('Tangerine', 'ee7a1e'),
    ('Lavender', '8c6fd8'),
    ('Bubblegum Pink', 'ec6fae'),
    ('Crystal Clear', 'e9eef4/clear'),
    ('Smoke Black', '2a2c33/clear'),
    ('Crystal Blue', '2a6fd6/clear'),
    ('Crystal Red', 'd0202e/clear'),
    ('Crystal Green', '21a35a/clear'),
    ('Crystal Yellow', 'e8d21c/clear'),
    ('Crystal Orange', 'f07a1c/clear'),
    ('Crystal Pink', 'f06aa8/clear'),
    ('Island Aqua', '21b8c6/clear'),
    ('Carbon Fibre', '1c1d22/carbon'),
    ('Leopard', 'd9a441/leopard'),
    ('Camo', '5d7046/camo'),
    ('Zebra', 'eeeeee/zebra'),
    ('Strawberry', 'f6f0ea/strawberry'),
  ];
  static const finishes = [
    '',
    'clear',
    'carbon',
    'leopard',
    'camo',
    'zebra',
    'strawberry',
  ];
  static const shotsPerGame = 6;
  static const unreadable =
      "The card looks file can't be read, so it wasn't changed";

  static String lookKey(MemoryCard c) =>
      (c.home.isNotEmpty ? c.home : c.key()).toLowerCase();

  static int? _hex(String s) => RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)
      ? 0xFF000000 | int.parse(s, radix: 16)
      : null;

  /// Colour, sticker and place in the list onto the cards just read.
  static void apply(List<MemoryCard> cards, String file) {
    final data = read(file);
    final rank = <String, int>{
      for (var i = 0; i < data.order.length; i++) data.order[i]: i + 1,
    };
    for (final c in cards) {
      final k = lookKey(c);
      c.orderRank = rank[k] ?? 0;
      final it = data.looks[k];
      if (it == null) continue;
      final value = it.color;
      final parts = value.split('/');
      c.color = _hex(parts[0]) ?? 0;
      final finish = parts.length > 1 ? parts[1] : '';
      c.finish = finishes.contains(finish) && c.color != 0 ? finish : '';
      c.sticker = it.sticker;
      c.stickerImage = stickerImage(c.sticker, c);
    }
  }

  /// The order (card keys, top first) and looks; ok = false: there's a
  /// file that couldn't be read (writing would lose what's in it).
  static ({
    List<String> order,
    Map<String, ({String color, String sticker})> looks,
    bool ok,
  })
  read(String file) {
    final looks = <String, ({String color, String sticker})>{};
    final order = <String>[];
    final f = File(file);
    if (!f.existsSync()) return (order: order, looks: looks, ok: true);
    Object? got;
    try {
      got = jsonDecode(f.readAsStringSync());
    } catch (_) {}
    if (got is! Map) return (order: order, looks: looks, ok: false);
    if (got['order'] is List) {
      order.addAll((got['order'] as List).map((e) => '$e'));
    }
    if (got['looks'] is Map) {
      (got['looks'] as Map).forEach((k, v) {
        if (v is Map) {
          looks['$k'] = (
            color: '${v['color'] ?? ''}',
            sticker: '${v['sticker'] ?? ''}',
          );
        }
      });
    }
    return (order: order, looks: looks, ok: true);
  }

  /// [color] = a palette value ('' = the console's own); [sticker] = a key
  /// or '' (none).
  static String setLook(
    MemoryCard card,
    String color,
    String sticker,
    String file,
    CardSafety safety,
  ) {
    final data = read(file);
    if (!data.ok) return unreadable;
    if (color.isEmpty && sticker.isEmpty) {
      data.looks.remove(lookKey(card));
    } else {
      data.looks[lookKey(card)] = (color: color, sticker: sticker);
    }
    return _write(file, data.order, data.looks, safety);
  }

  /// The whole list, top first, as it is now on screen.
  static String setOrder(
    List<MemoryCard> cards,
    String file,
    CardSafety safety,
  ) {
    final data = read(file);
    if (!data.ok) return unreadable;
    final keys = <String>[];
    for (final c in cards) {
      if (!keys.contains(lookKey(c))) keys.add(lookKey(c));
    }
    return _write(file, keys, data.looks, safety);
  }

  static String _write(
    String file,
    List<String> order,
    Map<String, ({String color, String sticker})> looks,
    CardSafety safety,
  ) {
    final no = safety.refusal(file);
    if (no.isNotEmpty) return no;
    try {
      Directory(p.dirname(file)).createSync(recursive: true);
      final temp = File('$file.new')
        ..writeAsStringSync(
          const JsonEncoder.withIndent('\t').convert({
            'order': order,
            'looks': {
              for (final e in looks.entries)
                e.key: {'color': e.value.color, 'sticker': e.value.sticker},
            },
          }),
        );
      final f = File(file);
      if (f.existsSync()) f.deleteSync();
      temp.renameSync(file);
      return '';
    } catch (_) {
      return "Couldn't save that";
    }
  }

  /// What a card could wear: (key, label), "No sticker" first. [games]:
  /// the library's games that saves on this card belong to (art = a
  /// picture file or ''; shots = screenshots, newest first). Your own
  /// pictures come from [folder].
  static List<({String key, String label})> stickerChoices(
    MemoryCard card,
    List<({String id, String title, String art, List<String> shots})> games,
    String folder,
  ) {
    final out = <({String key, String label})>[(key: '', label: 'No sticker')];
    final seen = <String>{};
    for (final s in card.saves) {
      if (s.gameId.isEmpty || !seen.add('game:${s.gameId}')) continue;
      for (final g in games.where((g) => g.id == s.gameId)) {
        if (g.art.isNotEmpty && File(g.art).existsSync()) {
          out.add((key: 'file:${g.art}', label: 'Game art: ${g.title}'));
        }
        for (var k = 0; k < math.min(g.shots.length, shotsPerGame); k++) {
          out.add((
            key: 'file:${g.shots[k]}',
            label: 'Screenshot ${k + 1}: ${g.title}',
          ));
        }
      }
    }
    for (final s in card.saves) {
      final who = s.displayName();
      if (s.frames.isEmpty || !seen.add('icon:$who')) continue;
      out.add((key: 'icon:${s.id}', label: 'Save icon: $who'));
    }
    final d = Directory(folder);
    if (d.existsSync()) {
      final files = [
        for (final f in d.listSync().whereType<File>())
          if (stickerExt.contains(
            p.extension(f.path).replaceFirst('.', '').toLowerCase(),
          ))
            f.path,
      ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      for (final f in files) {
        out.add((
          key: 'file:$f',
          label: 'Your picture: ${p.basenameWithoutExtension(f)}',
        ));
      }
    }
    return out;
  }

  /// null = no sticker, or its picture isn't there any more.
  static Pixels? stickerImage(String key, MemoryCard card) {
    if (key.startsWith('icon:')) {
      for (final s in card.saves) {
        if (s.id == key.substring(5) && s.frames.isNotEmpty) {
          return s.frames.first;
        }
      }
      return null;
    }
    if (!key.startsWith('file:')) return null;
    final f = File(key.substring(5));
    if (!f.existsSync()) return null;
    var im = img.decodeImage(f.readAsBytesSync());
    if (im == null) return null;
    final big = math.max(im.width, im.height);
    if (big > stickerMax) {
      final k = stickerMax / big;
      im = img.copyResize(
        im,
        width: math.max(1, (im.width * k).round()),
        height: math.max(1, (im.height * k).round()),
        interpolation: img.Interpolation.cubic,
      );
    }
    final rgba = im
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba);
    return Pixels(im.width, im.height, Uint8List.fromList(rgba));
  }

  static int paletteIndex(int color, [String finish = '']) {
    if (color == 0) return 0;
    for (var i = 0; i < palette.length; i++) {
      final v = palette[i].$2;
      if (v.isEmpty) continue;
      final parts = v.split('/');
      if (_hex(parts[0]) == color &&
          finish == (parts.length > 1 ? parts[1] : '')) {
        return i;
      }
    }
    return 0;
  }

  /// Puts a palette value on a card (shown at once; saving is setLook's).
  static void wear(MemoryCard card, String value) {
    final parts = value.split('/');
    card.color = parts[0].isNotEmpty ? _hex(parts[0]) ?? 0 : 0;
    card.finish = parts.length > 1 ? parts[1] : '';
  }
}
