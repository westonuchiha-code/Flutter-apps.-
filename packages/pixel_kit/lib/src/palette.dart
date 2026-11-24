import 'color.dart';

/// A named list of colours.
class Palette {
  const Palette(this.name, this.colors);

  final String name;
  final List<int> colors;

  static const kind = 'palette';

  /// Closest colour in the palette (transparent stays transparent).
  int nearest(int c) {
    if (alphaOf(c) < 128 || colors.isEmpty) return 0;
    var best = colors.first, bestD = 1 << 62;
    for (final p in colors) {
      final d = colorDistance(c, p);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'name': name,
    'colors': [for (final c in colors) hexOf(c)],
  };

  factory Palette.fromJson(Object? j) {
    if (j is! Map || j['kind'] != kind) {
      throw const FormatException('Not a palette');
    }
    return Palette((j['name'] as String?) ?? 'Palette', [
      for (final c in (j['colors'] as List?) ?? const [])
        if (c is String && parseHex(c) != null) parseHex(c)!,
    ]);
  }

  /// GIMP / Aseprite .gpl text.
  String toGpl() {
    final b = StringBuffer('GIMP Palette\nName: $name\nColumns: 8\n#\n');
    for (final c in colors) {
      b.writeln(
        '${redOf(c).toString().padLeft(3)} ${greenOf(c).toString().padLeft(3)} ${blueOf(c).toString().padLeft(3)}\t${hexOf(c)}',
      );
    }
    return b.toString();
  }

  factory Palette.fromGpl(String text, {String name = 'Imported'}) {
    var n = name;
    final colors = <int>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.startsWith('Name:')) n = t.substring(5).trim();
      final m = RegExp(r'^(\d+)\s+(\d+)\s+(\d+)').firstMatch(t);
      if (m != null) {
        colors.add(
          argb(255, int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)),
        );
      }
    }
    if (colors.isEmpty) throw const FormatException('No colours found');
    return Palette(n, colors);
  }
}

List<int> _hex(List<int> l) => [for (final h in l) rgb(h)];

/// Classic palettes. Hardware palettes use commonly published RGB
/// measurements of each machine's colours.
final builtInPalettes = <Palette>[
  Palette('Game Boy (green)', _hex([0x0F380F, 0x306230, 0x8BAC0F, 0x9BBC0F])),
  Palette(
    'Game Boy Pocket (grey)',
    _hex([0x000000, 0x555555, 0xAAAAAA, 0xFFFFFF]),
  ),
  Palette(
    'PICO-8 style 16',
    _hex([
      0x000000,
      0x1D2B53,
      0x7E2553,
      0x008751,
      0xAB5236,
      0x5F574F,
      0xC2C3C7,
      0xFFF1E8,
      0xFF004D,
      0xFFA300,
      0xFFEC27,
      0x00E436,
      0x29ADFF,
      0x83769C,
      0xFF77A8,
      0xFFCCAA,
    ]),
  ),
  Palette(
    'Commodore 64',
    _hex([
      0x000000,
      0xFFFFFF,
      0x68372B,
      0x70A4B2,
      0x6F3D86,
      0x588D43,
      0x352879,
      0xB8C76F,
      0x6F4F25,
      0x433900,
      0x9A6759,
      0x444444,
      0x6C6C6C,
      0x9AD284,
      0x6C5EB5,
      0x959595,
    ]),
  ),
  Palette(
    'ZX Spectrum',
    _hex([
      0x000000,
      0x0000D7,
      0xD70000,
      0xD700D7,
      0x00D700,
      0x00D7D7,
      0xD7D700,
      0xD7D7D7,
      0x0000FF,
      0xFF0000,
      0xFF00FF,
      0x00FF00,
      0x00FFFF,
      0xFFFF00,
      0xFFFFFF,
    ]),
  ),
  Palette('CGA (mode 4, high)', _hex([0x000000, 0x55FFFF, 0xFF55FF, 0xFFFFFF])),
  Palette(
    'CGA 16',
    _hex([
      0x000000,
      0x0000AA,
      0x00AA00,
      0x00AAAA,
      0xAA0000,
      0xAA00AA,
      0xAA5500,
      0xAAAAAA,
      0x555555,
      0x5555FF,
      0x55FF55,
      0x55FFFF,
      0xFF5555,
      0xFF55FF,
      0xFFFF55,
      0xFFFFFF,
    ]),
  ),
  Palette(
    'NES',
    _hex([
      0x7C7C7C,
      0x0000FC,
      0x0000BC,
      0x4428BC,
      0x940084,
      0xA80020,
      0xA81000,
      0x881400,
      0x503000,
      0x007800,
      0x006800,
      0x005800,
      0x004058,
      0x000000,
      0xBCBCBC,
      0x0078F8,
      0x0058F8,
      0x6844FC,
      0xD800CC,
      0xE40058,
      0xF83800,
      0xE45C10,
      0xAC7C00,
      0x00B800,
      0x00A800,
      0x00A844,
      0x008888,
      0xF8F8F8,
      0x3CBCFC,
      0x6888FC,
      0x9878F8,
      0xF878F8,
      0xF85898,
      0xF87858,
      0xFCA044,
      0xF8B800,
      0xB8F818,
      0x58D854,
      0x58F898,
      0x00E8D8,
      0x787878,
      0xFCFCFC,
      0xA4E4FC,
      0xB8B8F8,
      0xD8B8F8,
      0xF8B8F8,
      0xF8A4C0,
      0xF0D0B0,
      0xFCE0A8,
      0xF8D878,
      0xD8F878,
      0xB8F8B8,
      0xB8F8D8,
      0x00FCFC,
      0xF8D8F8,
    ]),
  ),
  Palette(
    'Greys (8)',
    _hex([
      0x000000,
      0x242424,
      0x494949,
      0x6D6D6D,
      0x929292,
      0xB6B6B6,
      0xDBDBDB,
      0xFFFFFF,
    ]),
  ),
];
