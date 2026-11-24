import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_kit/audio_kit.dart' show buildWav, WavFormat;
import 'package:lofi_video/src/media.dart';
import 'package:pixel_kit/pixel_kit.dart' as pk;
import 'package:video_kit/video_kit.dart';

/// A 2-second Chip Cam clip (ZX Spectrum test card) with a 440 Hz beep.
Future<Uint8List> makeClip(Directory dir) async {
  final w = await ClipWriter.create(File('${dir.path}/c.$clipExtension'));
  final zx = ZxSpectrum();
  for (var i = 0; i < 30; i++) {
    await w.addFrame(runEffect(zx, testCard(i / 15), i / 15), i / 15);
  }
  final sound = Int16List(48000 * 2);
  for (var i = 0; i < sound.length; i++) {
    sound[i] = (math.sin(i * 2 * math.pi * 440 / 48000) * 12000).round();
  }
  final f = await w.finish(sound: sound, sampleRate: 48000, length: 2);
  return f.readAsBytes();
}

/// A 16×16 two-frame Pixel Forge sprite.
Uint8List makeSprite() {
  final s = pk.Sprite.blank(16, 16, background: 0xFF1D2B53)..addFrame();
  s.cel(0, 0).fillRange(0, 64, 0xFFFF004D);
  s.cel(1, 0).fillRange(128, 192, 0xFF00E436);
  return utf8.encode(jsonEncode(s.toJson()));
}

/// 4 s of 220 Hz at 22050 Hz mono.
Uint8List makeMusic() {
  final pcm = Int16List(22050 * 4);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (math.sin(i * 2 * math.pi * 220 / 22050) * 9000).round();
  }
  return buildWav(const WavFormat(sampleRate: 22050), pcm.buffer.asUint8List());
}

Map<String, Media> decodeAll(Map<String, (String, Uint8List)> files) => {
  for (final e in files.entries) e.key: decodeMedia(e.value.$1, e.value.$2),
};
