// Tests for the parts of the TV that don't need a screen or a video player:
// reading folder names, sorting, and deciding what plays next.
//
// Run with:  flutter test

import 'dart:io';
import 'dart:math';

import 'package:crt_tv/src/channel_engine.dart';
import 'package:crt_tv/src/library_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

ChannelEngine engineWith({
  required List<String> programs,
  List<String> commercials = const [],
  bool shuffle = false,
  int perBreak = 0,
  int seed = 1,
}) {
  final engine = ChannelEngine(ChannelState(), random: Random(seed));
  engine.configure(
    programs: programs,
    commercialPool: commercials,
    shuffle: shuffle,
    perBreak: perBreak,
  );
  return engine;
}

List<QueueItem> playN(ChannelEngine engine, int n) => [
  for (var i = 0; i < n; i++) engine.advance()!,
];

void main() {
  group('channel folder names', () {
    test('reads the number and the name', () {
      expect(parseChannelFolder('Channel 3'), (3, ''));
      expect(parseChannelFolder('Channel 5 - Cartoons'), (5, 'Cartoons'));
      expect(parseChannelFolder('channel12 Movies'), (12, 'Movies'));
      expect(parseChannelFolder('Ch 07'), (7, ''));
      expect(parseChannelFolder('4 Sitcoms'), (4, 'Sitcoms'));
      expect(parseChannelFolder('Channel 4 (Saturday Mornings)'), (
        4,
        'Saturday Mornings',
      ));
    });

    test('reads channel folders that have a name but no number', () {
      expect(parseChannelFolder('Channel Gojira'), (null, 'Gojira'));
      expect(parseChannelFolder('Channel Tonami (Anime)'), (
        null,
        'Tonami (Anime)',
      ));
      expect(parseChannelFolder('z Other'), isNull);
      expect(parseChannelFolder('msdownld.tmp'), isNull);
      expect(parseChannelFolder('Channel'), isNull);
    });

    test('ignores folders that are not channels', () {
      expect(parseChannelFolder('Commercials'), isNull);
      expect(parseChannelFolder('Movies'), isNull);
      expect(isCommercialFolder('Commercials'), isTrue);
      expect(isCommercialFolder('commercial'), isTrue);
    });
  });

  test('natural sort puts episode 2 before episode 10', () {
    final names = ['Ep 10.mkv', 'Ep 2.mkv', 'Ep 1.mkv', 'ep 3.mkv'];
    names.sort(naturalCompare);
    expect(names, ['Ep 1.mkv', 'Ep 2.mkv', 'ep 3.mkv', 'Ep 10.mkv']);
  });

  test('titles are cleaned up from file names', () {
    expect(
      titleFromPath('/tv/Channel 3/Show.Name.S01E02.mkv'),
      'Show Name S01E02',
    );
    expect(
      titleFromPath(r'C:\TV\Channel 3\My Movie (1985).mp4'),
      'My Movie (1985)',
    );
  });

  group('schedule', () {
    test('plays in order with commercial breaks between videos', () {
      final engine = engineWith(
        programs: ['a', 'b', 'c'],
        commercials: ['x', 'y', 'z'],
        perBreak: 2,
      );
      final played = playN(engine, 10);
      expect(played.map((q) => q.isCommercial ? 'C' : q.path).toList(), [
        'a',
        'C',
        'C',
        'b',
        'C',
        'C',
        'c',
        'C',
        'C',
        'a',
      ]);
    });

    test('a break never repeats the same commercial', () {
      final engine = engineWith(
        programs: ['a'],
        commercials: ['x', 'y', 'z'],
        perBreak: 3,
        seed: 9,
      );
      for (var round = 0; round < 20; round++) {
        engine.advance(); // the program
        final ads = playN(engine, 3);
        expect(ads.every((q) => q.isCommercial), isTrue);
        expect(ads.map((q) => q.path).toSet().length, 3);
      }
    });

    test('no commercials when breaks are off', () {
      final engine = engineWith(
        programs: ['a', 'b'],
        commercials: ['x'],
        perBreak: 0,
      );
      expect(playN(engine, 4).any((q) => q.isCommercial), isFalse);
    });

    test('a break is never longer than the number of commercials', () {
      final engine = engineWith(
        programs: ['a', 'b'],
        commercials: ['x'],
        perBreak: 3,
      );
      expect(playN(engine, 4).map((q) => q.path).toList(), [
        'a',
        'x',
        'b',
        'x',
      ]);
    });

    test('shuffle plays everything once before repeating', () {
      final programs = [for (var i = 0; i < 12; i++) 'p$i'];
      final engine = engineWith(programs: programs, shuffle: true, seed: 3);
      final firstRound = playN(engine, 12).map((q) => q.path).toSet();
      expect(firstRound.length, 12);
    });

    test('a channel with only commercials plays them back to back', () {
      final engine = engineWith(
        programs: [],
        commercials: ['x', 'y'],
        perBreak: 2,
      );
      expect(playN(engine, 4).every((q) => q.isCommercial), isTrue);
    });

    test('live channels move on while you are away', () async {
      final engine = engineWith(
        programs: ['a', 'b'],
        commercials: ['x', 'y'],
        perBreak: 2,
      );
      engine.advance(); // 'a' starts
      Future<Duration> length(QueueItem q) async => q.isCommercial
          ? const Duration(minutes: 1)
          : const Duration(minutes: 20);
      // 25 minutes later: a (20) + two commercials (2) = 22, so 3 minutes into 'b'.
      await engine.catchUp(const Duration(minutes: 25), length);
      expect(engine.state.current!.path, 'b');
      expect(
        engine.state.positionMs,
        const Duration(minutes: 3).inMilliseconds,
      );
    });

    test('a deleted video is dropped from the schedule', () {
      final engine = engineWith(programs: ['a', 'b', 'c']);
      engine.advance();
      engine.configure(
        programs: ['a', 'c'],
        commercialPool: const [],
        shuffle: false,
        perBreak: 0,
      );
      expect(engine.advance()!.path, 'c');
    });

    test('progress survives saving and loading', () {
      final engine = engineWith(
        programs: ['a', 'b'],
        commercials: ['x'],
        perBreak: 1,
      );
      engine.advance();
      engine.state.positionMs = 1234;
      engine.state.updatedAtMs = 99;
      final copy = ChannelState.fromJson(engine.state.toJson());
      expect(copy.current!.path, 'a');
      expect(copy.positionMs, 1234);
      expect(copy.order, ['a', 'b']);
    });
  });

  test('scans a TV folder into channels', () {
    final root = Directory.systemTemp.createTempSync('tv_test');
    addTearDown(() => root.deleteSync(recursive: true));
    void touch(String relative) {
      final f = File('${root.path}/$relative');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('x');
    }

    touch('Commercials/ad1.mp4');
    touch('Channel 3/Season 1/Ep 2.mkv');
    touch('Channel 3/Season 1/Ep 10.mkv');
    touch('Channel 3/Season 1/notes.txt');
    touch('Channel 3/Commercials/retro ad.avi');
    touch('Channel 5 - Cartoons/toon.mp4');
    touch('Random stuff/ignored.mp4');

    final lib = scanLibrarySync(root.path);
    expect(lib.channels.map((c) => c.number).toList(), [3, 5]);
    final three = lib.channel(3)!;
    expect(three.programs.map(baseName).toList(), ['Ep 2.mkv', 'Ep 10.mkv']);
    expect(three.commercials.map(baseName).toList(), ['retro ad.avi']);
    expect(lib.channel(5)!.name, 'Cartoons');
    expect(lib.channel(5)!.commercials, isEmpty);
    expect(lib.globalCommercials.map(baseName).toList(), ['ad1.mp4']);
  });

  test('channels without a number get the free numbers in name order', () {
    final root = Directory.systemTemp.createTempSync('tv_test');
    addTearDown(() => root.deleteSync(recursive: true));
    void touch(String relative) {
      final f = File('${root.path}/$relative');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('x');
    }

    touch('Channel 2 (Saturday Mornings)/toon.mp4');
    touch('Channel Anime Movies/a.mkv');
    touch('Channel Gojira/g.mkv');
    touch('Channel Robo/r.mkv');
    touch('z Other/ignored.mp4');

    final lib = scanLibrarySync(root.path);
    expect(lib.channels.map((c) => '${c.number} ${c.name}').toList(), [
      '1 Anime Movies',
      '2 Saturday Mornings',
      '3 Gojira',
      '4 Robo',
    ]);
  });
}
