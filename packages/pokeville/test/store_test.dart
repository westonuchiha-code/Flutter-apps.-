// The Box's storage (ported from the PC's tools/PokeBoxTests.gd, _store),
// plus box.json round trips with the PC's real example.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pokeville/pokeville.dart';

import 'fixtures.dart';

void main() {
  test('the data functions, as on the PC', () {
    final d = PokeBoxStore.blank();
    expect(PokeBoxStore.boxCount(d), PokeBoxStore.startBoxes);
    expect(PokeBoxStore.firstEmpty(d), (0, 0));
    expect(
      PokeBoxStore.place(d, 0, 0, 'mons/a.pk3', {'name': 'Mudkip'}),
      isTrue,
    );
    expect(
      PokeBoxStore.place(d, 0, 0, 'mons/b.pk3', {}),
      isFalse,
      reason: "can't place over a Pokémon",
    );
    expect(PokeBoxStore.firstEmpty(d), (0, 1));
    expect(PokeBoxStore.move(d, 0, 0, 3, 7), isTrue);
    expect(
      PokeBoxStore.isEmpty(d, 0, 0) && !PokeBoxStore.isEmpty(d, 3, 7),
      isTrue,
    );
    PokeBoxStore.place(d, 0, 0, 'mons/c.pk3', {'name': 'Torchic'});
    expect(
      PokeBoxStore.move(d, 0, 0, 3, 7),
      isTrue,
      reason: 'onto a Pokémon swaps',
    );
    expect(PokeBoxStore.slot(d, 0, 0)['mon']['name'], 'Mudkip');
    expect(PokeBoxStore.slot(d, 3, 7)['mon']['name'], 'Torchic');
    expect(PokeBoxStore.total(d), 2);
    final last = PokeBoxStore.boxCount(d) - 1;
    PokeBoxStore.place(d, last, 0, 'mons/d.pk3', {});
    expect(
      PokeBoxStore.boxCount(d),
      last + 2,
      reason: 'filling the last box adds a spare one',
    );
    expect(PokeBoxStore.boxName(d, last + 1), 'Box ${last + 2}');
    expect(PokeBoxStore.clear(d, last, 0).containsKey('file'), isTrue);
    expect(PokeBoxStore.isEmpty(d, last, 0), isTrue);
    expect(PokeBoxStore.slot(d, 99, 0), isEmpty);
    expect(PokeBoxStore.slot(d, 0, 99), isEmpty);
    expect(
      PokeBoxStore.move(d, 5, 5, 0, 1),
      isFalse,
      reason: 'nothing to move',
    );
    expect(PokeBoxStore.move(d, 0, 0, 99, 0), isFalse, reason: 'no such box');
  });

  test('paths: relative with /, absolute on this machine', () {
    final dir = p.join('x', 'pv');
    expect(
      PokeBoxStore.relative(dir, p.join(dir, 'mons', 'a.pk3')),
      'mons/a.pk3',
    );
    expect(
      PokeBoxStore.absolute(dir, 'mons/a.pk3'),
      p.join(dir, 'mons', 'a.pk3'),
    );
  });

  test("the PC's example reads, and writes back byte for byte", () {
    final text = File(p.join(exampleDir, 'box.json')).readAsStringSync();
    final d = PokeBoxStore.parse(text)!;
    expect(PokeBoxStore.boxCount(d), 2, reason: 'box 2 is the empty spare');
    expect(PokeBoxStore.total(d), 3);
    final m = Mon.of(PokeBoxStore.slot(d, 0, 0))!;
    expect(m.species, 52, reason: 'numbers are floats (52.0)');
    expect(m.shownName, 'D․I․Z․');
    expect(m.name, 'Meowth');
    expect(m.level, 19);
    expect(m.gender, 0);
    expect(m.item, 'Grepa Berry');
    expect(m.stats, [40, 45, 35, 40, 40, 90]);
    expect(m.types, ['Normal']);
    expect(PokeBoxStore.encode(d), text, reason: 'the PC loses nothing');
    expect(PokeBoxStore.species(d), {52, 230, 85});
  });

  test('a move keeps every field (known or not) and floats as floats', () {
    final text = File(p.join(exampleDir, 'box.json')).readAsStringSync();
    final d = PokeBoxStore.parse(text)!;
    (d['boxes'][0] as Map)['unknown_box_field'] = {'keep': 1.5};
    (PokeBoxStore.slot(d, 0, 1)['mon'] as Map)['future'] = [1.0, 'x'];
    d['extra'] = true;
    final before = PokeBoxStore.slot(d, 0, 1);
    expect(PokeBoxStore.move(d, 0, 1, 1, 29), isTrue);
    final out = PokeBoxStore.encode(d);
    final back = PokeBoxStore.parse(out)!;
    expect(PokeBoxStore.slot(back, 1, 29), before);
    expect(back['extra'], isTrue);
    expect((back['boxes'][0] as Map)['unknown_box_field'], {'keep': 1.5});
    expect(out, contains('"species": 230.0'));
    expect(out, contains('"version": 1.0'));
    expect(PokeBoxStore.boxCount(back), 3, reason: 'box 2 filled: a new spare');
  });

  test('broken or odd box.json', () {
    expect(PokeBoxStore.parse('{broken'), isNull);
    expect(PokeBoxStore.parse('[]'), isNull);
    expect(PokeBoxStore.parse('{"boxes": []}'), isNull);
    final short = PokeBoxStore.parse(
      '{"version": 1, "boxes": [{"name": "A", "slots": [{}]}]}',
    )!;
    expect((PokeBoxStore.boxes(short)[0] as Map)['slots'], hasLength(30));
    expect(
      PokeBoxStore.boxCount(short),
      1,
      reason: 'an empty last box is the spare',
    );
  });

  test('Mon reads what the helper writes, and copes with gaps', () {
    const m = Mon({'species': 25, 'shiny': true, 'egg': false, 'gender': 1.0});
    expect(m.shownName, '?');
    expect(m.shiny, isTrue);
    expect(m.gender, 1);
    expect(m.moves, isEmpty);
    expect(const Mon({'egg': true, 'name': 'Togepi'}).shownName, 'Egg');
    expect(const Mon({}).gender, 2);
    final copy = PokeBoxStore.copy(PokeBoxStore.blank());
    expect(PokeBoxStore.boxCount(copy), PokeBoxStore.startBoxes);
  });
}
