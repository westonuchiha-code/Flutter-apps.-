/// Save manager data: pictures, colours, 3D icons, one save, one card, and
/// what a writer hands back (ported from the PC's CardSave.gd,
/// MemoryCard.gd, CardEdit.gd, CardSystems.gd). Pure data.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A picture: [w]×[h] RGBA, 8 bits each, not premultiplied.
class Pixels {
  Pixels(this.w, this.h, [Uint8List? rgba])
    : rgba = rgba ?? Uint8List(w * h * 4);
  final int w, h;
  final Uint8List rgba;

  void set(int x, int y, int r, int g, int b, [int a = 255]) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = (y * w + x) * 4;
    rgba[i] = r;
    rgba[i + 1] = g;
    rgba[i + 2] = b;
    rgba[i + 3] = a;
  }

  /// 0xAARRGGBB at (x, y), 0 outside.
  int at(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return 0;
    final i = (y * w + x) * 4;
    return rgba[i + 3] << 24 | rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2];
  }

  void fill(int x, int y, int fw, int fh, int argb) {
    for (var j = y; j < y + fh; j++) {
      for (var i = x; i < x + fw; i++) {
        set(
          i,
          j,
          argb >> 16 & 255,
          argb >> 8 & 255,
          argb & 255,
          argb >> 24 & 255,
        );
      }
    }
  }
}

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;
  static const zero = Vec3(0, 0, 0);
  static const back = Vec3(0, 0, 1);
  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 normalized() {
    final l = length;
    return l < 1e-9 ? this : Vec3(x / l, y / l, z / l);
  }

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
}

/// A colour with 0..1 parts.
class Rgb {
  const Rgb(this.r, this.g, this.b, [this.a = 1]);
  final double r, g, b, a;
  static Rgb from8(int r, int g, int b) => Rgb(r / 255, g / 255, b / 255);
  static Rgb hex(String h) {
    final v = int.parse(h, radix: 16);
    return from8(v >> 16 & 255, v >> 8 & 255, v & 255);
  }

  int get argb =>
      (a * 255).round().clamp(0, 255) << 24 |
      (r * 255).round().clamp(0, 255) << 16 |
      (g * 255).round().clamp(0, 255) << 8 |
      (b * 255).round().clamp(0, 255);

  Rgb lightened(double k) =>
      Rgb(r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k, a);
  Rgb darkened(double k) => Rgb(r * (1 - k), g * (1 - k), b * (1 - k), a);

  /// From hue (0..1), saturation and value.
  static Rgb hsv(double h, double s, double v) {
    final i = (h * 6).floor() % 6;
    final f = h * 6 - (h * 6).floor();
    final p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
    return switch (i) {
      0 => Rgb(v, t, p),
      1 => Rgb(q, v, p),
      2 => Rgb(p, v, t),
      3 => Rgb(p, q, v),
      4 => Rgb(t, p, v),
      _ => Rgb(v, p, q),
    };
  }
}

/// A PS2 save icon (.ico / .icn): a small 3D model, up to a few morph
/// shapes, one 128×128 texture; in the menu's axes (Y up, Z toward the
/// viewer), centred and scaled to fit. Filled by ps2_icon.dart.
class Ps2Icon {
  final shapes = <List<Vec3>>[];
  final normals = <Vec3>[];
  final uvs = <(double, double)>[];
  final colors = <Rgb>[];

  /// Textured icons store 128 as full brightness.
  double colorScale = 1;

  /// Animation length in ticks (60 a second), and speed.
  double length = 1, speed = 1;

  /// Morph weights over time: shape → keys of (tick, weight).
  final tracks = <({int shape, List<(double, double)> keys})>[];
  Pixels? texture;

  int get vertexCount => normals.length;
  double get loopSeconds => math.max(length / math.max(speed, 0.01) / 60, 0.8);
}

/// The consoles with saves here: the seven with virtual memory cards, plus
/// PS3 (save folders on its hard drive). Names, units, colours, library ids.
/// The colours are for our own drawings of a card; no console's logo.
abstract final class CardSystems {
  static const order = [
    'PS2',
    'PS1',
    'PS3',
    'DC',
    'GC',
    'N64',
    'SATURN',
    'NEO GEO',
  ];
  static const tabs = [
    'ALL',
    'PS1',
    'PS2',
    'PS3',
    'DC',
    'GC',
    'N64',
    'SATURN',
    'NEO GEO',
  ];
  static const info = <String, Map<String, String>>{
    'PS3': {
      'name': 'PlayStation 3',
      'unit': 'KB',
      'badge': '4b4f63',
      'shell': 'c9ccd8',
      'edge': '6e7186',
      'label': '5a5e74',
      'ink': 'e8eaf3',
      'library': 'ps3',
    },
    'PS1': {
      'name': 'PlayStation',
      'unit': 'block',
      'badge': '747b8c',
      'shell': 'a9adb8',
      'edge': '6d7280',
      'label': '8d929f',
      'ink': 'e9ebf0',
      'library': 'ps1',
    },
    'PS2': {
      'name': 'PlayStation 2',
      'unit': 'KB',
      'badge': '2355d8',
      'shell': '17181d',
      'edge': '626a7a',
      'label': '23262f',
      'ink': '6ea8ff',
      'library': 'ps2',
    },
    'DC': {
      'name': 'Dreamcast',
      'unit': 'block',
      'badge': 'd8641c',
      'shell': 'e6e7ea',
      'edge': '8e939c',
      'label': '9fb39a',
      'ink': '26361f',
      'library': 'dreamcast',
    },
    'GC': {
      'name': 'GameCube',
      'unit': 'block',
      'badge': '5a44b8',
      'shell': '4b3f93',
      'edge': '8b80d0',
      'label': '2b245c',
      'ink': 'dcd6ff',
      'library': 'gamecube',
    },
    'N64': {
      'name': 'Nintendo 64',
      'unit': 'page',
      'badge': '23894a',
      'shell': '6f737b',
      'edge': 'a4a8b0',
      'label': '3a3d44',
      'ink': '8df0a8',
      'library': 'n64',
    },
    'SATURN': {
      'name': 'Saturn',
      'unit': 'block',
      'badge': '4a5878',
      'shell': '2d3139',
      'edge': '7c8596',
      'label': '444b59',
      'ink': 'e3e8f2',
      'library': 'saturn',
    },
    'NEO GEO': {
      'name': 'Neo Geo',
      'unit': 'block',
      'badge': 'a8861c',
      'shell': '222222',
      'edge': 'b59a45',
      'label': '5d4d1e',
      'ink': 'ffe08a',
      'library': 'neogeo',
    },
  };

  static Rgb color(String system, String key) =>
      Rgb.hex((info[system] ?? info['PS1']!)[key]!);

  static String unit(String system, int count) {
    final word = (info[system] ?? info['PS1']!)['unit']!;
    return word == 'KB' || count == 1 ? word : '${word}s';
  }

  static int rank(String system) {
    final i = order.indexOf(system);
    return i >= 0 ? i : order.length;
  }
}

/// One save on a memory card: what the old consoles showed, plus what the
/// menu knows about its game.
class CardSave {
  static const regions = {'BA': 'America', 'BE': 'Europe', 'BI': 'Japan'};

  String system = '';

  /// Folder (PS2) or file (PS1) name on the card.
  String id = '';

  /// SLUS-20946
  String serial = '';
  String region = '';

  /// The save's own title, often with progress in it.
  final titleLines = <String>[];
  int kb = 0;

  /// In the card's own unit (not PS2).
  int blocks = 0;

  /// Where its writer finds it (not PS2: that goes by folder name).
  int slot = -1;

  /// In a folder of .gci: which file.
  String file = '';

  /// PS1 (and others): which blocks it sits in.
  final held = <int>[];

  /// Unix seconds; 0 = the format doesn't store it.
  int created = 0, modified = 0;
  bool copyProtected = false;
  bool favorite = false;

  /// Every file inside: name, size, modified.
  final files = <({String name, int size, int modified})>[];
  MemoryCard? card;

  // The icon.
  final frames = <Pixels>[];

  /// PS2: list, copy, delete.
  final icons = <Ps2Icon?>[null, null, null];
  Rgb ambient = const Rgb(0.5, 0.5, 0.5);
  final lightDirs = <Vec3>[];
  final lightColors = <Rgb>[];

  /// The save's own four corner colours.
  final backColors = <Rgb>[];
  double backAlpha = 0;

  // PS3: the wide picture, the backdrop file, the game name it carries.
  Pixels? wide;
  String backdrop = '';
  String ps3Title = '';

  // Filled in from the library and play history.
  String game = '';
  String gameId = '';
  int playedS = 0, sessions = 0, lastPlayed = 0;

  void setId(String saveId) {
    id = saveId;
    serial = serialFrom(saveId);
    region = regions[saveId.length >= 2 ? saveId.substring(0, 2) : ''] ?? '';
  }

  /// "BASLUS-20946GTA50000" -> "SLUS-20946"
  static String serialFrom(String saveId) {
    if (saveId.length < 2) return '';
    final m = RegExp(r'([A-Z]{4})[-P]?(\d{5})').firstMatch(saveId.substring(2));
    return m == null ? '' : '${m.group(1)}-${m.group(2)}';
  }

  String sizeText() {
    if (system == 'PS3') return MemoryCard.sizeWords(kb);
    if (system != 'PS2') {
      return '$blocks ${CardSystems.unit(system, blocks)} ($kb KB)';
    }
    return '${MemoryCard.thousands(kb)} KB';
  }

  /// Under its icon in a grid: a PS3 save says where you are.
  String cellName() => system == 'PS3' && titleLines.isNotEmpty
      ? titleLines.first
      : displayName();

  String displayName() {
    if (game.isNotEmpty) return game;
    if (titleLines.isNotEmpty) return titleLines.first;
    return id;
  }
}

/// One memory card as read from disk. Pure data.
class MemoryCard {
  static const testPrefix = 'TEST ';
  static const plainFolders = [
    'memcards',
    'memory_cards',
    'saves',
    'save',
    'dc',
    'system',
    'gc',
  ];

  /// A PS1 card has 15 blocks; a PS2 card is drawn as 15 slices.
  static const blocksShown = 15;

  /// One of [CardSystems.order].
  String system = '';
  String name = '';
  String path = '';

  /// PS1: blocks, PS2: KB.
  int free = 0, total = 0;
  int modified = 0;

  /// Why it couldn't be read ('' = fine).
  String error = '';
  final saves = <CardSave>[];

  /// Where it sits in its file: four N64 paks can share one file, a Saturn
  /// cart can be gzipped.
  int offset = 0, span = 0;
  bool gzip = false;

  /// A blank card: only Format works on it.
  bool unformatted = false;

  /// A PCSX2 folder card or a folder of .gci files (or PS3 saves).
  bool isFolder = false;

  /// "IN PCSX2 SLOT 2": the console sees it.
  String inSlot = '';
  int slotOrder = 0;

  /// In a Dreamcast slot: the file this card came from.
  String home = '';

  // This menu's own look for it: no colour (0) = the console's own.
  int color = 0;
  String finish = '', sticker = '';
  Pixels? stickerImage;
  int orderRank = 0;

  String freeText() {
    if (unformatted) return 'Not formatted';
    if (error.isNotEmpty) return "Can't be read";
    if (system == 'PS3') {
      var kb = 0;
      for (final s in saves) {
        kb += s.kb;
      }
      return '${saves.length} save${saves.length == 1 ? '' : 's'}, ${sizeWords(kb)}';
    }
    if (system != 'PS2') {
      return '$free of $total ${CardSystems.unit(system, total)} free';
    }
    return '${thousands(free)} KB free';
  }

  /// Which of the 15 blocks are lit: (used by [save], used at all).
  (int, int) litBlocks([CardSave? save]) {
    if (total <= 0) return (0, 0);
    final per = total / blocksShown;
    final used = ((total - free) / per).round();
    if (save == null) return (0, used);
    final amount = system == 'PS2' ? save.kb : save.blocks;
    return (math.max(1, (amount / per).round()), used);
  }

  /// One per card, even when several share a file.
  String key() => offset == 0 ? path : '$path#$offset';

  bool isTest() => name.startsWith(testPrefix);

  /// 1303 KB -> "1.3 MB", 840 -> "840 KB"
  static String sizeWords(int kb) =>
      kb < 1024 ? '$kb KB' : '${(kb / 1024).toStringAsFixed(1)} MB';

  static String thousands(int n) {
    var digits = n.abs().toString();
    var out = '';
    while (digits.length > 3) {
      out = ',${digits.substring(digits.length - 3)}$out';
      digits = digits.substring(0, digits.length - 3);
    }
    return '${n < 0 ? '-' : ''}$digits$out';
  }
}

/// What a writer hands back: the changed card (or exported save), or why
/// it couldn't be done. Never both.
class CardEdit {
  CardEdit.done(this.data) : error = '';
  CardEdit.fail(this.error) : data = Uint8List(0);
  final Uint8List data;
  final String error;
  bool get ok => error.isEmpty;
}
