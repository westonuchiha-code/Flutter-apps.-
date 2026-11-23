/// One cheat code. [sequence] is space-separated button tokens:
/// X O T S (face buttons), U D L R (d-pad), L1 L2 R1 R2 (shoulders).
class Cheat {
  const Cheat(this.name, this.sequence, {this.note = ''});
  final String name;
  final String sequence;
  final String note;

  List<String> get buttons => sequence.split(' ');
}

class CheatCategory {
  const CheatCategory(this.name, this.cheats);
  final String name;
  final List<Cheat> cheats;
}

class Mission {
  const Mission(this.name, this.giver, this.tip);
  final String name;

  /// Who gives the mission (or "Intro").
  final String giver;
  final String tip;
}

class Chapter {
  const Chapter(this.name, this.missions);
  final String name;
  final List<Mission> missions;
}

/// Something that counts toward 100%: a counter when [max] is set,
/// otherwise a checkbox.
class TrackItem {
  const TrackItem({
    required this.id,
    required this.name,
    this.max,
    this.detail = '',
  });
  final String id;
  final String name;
  final int? max;
  final String detail;
}

class TrackSection {
  const TrackSection(this.name, this.items);
  final String name;
  final List<TrackItem> items;
}

class ExportList {
  const ExportList(this.name, this.cars);
  final String name;
  final List<String> cars;
}

class Place {
  const Place(this.area, this.name, this.description);
  final String area;
  final String name;
  final String description;
}

class RefSection {
  const RefSection(this.title, this.blocks);
  final String title;
  final List<RefBlock> blocks;
}

sealed class RefBlock {
  const RefBlock();
}

class RefTable extends RefBlock {
  const RefTable(this.rows);
  final List<RefRow> rows;
}

class RefRow {
  const RefRow(this.cells, {this.header = false});
  final List<String> cells;
  final bool header;
}

class RefCard extends RefBlock {
  const RefCard(this.text);
  final String text;
}

class RefText extends RefBlock {
  const RefText(this.text);
  final String text;
}
