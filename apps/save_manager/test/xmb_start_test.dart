import 'package:flutter_test/flutter_test.dart';
import 'package:save_kit/save_kit.dart';
import 'package:save_manager/src/xmb_start.dart';

void main() {
  test('a GameCube save: its own title line and .gci file', () {
    final s = CardSave()
      ..system = 'GC'
      ..file = '01-GXXE-PokemonXD.gci';
    s.titleLines.addAll(['Pokemon XD', 'Gale of Darkness']);
    expect(xmbStartExtras(s), {
      'start_game_system': 'GC',
      'start_game_title': 'Pokemon XD',
      'start_game_serial': '',
      'start_game_file': '01-GXXE-PokemonXD.gci',
    });
  });

  test("a PS1 card named after its game: the name save_kit gave it", () {
    final card = MemoryCard()
      ..system = 'PS1'
      ..name = 'Crash Bandicoot'
      ..path =
          '/storage/emulated/0/XMB Frontend/Saves/DuckStation/'
          'memcards/Crash Bandicoot_1.mcd';
    final s = CardSave()
      ..system = 'PS1'
      ..card = card
      ..game = 'Crash Bandicoot '
      ..setId('BASCUS-94900CRASH');
    s.titleLines.add('CRASH BANDICOOT  SAVE 1');
    final e = xmbStartExtras(s);
    expect(e['start_game_system'], 'PS1');
    expect(e['start_game_title'], 'Crash Bandicoot');
    expect(e['start_game_serial'], 'SCUS-94900');
    expect(e['start_game_file'], 'Crash Bandicoot_1.mcd');
  });

  test('only the consoles the XMB starts; the notice says how', () {
    expect(xmbStartSystems, containsAll(['PS1', 'N64', 'SATURN', 'DC', 'GC']));
    expect(xmbStartSystems, isNot(contains('PS2')));
    expect(xmbStartSystems, isNot(contains('PS3')));
    expect(xmbMissingNotice, startsWith('Start game works through the XMB'));
    expect(xmbPackage, 'com.westonuchiha.xmb_frontend');
    expect(xmbActivity, 'com.westonuchiha.xmb_frontend.MainActivity');
  });
}
