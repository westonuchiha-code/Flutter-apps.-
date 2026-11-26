// Pokéville's storage, ported from the PC XMB Frontend's PokeBoxStore.gd.
//
// The folder holds every stored Pokémon as the file PKHeX wrote
// (mons/<stamp>.pkN) plus box.json, the order:
//
//   {"version": 1, "boxes": [{"name": "Box 1", "slots": [{} or
//    {"file": "mons/x.pk3", "mon": {...}}, x30]}]}
//
// "mon" is the PC helper's summary, so the boxes draw without PKHeX. These
// functions work on the decoded JSON itself (plain maps and lists), so every
// field the PC writes, known here or not, goes back out untouched. Numbers
// come back as floats (52.0): read them as `num`.
import 'dart:convert';

import 'package:path/path.dart' as p;

/// The decoded box.json.
typedef BoxData = Map<String, dynamic>;

/// One slot: `{}` when empty, else `{"file": ..., "mon": {...}}`.
typedef SlotData = Map<String, dynamic>;

/// Pure functions on box.json's data, as on the PC.
abstract final class PokeBoxStore {
  static const index = 'box.json';
  static const mons = 'mons';
  static const slots = 30;
  static const cols = 6;
  static const rows = 5;
  static const startBoxes = 8;

  static BoxData blank() => {
    'version': 1,
    'boxes': [for (var i = 0; i < startBoxes; i++) _box(i)],
  };

  static Map<String, dynamic> _box(int i) => {
    'name': 'Box ${i + 1}',
    'slots': [for (var s = 0; s < slots; s++) <String, dynamic>{}],
  };

  static List<dynamic> boxes(BoxData data) =>
      (data['boxes'] as List?) ?? const [];

  static int boxCount(BoxData data) => boxes(data).length;

  static List<dynamic> _slots(BoxData data, int box) =>
      (boxes(data)[box] as Map)['slots'] as List;

  /// Always one empty box at the end, so there's room to put things.
  static void keepSpareBox(BoxData data) {
    final b = boxes(data);
    if (b.isEmpty || countInBox(data, b.length - 1) > 0) {
      b.add(_box(b.length));
    }
  }

  static int countInBox(BoxData data, int box) {
    if (box < 0 || box >= boxCount(data)) return 0;
    var n = 0;
    for (final s in _slots(data, box)) {
      if (s is Map && s.containsKey('file')) n++;
    }
    return n;
  }

  static int total(BoxData data) {
    var n = 0;
    for (var b = 0; b < boxCount(data); b++) {
      n += countInBox(data, b);
    }
    return n;
  }

  static String boxName(BoxData data, int box) {
    if (box < 0 || box >= boxCount(data)) return '';
    final name = (boxes(data)[box] as Map)['name'];
    return name is String ? name : 'Box ${box + 1}';
  }

  /// The slot's map (`{}` for an empty one or one out of range).
  static SlotData slot(BoxData data, int box, int i) {
    if (box < 0 || box >= boxCount(data) || i < 0 || i >= slots) return {};
    final list = _slots(data, box);
    if (i >= list.length) return {};
    final s = list[i];
    return s is Map<String, dynamic> ? s : {};
  }

  static bool isEmpty(BoxData data, int box, int i) =>
      !slot(data, box, i).containsKey('file');

  static bool place(
    BoxData data,
    int box,
    int i,
    String file,
    Map<String, dynamic> mon,
  ) {
    if (box < 0 || box >= boxCount(data) || !isEmpty(data, box, i)) {
      return false;
    }
    _slots(data, box)[i] = <String, dynamic>{'file': file, 'mon': mon};
    keepSpareBox(data);
    return true;
  }

  static SlotData clear(BoxData data, int box, int i) {
    final was = slot(data, box, i);
    if (was.containsKey('file')) _slots(data, box)[i] = <String, dynamic>{};
    return was;
  }

  /// Moves a Pokémon; onto another one it's a swap.
  static bool move(BoxData data, int fromBox, int fromI, int toBox, int toI) {
    if (isEmpty(data, fromBox, fromI)) return false;
    if (toBox < 0 || toBox >= boxCount(data) || toI < 0 || toI >= slots) {
      return false;
    }
    final a = slot(data, fromBox, fromI);
    final b = _slots(data, toBox)[toI];
    _slots(data, toBox)[toI] = a;
    _slots(data, fromBox)[fromI] = b; // a swap when the target held one
    keepSpareBox(data);
    return true;
  }

  /// The first empty slot from [fromBox] on (wrapping), or null when full.
  static (int, int)? firstEmpty(BoxData data, [int fromBox = 0]) {
    final n = boxCount(data);
    for (var k = 0; k < n; k++) {
      final b = (fromBox + k) % n;
      for (var i = 0; i < slots; i++) {
        if (isEmpty(data, b, i)) return (b, i);
      }
    }
    return null;
  }

  /// [path] relative to the folder, always with `/` (as box.json keeps it).
  static String relative(String dir, String path) {
    final rel = p.isWithin(dir, path) ? p.relative(path, from: dir) : path;
    return rel.replaceAll(r'\', '/');
  }

  /// A box.json `file` as a path on this machine.
  static String absolute(String dir, String file) {
    if (p.isAbsolute(file)) return file;
    return p.joinAll([dir, ...file.split('/')]);
  }

  /// Species in the Box (eggs left out): the Box Dex.
  static Set<int> species(BoxData data) {
    final out = <int>{};
    for (var b = 0; b < boxCount(data); b++) {
      for (var i = 0; i < slots; i++) {
        final s = slot(data, b, i);
        if (!s.containsKey('file')) continue;
        final m = Mon.of(s);
        if (m != null && !m.egg && m.species > 0) out.add(m.species);
      }
    }
    return out;
  }

  // ---- box.json text --------------------------------------------------------

  /// Reads box.json's text: null when it isn't a Box. Short boxes are padded
  /// to 30 slots and a spare box is added, as the PC does on load.
  static BoxData? parse(String text) {
    final Object? parsed;
    try {
      parsed = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (parsed is! Map<String, dynamic>) return null;
    final b = parsed['boxes'];
    if (b is! List || b.isEmpty) return null;
    for (final box in b) {
      if (box is! Map<String, dynamic>) return null;
      final s = box['slots'];
      if (s is! List) return null;
      for (var i = 0; i < s.length; i++) {
        if (s[i] is! Map) s[i] = <String, dynamic>{};
      }
      while (s.length < slots) {
        s.add(<String, dynamic>{});
      }
    }
    keepSpareBox(parsed);
    return parsed;
  }

  /// box.json's text the way the PC writes it (Godot's JSON.stringify with
  /// a tab indent; floats stay floats, keys keep their order).
  static String encode(BoxData data) =>
      const JsonEncoder.withIndent('\t').convert(data);

  /// A copy that can be changed without touching [data].
  static BoxData copy(BoxData data) => _copy(data) as BoxData;

  static Object? _copy(Object? v) => switch (v) {
    Map() => <String, dynamic>{
      for (final e in v.entries) e.key as String: _copy(e.value),
    },
    List() => <dynamic>[for (final x in v) _copy(x)],
    _ => v,
  };
}

/// A read-only view of a slot's `mon` summary.
class Mon {
  const Mon(this.raw);

  /// The summary of a filled slot, else null.
  static Mon? of(SlotData slot) {
    if (!slot.containsKey('file')) return null;
    final m = slot['mon'];
    return Mon(m is Map<String, dynamic> ? m : const {});
  }

  final Map<String, dynamic> raw;

  int _int(String k) {
    final v = raw[k];
    return v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);
  }

  String _str(String k) {
    final v = raw[k];
    return v == null ? '' : '$v';
  }

  bool _bool(String k) {
    final v = raw[k];
    return v == true || (v is num && v != 0);
  }

  List<String> _list(String k) {
    final v = raw[k];
    return v is List ? [for (final x in v) '$x'] : const [];
  }

  int get species => _int('species');
  int get form => _int('form');
  String get name => _str('name');
  String get nickname => _str('nickname');
  int get level => _int('level');
  bool get shiny => _bool('shiny');

  /// 0 male, 1 female, 2 none.
  int get gender => raw.containsKey('gender') ? _int('gender').clamp(0, 2) : 2;
  bool get egg => _bool('egg');
  String get item => _str('item');
  String get ot => _str('ot');
  int get generation => _int('generation');
  String get format => _str('format');
  String get origin => _str('origin');
  List<String> get moves => _list('moves');
  List<String> get types => _list('types');

  /// The six base stats (HP Atk Def SpA SpD Spe), or empty when not known.
  List<int> get stats {
    final v = raw['stats'];
    return v is List ? [for (final x in v) x is num ? x.toInt() : 0] : const [];
  }

  String get nature => _str('nature');
  String get ability => _str('ability');
  String get ball => _str('ball');
  String get fromSave => _str('from_save');

  /// What the Box shows: "Egg", the nickname, or the species name.
  String get shownName {
    if (egg) return 'Egg';
    final n = nickname;
    if (n.isNotEmpty) return n;
    final s = name;
    return s.isEmpty ? '?' : s;
  }
}
