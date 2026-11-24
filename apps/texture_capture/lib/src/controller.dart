import 'dart:async';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart' show runInBackground;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'engine/formats.dart';
import 'engine/pic.dart';
import 'engine/pipeline.dart';
import 'engine/warp.dart';

/// Decodes a photo (any common format), turned upright and shrunk to at
/// most [maxSide] pixels.
Pic? decodePhoto(Uint8List bytes, {int maxSide = 2048}) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  final long = image.width > image.height ? image.width : image.height;
  if (long > maxSide) {
    image = img.copyResize(
      image,
      width: image.width * maxSide ~/ long,
      height: image.height * maxSide ~/ long,
      interpolation: img.Interpolation.average,
    );
  }
  final rgba = image.convert(numChannels: 4, format: img.Format.uint8);
  final out = Pic(rgba.width, rgba.height);
  for (final p in rgba) {
    out.px[p.y * rgba.width + p.x] = rgb(p.r.toInt(), p.g.toInt(), p.b.toInt());
  }
  return out;
}

Uint8List picToPng(Pic p) {
  final image = img.Image(width: p.width, height: p.height, numChannels: 3);
  for (final px in image) {
    final c = p.px[px.y * p.width + px.x];
    px
      ..r = rOf(c)
      ..g = gOf(c)
      ..b = bOf(c);
  }
  return img.encodePng(image);
}

Future<ui.Image> picToImage(Pic p) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    p.bgraBytes,
    p.width,
    p.height,
    ui.PixelFormat.bgra8888,
    c.complete,
  );
  return c.future;
}

class TextureController extends ChangeNotifier {
  TextureController({this.useIsolates = true});

  /// Off in tests that run without real isolates.
  final bool useIsolates;

  String name = 'Texture';
  Pic? photo;
  ui.Image? photoImage;
  MasterSettings? settings;

  Pic? master;
  ui.Image? masterImage;
  List<Advice> advice = const [];
  bool workingMaster = false;

  ConsolePreset console = consoles.first;
  late FormatChoice format = console.formats.first;
  late int size = format.defaultSize;
  bool dither = false;
  Pic? consolePic;
  ui.Image? consoleImage;
  bool workingConsole = false;

  /// Show textures repeated 3×3.
  bool tiled = true;

  int _masterGen = 0, _consoleGen = 0;
  bool _disposed = false;

  Future<R> _run<A, R>(R Function(A) work, A arg) =>
      useIsolates ? runInBackground(work, arg) : Future.value(work(arg));

  List<Pt> fullCorners(Pic p) => [
    (x: 0, y: 0),
    (x: p.width.toDouble(), y: 0),
    (x: p.width.toDouble(), y: p.height.toDouble()),
    (x: 0, y: p.height.toDouble()),
  ];

  /// Opens a photo (encoded bytes). Returns false if it can't be read.
  Future<bool> openBytes(Uint8List bytes, {String name = 'Texture'}) async {
    final p = await _run(_decode, bytes);
    if (p == null) return false;
    await setPhoto(p, name: name);
    return true;
  }

  Future<void> setPhoto(Pic p, {String name = 'Texture'}) async {
    this.name = name;
    photo = p;
    final image = await picToImage(p);
    photoImage?.dispose();
    photoImage = image;
    final corners = fullCorners(p);
    settings = MasterSettings(
      corners: corners,
      size: suggestedSize(quadSide(corners)),
    );
    notifyListeners();
    await rebuild();
  }

  /// Live corner dragging (no rebuild until [rebuild]).
  void moveCorner(int i, Pt to) {
    final s = settings, p = photo;
    if (s == null || p == null) return;
    final c = List<Pt>.of(s.corners);
    c[i] = (
      x: to.x.clamp(0, p.width.toDouble()),
      y: to.y.clamp(0, p.height.toDouble()),
    );
    settings = s.copyWith(corners: c);
    notifyListeners();
  }

  Future<void> resetCorners() =>
      _change((s) => s.copyWith(corners: fullCorners(photo!)));

  /// Turns the texture a quarter clockwise.
  Future<void> rotate() => _change((s) {
    final c = s.corners;
    return s.copyWith(corners: [c[3], c[0], c[1], c[2]]);
  });

  Future<void> setMasterSize(int v) => _change((s) => s.copyWith(size: v));
  Future<void> setLighting(double v) => _change((s) => s.copyWith(lighting: v));
  Future<void> setSeamless(bool v) => _change((s) => s.copyWith(seamless: v));
  Future<void> setBlend(double v) => _change((s) => s.copyWith(blend: v));

  /// Slider dragging: show the value, build on release.
  void preview(MasterSettings Function(MasterSettings) f) {
    if (settings == null) return;
    settings = f(settings!);
    notifyListeners();
  }

  Future<void> _change(MasterSettings Function(MasterSettings) f) async {
    if (settings == null) return;
    settings = f(settings!);
    notifyListeners();
    await rebuild();
  }

  /// Rebuilds the master (and then the console version).
  Future<void> rebuild() async {
    final p = photo, s = settings;
    if (p == null || s == null) return;
    final gen = ++_masterGen;
    workingMaster = true;
    notifyListeners();
    final r = await _run(_master, (p, s));
    if (gen != _masterGen || _disposed) return;
    final image = await picToImage(r.master);
    if (gen != _masterGen || _disposed) {
      image.dispose();
      return;
    }
    master = r.master;
    advice = r.advice;
    masterImage?.dispose();
    masterImage = image;
    workingMaster = false;
    notifyListeners();
    await _rebuildConsole();
  }

  Future<void> selectConsole(ConsolePreset c) {
    console = c;
    format = c.formats.first;
    size = format.defaultSize;
    return _rebuildConsole();
  }

  Future<void> selectFormat(FormatChoice f) {
    format = f;
    if (!f.sizes.contains(size)) size = f.defaultSize;
    return _rebuildConsole();
  }

  Future<void> setSize(int v) {
    size = v;
    return _rebuildConsole();
  }

  Future<void> setDither(bool v) {
    dither = v;
    return _rebuildConsole();
  }

  void setTiled(bool v) {
    tiled = v;
    notifyListeners();
  }

  int get consoleBytes => format.format.bytesFor(size, size);

  Future<void> _rebuildConsole() async {
    final m = master;
    if (m == null) {
      notifyListeners();
      return;
    }
    final gen = ++_consoleGen;
    workingConsole = true;
    notifyListeners();
    final f = format.format, s = size, d = dither && f.canDither;
    final out = await _run(_console, (m, f, s, d));
    if (gen != _consoleGen || _disposed) return;
    final image = await picToImage(out);
    if (gen != _consoleGen || _disposed) {
      image.dispose();
      return;
    }
    consolePic = out;
    consoleImage?.dispose();
    consoleImage = image;
    workingConsole = false;
    notifyListeners();
  }

  String get consoleLabel => '${console.name} ${format.format.label} $size';

  Future<Uint8List> masterPng() {
    final m = master!;
    return _run(picToPng, m);
  }

  Future<Uint8List> consolePng() {
    final c = consolePic!;
    return _run(picToPng, c);
  }

  @override
  void dispose() {
    _disposed = true;
    photoImage?.dispose();
    masterImage?.dispose();
    consoleImage?.dispose();
    super.dispose();
  }
}

Pic? _decode(Uint8List bytes) => decodePhoto(bytes);
MasterResult _master((Pic, MasterSettings) a) => buildMaster(a.$1, a.$2);
Pic _console((Pic, TexFormat, int, bool) a) =>
    buildConsole(a.$1, a.$2, a.$3, dither: a.$4);
