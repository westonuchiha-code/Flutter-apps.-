/// Pokémon boxes of the Game Boy and GBA games (Gen 1-3): open a save, list
/// its boxes and party, take Pokémon out as PKHeX files (.pk1 .pk2 .pk3) and
/// put them back, byte for byte the way PKHeX does. Pure Dart; every change
/// returns new bytes and nothing here writes files.
library;

export 'src/dex.dart' show speciesName, moveName, heldItemChoices;
export 'src/mon.dart'
    show Mon, MonEdit, maxNicknameLength, nicknameCanWrite, heldItemAllowed;
export 'src/poke_save.dart';
