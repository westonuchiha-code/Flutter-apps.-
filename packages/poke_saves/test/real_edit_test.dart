// Nicknames and held items on every real Pokémon of the owner's saves and
// Pokéville files (read only, never copied here; changes stay in memory).
// Runs when POKE_SAMPLES points at the cross-save folder:
//   POKE_SAMPLES=/home/user/cross-save dart test
import 'dart:io';
import 'dart:typed_data';

import 'package:poke_saves/poke_saves.dart';
import 'package:test/test.dart';

final String? root = Platform.environment['POKE_SAMPLES'];
final skip = root == null || !Directory(root!).existsSync()
    ? 'POKE_SAMPLES not set'
    : null;

Uint8List read(String rel) => File('$root/$rel').readAsBytesSync();

const saves = [
  'saves/retroarch/Gambatte/Pokemon - Red Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Blue Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Yellow Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Gold Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Silver Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Crystal Version (USA, Europe).srm',
  'saves/retroarch/mGBA/Pokemon - Leaf Green Version.srm',
  'saves/retroarch/mGBA/Pokemon_Emerald_USA_GBA-TRM.srm',
];

PokeSave open(String rel) =>
    PokeSave.open(read(rel), fileName: rel.split('/').last)!;

/// The nickname that names [m] back ('' when it has none).
String own(Mon m) => m.isNicknamed ? m.nickname : '';

/// A short name to rename to: one letter (a GBA name is written over the
/// old one, so a short one leaves nothing behind).
String other(Mon m) => m.nickname == 'Q' ? 'Z' : 'Q';

int leftoversFor(int format) => format == 2 ? 0x92 : 200;

void main() {
  group('real Pokémon', skip: skip, () {
    test('every Pokéville file: rename and back, item and back', () {
      final dir = Directory('$root/pokeville/mons');
      var n = 0, gbTrash = 0;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final ext = f.path.split('.').last;
        if (!['pk1', 'pk2', 'pk3'].contains(ext)) continue;
        final bytes = f.readAsBytesSync();
        final m = Mon.fromFile(bytes, ext: ext)!;
        final file = m.bytes;
        if (m.isEgg) {
          expect(m.withNickname('Hi').ok, isFalse);
          expect(m.withItem(0).ok, isFalse);
          continue;
        }
        final r = m.withNickname(other(m));
        expect(r.ok, isTrue, reason: '${f.path} ${r.error}');
        final back = r.mon!.withNickname(own(m));
        expect(back.ok, isTrue, reason: '${f.path} ${back.error}');
        expect(back.mon!.nickname, m.nickname, reason: f.path);
        expect(back.mon!.summary, m.summary, reason: f.path);
        if (m.format == 3) {
          expect(back.mon!.bytes, file, reason: f.path);
        } else if (!_same(back.mon!.bytes, file)) {
          // a Game Boy name buffer with the game's leftovers after the
          // name: PKHeX writes it cleared, so only the name is the same
          gbTrash++;
          final b = back.mon!.bytes;
          expect(b.sublist(0, b.length - 11), file.sublist(0, b.length - 11));
        }
        // the summary the PC's helper gives a renamed Pokémon
        expect(r.mon!.summary['nickname'], other(m));
        if (m.format == 1) {
          expect(m.withItem(leftoversFor(2)).error, contains('Gen 1'));
        } else {
          final it = m.withItem(leftoversFor(m.format));
          expect(it.ok, isTrue, reason: it.error);
          expect(it.mon!.summary['item'], 'Leftovers');
          final had = it.mon!.withItem(m.heldItem);
          expect(had.ok, isTrue, reason: '${f.path} ${had.error}');
          expect(had.mon!.bytes, file, reason: f.path);
          // the stored file reads back as what was written
          expect(
            Mon.fromFile(it.mon!.bytes, ext: ext)!.summary,
            it.mon!.summary,
          );
        }
        n++;
      }
      expect(n, greaterThan(25));
      printOnFailure('$n Pokémon, $gbTrash with Game Boy name leftovers');
    });

    test('every Pokémon in every save (boxes and party): rename and back, '
        'item and back, checksums right', () {
      var n = 0, gbTrash = 0;
      for (final rel in saves) {
        final save = open(rel);
        final base = save.rewrite();
        final at = <(int, int)>[
          for (var i = 0; i < save.party.length; i++) (PokeSave.partyBox, i),
          for (var b = 0; b < save.boxCount; b++)
            for (var s = 0; s < save.boxSlots; s++)
              if (save.boxMon(b, s) != null) (b, s),
        ];
        for (final (b, s) in at) {
          final m = save.monAt(b, s)!;
          final where = '$rel ${b < 0 ? 'party' : 'box $b'}/$s';
          if (m.isEgg) {
            expect(save.setNickname(b, s, 'Hi').ok, isFalse, reason: where);
            continue;
          }
          final r = save.setNickname(b, s, other(m));
          expect(r.ok, isTrue, reason: '$where ${r.error}');
          final s2 = PokeSave.open(r.save!, fileName: rel.split('/').last)!;
          expect(s2.check(), '', reason: where);
          expect(s2.monAt(b, s)!.nickname, other(m), reason: where);
          expect(s2.party.length, save.party.length);
          final back = s2.setNickname(b, s, own(m));
          expect(back.ok, isTrue, reason: '$where ${back.error}');
          if (!_same(back.save!, base)) {
            expect(m.format, lessThan(3), reason: where);
            gbTrash++;
            final again = PokeSave.open(back.save!)!;
            expect(again.monAt(b, s)!.summary, m.summary, reason: where);
          }
          if (m.format == 1) {
            expect(save.setItem(b, s, 0).ok, isFalse);
          } else {
            final it = save.setItem(b, s, leftoversFor(m.format));
            expect(it.ok, isTrue, reason: '$where ${it.error}');
            final s3 = PokeSave.open(it.save!)!;
            expect(s3.check(), '', reason: where);
            expect(s3.monAt(b, s)!.itemName, 'Leftovers', reason: where);
            if (heldItemAllowed(m.format, m.heldItem)) {
              final undo = s3.setItem(b, s, m.heldItem);
              expect(undo.save, base, reason: where);
            }
          }
          n++;
        }
      }
      expect(n, greaterThan(15));
      printOnFailure('$n Pokémon, $gbTrash with Game Boy name leftovers');
    });

    test('a party never changes size, and a missing slot is refused', () {
      for (final rel in saves) {
        final save = open(rel);
        final n = save.party.length;
        expect(n, greaterThan(0), reason: rel);
        expect(save.setNickname(PokeSave.partyBox, n, 'X').ok, isFalse);
        expect(save.setItem(PokeSave.partyBox, 6, 0).ok, isFalse);
      }
    });
  });
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
