// Pokémon pictures for Pokéville: PokeAPI's sprite set
// (github.com/PokeAPI/sprites, 96×96, every species, shiny too), the same
// the PC uses. Downloaded the first time one is needed, two at a time, and
// kept in the cache folder the host passes in (<species>.png, <species>s.png
// for shiny), so it works offline with whatever is cached. A picture that
// can't be had is drawn as a ball by the screen; nothing here throws.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// Gets a URL's bytes, or null. Injected in tests (never the network there).
typedef SpriteFetcher = Future<Uint8List?> Function(Uri url);

/// Downloads with dart:io's HttpClient (15 s to connect, 30 s in all).
SpriteFetcher httpFetcher() {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'pokeville';
  return (Uri url) async {
    try {
      final req = await client.getUrl(url);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final b = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        b.add(chunk);
      }
      return b.takeBytes();
    } on Object {
      return null;
    }
  };
}

class PokeSprites extends ChangeNotifier {
  PokeSprites(this.cacheDir, {SpriteFetcher? fetcher, this.parallel = 2})
    : _fetch = fetcher ?? httpFetcher();

  static const base =
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/';

  /// The cache folder (made when first needed).
  final String cacheDir;
  final int parallel;
  final SpriteFetcher _fetch;

  final _images = <String, ui.Image?>{}; // null = can't be had this run
  final _queue = <String>[];
  final _busy = <String, Future<void>>{};
  bool _disposed = false;
  ui.Image? _ball;
  bool _ballAsked = false;

  static String key(int species, bool shiny) =>
      shiny ? '${species}s' : '$species';

  static Uri url(int species, bool shiny) =>
      Uri.parse('$base${shiny ? 'shiny/' : ''}$species.png');

  /// The picture if it's here; else null, and it's fetched (from the cache
  /// folder or the internet) and listeners hear when it arrives.
  ui.Image? image(int species, bool shiny) {
    if (species <= 0) return null;
    final k = key(species, shiny);
    if (_images.containsKey(k)) return _images[k];
    if (!_queue.contains(k) && !_busy.containsKey(k)) {
      _queue.add(k);
      scheduleMicrotask(_pump);
    }
    return null;
  }

  /// True once a picture was tried and couldn't be had.
  bool failed(int species, bool shiny) {
    final k = key(species, shiny);
    return _images.containsKey(k) && _images[k] == null;
  }

  /// Loads these now (shots, or warming the cache).
  Future<void> preload(Iterable<(int, bool)> which) async {
    final waits = <Future<void>>[];
    for (final (s, sh) in which) {
      final k = key(s, sh);
      if (s <= 0 || _images.containsKey(k)) continue;
      _queue.remove(k);
      waits.add(_busy[k] ??= _load(k));
    }
    await Future.wait(waits);
    await ball();
  }

  /// The Poké Ball item sprite (drawn where a picture is missing).
  ui.Image? get ballImage {
    if (!_ballAsked) unawaited(ball());
    return _ball;
  }

  Future<ui.Image?> ball() async {
    if (_ballAsked) return _ball;
    _ballAsked = true;
    try {
      final data = await rootBundle.load(
        'packages/pokeville/assets/poke-ball.png',
      );
      _ball = await _decode(data.buffer.asUint8List());
      if (!_disposed) notifyListeners();
    } on Object {
      _ball = null;
    }
    return _ball;
  }

  void _pump() {
    while (!_disposed && _busy.length < parallel && _queue.isNotEmpty) {
      final k = _queue.removeAt(0);
      _busy[k] = _load(k);
    }
  }

  Future<void> _load(String k) async {
    ui.Image? img;
    try {
      final file = File(p.join(cacheDir, '$k.png'));
      if (await file.exists()) img = await _decode(await file.readAsBytes());
      if (img == null) {
        final shiny = k.endsWith('s');
        final species = int.parse(shiny ? k.substring(0, k.length - 1) : k);
        final bytes = await _fetch(url(species, shiny));
        if (bytes != null) img = await _decode(bytes);
        if (img != null && bytes != null) {
          await _keep(file, bytes);
        }
      }
    } on Object {
      img = null;
    }
    _busy.remove(k);
    if (_disposed) {
      img?.dispose();
      return;
    }
    _images[k]?.dispose();
    _images[k] = img;
    notifyListeners();
    _pump();
  }

  static Future<void> _keep(File file, Uint8List bytes) async {
    final part = File('${file.path}.part');
    try {
      await file.parent.create(recursive: true);
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
    } on Object {
      try {
        if (await part.exists()) await part.delete();
      } on Object {
        // a stray .part is replaced next time
      }
    }
  }

  static Future<ui.Image?> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final img in _images.values) {
      img?.dispose();
    }
    _images.clear();
    _ball?.dispose();
    _ball = null;
    super.dispose();
  }
}
