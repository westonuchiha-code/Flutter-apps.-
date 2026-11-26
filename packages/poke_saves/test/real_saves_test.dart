// The owner's real saves and Pokéville files (read only, never copied here).
// Runs when POKE_SAMPLES points at the cross-save folder, e.g.
//   POKE_SAMPLES=/home/user/cross-save dart test
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:poke_saves/poke_saves.dart';
import 'package:test/test.dart';

final String? root = Platform.environment['POKE_SAMPLES'];
final skip = root == null || !Directory(root!).existsSync()
    ? 'POKE_SAMPLES not set'
    : null;

Uint8List read(String rel) => File('$root/$rel').readAsBytesSync();

const gbSaves = [
  'saves/retroarch/Gambatte/Pokemon - Red Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Blue Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Yellow Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Gold Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Silver Version (USA, Europe).srm',
  'saves/retroarch/Gambatte/Pokemon - Crystal Version (USA, Europe).srm',
];
const gbaSaves = [
  'saves/retroarch/mGBA/Pokemon - Leaf Green Version.srm',
  'saves/retroarch/mGBA/Pokemon_Emerald_USA_GBA-TRM.srm',
];
const allSaves = [...gbSaves, ...gbaSaves];

PokeSave open(String rel) =>
    PokeSave.open(read(rel), fileName: rel.split('/').last)!;

bool sameValue(Object? a, Object? b) {
  if (a is num && b is num) {
    return a == b;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!sameValue(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

void main() {
  group('real saves', skip: skip, () {
    test('every save opens as the right game, checksums right', () {
      final expect_ = {
        'Red': ('Red', PokeGame.redBlue),
        'Blue': ('Blue', PokeGame.redBlue),
        'Yellow': ('Yellow', PokeGame.yellow),
        'Gold': ('Gold', PokeGame.goldSilver),
        'Silver': ('Silver', PokeGame.goldSilver),
        'Crystal': ('Crystal', PokeGame.crystal),
        'Leaf': ('LeafGreen', PokeGame.fireRedLeafGreen),
        'Emerald': ('Emerald', PokeGame.emerald),
      };
      for (final rel in allSaves) {
        final s = open(rel);
        final key = expect_.keys.firstWhere(rel.contains);
        expect(s.gameName, expect_[key]!.$1, reason: rel);
        expect(s.game, expect_[key]!.$2, reason: rel);
        expect(s.check(), '', reason: rel);
        expect(s.trainer.toUpperCase(), 'WESTON', reason: rel);
        expect(s.party, isNotEmpty, reason: rel);
      }
    });

    test('opening without a file name gives PKHeX\'s own game names', () {
      expect(PokeSave.open(read(gbSaves[0]))!.gameName, 'RB');
      expect(PokeSave.open(read(gbSaves[3]))!.gameName, 'GS');
      expect(PokeSave.open(read(gbaSaves[0]))!.gameName, 'FireRed');
    });

    test(
      'summaries equal the PC helper\'s box.json entries field by field',
      () {
        final box =
            jsonDecode(File('$root/pokeville/box.json').readAsStringSync())
                as Map<String, dynamic>;
        var compared = 0, other = 0;
        for (final b in box['boxes'] as List) {
          for (final slot in (b as Map)['slots'] as List) {
            final s = slot as Map;
            if (s['file'] == null) {
              continue;
            }
            final file = s['file'] as String;
            final ext = file.split('.').last;
            final m = Mon.fromFile(read('pokeville/$file'), ext: ext);
            if (!['pk1', 'pk2', 'pk3'].contains(ext)) {
              expect(m, isNull, reason: file);
              other++;
              continue;
            }
            final want = Map<String, dynamic>.from(s['mon'] as Map)
              ..remove('from')
              ..remove('from_save');
            final got = m!.summary;
            expect(got.keys.toSet(), want.keys.toSet(), reason: file);
            for (final k in want.keys) {
              expect(
                sameValue(got[k], want[k]),
                isTrue,
                reason: '$file $k: ${got[k]} vs ${want[k]}',
              );
            }
            compared++;
          }
        }
        expect(compared, 35);
        expect(other, 1); // the pk8
      },
    );

    test(
      'take from Gold gives the exact file PKHeX wrote (sent/ Larvitar)',
      () {
        final gold = open(gbSaves[3]);
        final r = gold.take(0, 2);
        expect(r.ok, isTrue, reason: r.error);
        expect(
          r.mon!.bytes,
          read('pokeville/mons/sent/20261124-220244-269559.pk2'),
        );
        final after = PokeSave.open(r.save!)!;
        expect(after.check(), '');
        expect(after.boxes[0].count, 2);
      },
    );

    test('Red\'s party Charmander is byte for byte the .pk1 PKHeX dumped', () {
      final red = open(gbSaves[0]);
      expect(
        red.party.first.bytes,
        read('pokeville/mons/20261124-220244-011878.pk1'),
      );
    });

    test(
      'pk2 -> Gen 1 conversion matches what PKHeX put into Blue and Yellow',
      () {
        final cases = {
          gbSaves[1]: [
            '20261124-220244-054466',
            '20261124-220244-820697',
            '20261124-220244-062106',
          ],
          gbSaves[2]: ['20261124-220244-022764', '20261124-220244-426921'],
        };
        for (final MapEntry(key: rel, value: files) in cases.entries) {
          final save = open(rel);
          for (var i = 0; i < files.length; i++) {
            final pk2 = read('pokeville/mons/${files[i]}.pk2');
            final r = save.put(1, 0, pk2, ext: 'pk2');
            expect(r.ok, isTrue, reason: r.error);
            expect(r.reason, startsWith('converted from pk2 to pk1'));
            final put = PokeSave.open(r.save!)!;
            expect(put.check(), '');
            expect(
              put.boxMon(1, 0)!.bytes,
              save.boxMon(0, i)!.bytes,
              reason: '${files[i]} into $rel',
            );
          }
        }
      },
    );

    test('pk1 -> Gen 2 through the Time Capsule', () {
      final crystal = open(gbSaves[5]);
      for (final f in ['20261124-220244-011878', '20261124-220244-750310']) {
        final pk1 = read('pokeville/mons/$f.pk1');
        final r = crystal.put(2, 0, pk1, ext: 'pk1');
        expect(r.ok, isTrue, reason: r.error);
        expect(r.reason, 'converted from pk1 to pk2');
        final s = PokeSave.open(r.save!)!;
        expect(s.check(), '');
        final m = s.boxMon(2, 0)!;
        final from = Mon.fromFile(pk1, ext: 'pk1')!;
        expect(m.ext, 'pk2');
        expect(m.species, from.species);
        expect(m.level, from.level);
        expect(m.summary['nickname'], from.summary['nickname']);
        expect(m.summary['ot'], from.summary['ot']);
        expect(m.summary['moves'], from.summary['moves']);
      }
    });

    test('moves the games never allowed are refused', () {
      final lg = open(gbaSaves[0]);
      final pk1 = read('pokeville/mons/20261124-220244-011878.pk1');
      expect(
        lg.put(0, 0, pk1, ext: 'pk1').error,
        contains("Game Boy Pokémon can't go to"),
      );
      final gold = open(gbSaves[3]);
      final pk3 = lg.party.first.bytes;
      expect(
        gold.put(1, 0, pk3, ext: 'pk3').error,
        contains("can't go back to a Game Boy game"),
      );
      final red = open(gbSaves[0]);
      final kingdra = read('pokeville/mons/20261124-220244-215252.pk2');
      expect(
        red.put(0, 0, kingdra, ext: 'pk2').error,
        contains("Kingdra doesn't exist"),
      );
      final egg = read('pokeville/mons/20261124-220244-237293.pk2');
      expect(red.put(0, 0, egg, ext: 'pk2').ok, isFalse);
    });

    test('Gen 3: a party Pokémon as .pk3 goes into a box, both games', () {
      final lg = open(gbaSaves[0]);
      final em = open(gbaSaves[1]);
      for (final (from, to) in [(lg, em), (em, lg), (lg, lg), (em, em)]) {
        final file = from.party.first.bytes;
        expect(file.length, 80);
        final r = to.put(3, 7, file, ext: 'pk3');
        expect(r.ok, isTrue, reason: r.error);
        expect(r.reason, 'fits as it is');
        final s = PokeSave.open(r.save!)!;
        expect(s.check(), '');
        expect(s.boxMon(3, 7)!.bytes, file);
        expect(s.boxMon(3, 7)!.summary, from.party.first.summary);
        // and back out again
        final t = s.take(3, 7);
        expect(t.ok, isTrue, reason: t.error);
        expect(t.mon!.bytes, file);
        expect(PokeSave.open(t.save!)!.check(), '');
        expect(PokeSave.open(t.save!)!.boxMon(3, 7), isNull);
      }
    });

    test('round trips: every box Pokémon of every save out and back in', () {
      var n = 0;
      for (final rel in allSaves) {
        final save = open(rel);
        for (var b = 0; b < save.boxCount; b++) {
          for (var s = 0; s < save.boxSlots; s++) {
            final m = save.boxMon(b, s);
            if (m == null) {
              continue;
            }
            final t = save.take(b, s);
            expect(t.ok, isTrue, reason: '$rel $b/$s ${t.error}');
            final out = PokeSave.open(t.save!)!;
            expect(out.check(), '', reason: rel);
            expect(t.mon!.bytes, m.bytes);
            final back = out.put(
              b,
              save.boxSlots - 1,
              t.mon!.bytes,
              ext: t.mon!.ext,
            );
            expect(back.ok, isTrue, reason: back.error);
            final again = PokeSave.open(back.save!)!;
            expect(again.check(), '', reason: rel);
            final slot = save.packedBoxes
                ? again.boxes[b].count - 1
                : save.boxSlots - 1;
            expect(again.boxMon(b, slot)!.bytes, m.bytes, reason: '$rel $b/$s');
            expect(again.boxes[b].count, save.boxes[b].count);
            n++;
          }
        }
      }
      expect(n, greaterThan(10));
    });

    test(
      'writing a save unchanged gives the same bytes (PKHeX-written saves)',
      () {
        for (final rel in allSaves) {
          final save = open(rel);
          final out = save.rewrite();
          if (rel.contains('Red')) {
            // Never written by PKHeX: the game leaves 0x00 after the party
            // list's 0xFF end mark, PKHeX (and this) fill the list with 0xFF.
            final orig = read(rel);
            final diff = [
              for (var i = 0; i < orig.length; i++)
                if (orig[i] != out[i]) i,
            ];
            expect(diff, [for (var i = 0x2F2F; i <= 0x2F33; i++) i, 0x3523]);
            expect(PokeSave.open(out)!.check(), '');
          } else if (rel.contains('Gold')) {
            // The game itself left one emptied slot's names as 0x50s past the
            // end of box 1's list; PKHeX's repacking writes zeros there.
            final orig = read(rel);
            for (var i = 0; i < orig.length; i++) {
              if (orig[i] != out[i]) {
                final names =
                    (i >= 0x3002 && i < 0x3002 + 440) ||
                    (i >= 0x4296 && i < 0x4296 + 440);
                expect(
                  names && orig[i] == 0x50 && out[i] == 0,
                  isTrue,
                  reason: 'Gold at $i',
                );
              }
            }
            expect(PokeSave.open(out)!.check(), '');
          } else {
            expect(out, read(rel), reason: rel);
          }
          expect(PokeSave.open(out)!.rewrite(), out, reason: rel);
        }
      },
    );

    test('move inside a save keeps every Pokémon', () {
      final silver = open(gbSaves[4]);
      final r = silver.move(0, 0, 5, 0);
      expect(r.ok, isTrue, reason: r.error);
      final s = PokeSave.open(r.save!)!;
      expect(s.check(), '');
      expect(s.boxes[0].count, 2);
      expect(s.boxMon(5, 0)!.bytes, silver.boxMon(0, 0)!.bytes);
    });
  });
}
