import 'package:flutter_test/flutter_test.dart';
import 'package:xmb_frontend/src/library/scanner.dart';
import 'package:xmb_frontend/src/save_start.dart';

void main() {
  Game g(String sys, String file, String title) => Game(
    system: sys,
    path: '/storage/emulated/0/XMB Frontend/ROMs/$sys/$file',
    title: title,
    size: 1,
  );
  final library = [
    g(
      'ps1',
      'Harry Potter and the Sorcerers Stone (USA).chd',
      "Harry Potter and the Sorcerer's Stone",
    ),
    g('gamecube', 'Pokemon XD - Gale of Darkness (USA).rvz', 'Pokemon XD'),
    g('gamecube', 'Pokemon Colosseum (USA).iso', 'Pokemon Colosseum'),
    g('n64', 'Legend of Zelda, The - Ocarina of Time (USA).z64', 'Zelda OoT'),
    g('gba', 'Pokemon - Emerald Version (USA).gba', 'Pokemon Emerald'),
  ];

  SaveStartRequest? req(Map<String, String> m) => SaveStartRequest.fromMap(m);

  test('the extras read back; no console, no request', () {
    final r = req({
      'start_game_system': 'GC',
      'start_game_title': 'Pokemon XD',
      'start_game_serial': '',
      'start_game_file': '01-GXXE-PokemonXD.gci',
    })!;
    expect(r.system, 'GC');
    expect(r.title, 'Pokemon XD');
    expect(r.file, '01-GXXE-PokemonXD.gci');
    expect(req({'start_game_title': 'x'}), isNull);
    expect(SaveStartRequest.fromMap(null), isNull);
  });

  test('matches like the Memory Card row: console, then the title', () {
    // Accents folded: the save's "Pokémon" is the ROM's "Pokemon".
    expect(
      gameForSave(
        library,
        const SaveStartRequest(system: 'GC', title: 'Pokémon XD'),
      )?.path,
      endsWith('Pokemon XD - Gale of Darkness (USA).rvz'),
    );
    expect(
      gameForSave(
        library,
        const SaveStartRequest(system: 'GC', title: 'POKEMON XD'),
      )?.title,
      'Pokemon XD',
    );
    // Punctuation and "the" don't matter (save_kit's matchKey).
    expect(
      gameForSave(
        library,
        const SaveStartRequest(
          system: 'PS1',
          title: 'Harry Potter and the Sorcerers Stone',
        ),
      )?.system,
      'ps1',
    );
    // A RetroArch card named after the ROM file, region and all.
    expect(
      gameForSave(
        library,
        const SaveStartRequest(
          system: 'N64',
          title: 'Legend of Zelda, The - Ocarina of Time (USA)',
        ),
      )?.title,
      'Zelda OoT',
    );
  });

  test('another console, or no title, matches nothing', () {
    expect(
      gameForSave(
        library,
        const SaveStartRequest(system: 'PS1', title: 'Pokemon Colosseum'),
      ),
      isNull,
    );
    // GBA saves aren't the save manager's: never matched.
    expect(
      gameForSave(
        library,
        const SaveStartRequest(system: 'GBA', title: 'Pokemon Emerald'),
      ),
      isNull,
    );
    const none = SaveStartRequest(system: 'GC', file: 'a.gci');
    expect(gameForSave(library, none), isNull);
    expect(noGameText(none), 'No game in the library matches a.gci');
    expect(
      noGameText(const SaveStartRequest(system: 'GC', title: 'Mario Party 4')),
      'No game in the library matches Mario Party 4',
    );
  });
}
