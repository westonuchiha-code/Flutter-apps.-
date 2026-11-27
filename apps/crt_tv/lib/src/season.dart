/// Seasonal channels: a tag in square brackets in a channel's folder name
/// says which months it's on the air, e.g. "Channel Halloween [Oct]" or
/// "Channel Beach Episodes [Jun-Aug]". No tag means all year.

const List<String> _monthNames = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

const Map<String, List<int>> _seasonWords = {
  'spring': [3, 4, 5],
  'summer': [6, 7, 8],
  'fall': [9, 10, 11],
  'autumn': [9, 10, 11],
  'winter': [12, 1, 2],
};

final RegExp _tag = RegExp(r'\s*\[([^\[\]]+)\]\s*');
final RegExp _rangeSeparator = RegExp(r'\s*(?:-|–|—|\bto\b)\s*');

/// 1..12 for "oct", "October", "sept" or "10"; null for anything else.
int? _month(String word) {
  final w = word.trim().toLowerCase().replaceAll('.', '');
  if (w.isEmpty) return null;
  final number = int.tryParse(w);
  if (number != null) return number >= 1 && number <= 12 ? number : null;
  if (w.length < 3) return null;
  for (var i = 0; i < 12; i++) {
    if (_monthNames[i].startsWith(w) || (w == 'sept' && i == 8)) return i + 1;
  }
  return null;
}

/// The months named by text such as "Oct", "Jun-Aug", "Dec to Feb",
/// "Oct, Dec" or "Summer". Null if it isn't a season at all.
Set<int>? parseSeason(String text) {
  final months = <int>{};
  for (final part in text.split(RegExp('[,&/]'))) {
    final piece = part.trim().toLowerCase();
    if (piece.isEmpty) return null;
    final word = _seasonWords[piece];
    if (word != null) {
      months.addAll(word);
      continue;
    }
    final ends = piece.split(_rangeSeparator);
    if (ends.length > 2) return null;
    final from = _month(ends.first);
    final to = _month(ends.last);
    if (from == null || to == null) return null;
    // A range may run over New Year: Nov-Jan is November, December, January.
    for (var m = from;; m = m % 12 + 1) {
      months.add(m);
      if (m == to) break;
    }
  }
  return months.isEmpty ? null : months;
}

/// Splits "Channel Halloween [Oct]" into "Channel Halloween" and {10}.
/// Brackets that aren't a season ("[HD]") are left in the name.
(String, Set<int>) splitSeasonTag(String folderName) {
  for (final match in _tag.allMatches(folderName)) {
    final months = parseSeason(match.group(1)!);
    if (months != null) {
      final cleaned = folderName.replaceRange(match.start, match.end, ' ').trim();
      return (cleaned.replaceAll(RegExp(r'\s+'), ' '), months);
    }
  }
  return (folderName, const <int>{});
}

/// Whether a channel with these [months] is on the air on [date].
bool inSeason(Set<int> months, DateTime date) => months.isEmpty || months.contains(date.month);

/// "OCT", "JUN-AUG", "DEC-FEB", "OCT, DEC"; '' for all year.
String seasonLabel(Set<int> months) {
  if (months.isEmpty || months.length == 12) return '';
  String name(int m) => _monthNames[m - 1].substring(0, 3).toUpperCase();
  // Find runs of consecutive months, starting from one whose previous
  // month is not included, so a run over New Year stays in one piece.
  final starts = [
    for (final m in months)
      if (!months.contains((m + 10) % 12 + 1)) m,
  ]..sort();
  final runs = <String>[];
  for (final start in starts) {
    var end = start;
    while (months.contains(end % 12 + 1) && end % 12 + 1 != start) {
      end = end % 12 + 1;
    }
    runs.add(end == start ? name(start) : '${name(start)}-${name(end)}');
  }
  return runs.join(', ');
}
