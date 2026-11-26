import 'package:save_kit/save_kit.dart';
void main(List<String> a) {
  final got = MemoryCards.readAll([a[0]]);
  for (final s in got.saves) {
    if (s.icons[0] == null && (s.id.contains('62652') || s.titleLines.any((t)=>t.contains('3')))) {
      print('${s.system} ${s.id} frames=${s.frames.length} ${[for (final f in s.frames) '${f.w}x${f.h} a=${f.rgba.where((v)=>v!=0).length}']}');
    }
  }
}
