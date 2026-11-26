// Sprites: PokeAPI URLs, fetched once and cached on disk, offline from the
// cache, failures are a null picture (never a throw). No network: the
// fetcher is fake.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pokeville/pokeville.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pokeville_sprites'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('URLs as the PC uses', () {
    expect(
      PokeSprites.url(52, false).toString(),
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/52.png',
    );
    expect(
      PokeSprites.url(130, true).toString(),
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/130.png',
    );
    expect(PokeSprites.key(130, true), '130s');
  });

  test(
    'downloaded once, cached on disk, then offline from the cache',
    () async {
      final asked = <Uri>[];
      final s = PokeSprites(
        temp.path,
        fetcher: (u) {
          asked.add(u);
          return fakeFetcher(u);
        },
      );
      expect(s.image(52, false), isNull, reason: 'not here yet: fetched');
      await s.preload([(52, false), (130, true)]);
      expect(s.image(52, false), isNotNull);
      expect(s.image(130, true)!.width, 96);
      expect(File(p.join(temp.path, '52.png')).existsSync(), isTrue);
      expect(File(p.join(temp.path, '130s.png')).existsSync(), isTrue);
      expect(asked, hasLength(2));
      s.dispose();
      final offline = PokeSprites(
        temp.path,
        fetcher: (u) async {
          asked.add(u);
          return null;
        },
      );
      await offline.preload([(52, false), (25, false)]);
      expect(offline.image(52, false), isNotNull, reason: 'from the cache');
      expect(offline.image(25, false), isNull);
      expect(offline.failed(25, false), isTrue);
      expect(
        asked,
        hasLength(3),
        reason: 'only the uncached one was asked for',
      );
      offline.dispose();
    },
  );

  test(
    'bad bytes or a throwing fetcher: no picture, no crash, nothing cached',
    () async {
      final s = PokeSprites(
        temp.path,
        fetcher: (u) async {
          if (u.path.endsWith('/1.png')) throw const SocketException('offline');
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      await s.preload([(1, false), (2, false)]);
      expect(s.failed(1, false) && s.failed(2, false), isTrue);
      expect(temp.listSync(), isEmpty);
      expect(s.image(0, false), isNull);
      s.dispose();
    },
  );

  test(
    'a picture asked for while drawing arrives and tells listeners',
    () async {
      final s = PokeSprites(temp.path, fetcher: fakeFetcher);
      var heard = 0;
      s.addListener(() => heard++);
      s.image(25, false);
      s.image(25, false); // asked twice, fetched once
      for (var i = 0; i < 50 && s.image(25, false) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(s.image(25, false), isNotNull);
      expect(heard, greaterThan(0));
      s.dispose();
    },
  );
}
