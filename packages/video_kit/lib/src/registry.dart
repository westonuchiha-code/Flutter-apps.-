import 'dart:math' as math;

import 'effect.dart';
import 'effects/digital.dart';
import 'effects/machines.dart';
import 'effects/signals.dart';
import 'effects/strange.dart';
import 'frame.dart';

/// Every effect, in the order the app shows them.
List<VideoEffect> allEffects() => [
  ZxSpectrum(),
  C64Multicolor(),
  Atari2600(),
  GameBoyCamera(),
  HandheldLcd(),
  Teletext(),
  ArtifactColor(),
  NtscComposite(),
  Vhs(),
  BadAntenna(),
  SyncLoss(),
  Interlace(),
  RuttEtra(),
  VideoFeedback(),
  SlitScan(),
  SlowScanTv(),
  Pxl2000(),
  JpegBlocks(),
  Datamosh(),
];

/// Runs [effect] on a camera frame: resize to the machine's resolution, then
/// process.
VideoFrame runEffect(VideoEffect effect, VideoFrame camera, double time) {
  final (w, h) = effect.inputSize(camera.width, camera.height);
  return effect.process(camera.resized(w, h), time);
}

/// SMPTE-style colour bars with a moving bar, for when there is no camera.
VideoFrame testCard(double time, {int width = 320, int height = 240}) {
  final f = VideoFrame(width, height);
  const bars = [
    0xFFC0C0C0,
    0xFFC0C000,
    0xFF00C0C0,
    0xFF00C000,
    0xFFC000C0,
    0xFFC00000,
    0xFF0000C0,
  ];
  final split = (height * 0.67).round(), split2 = (height * 0.75).round();
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final bar = x * 7 ~/ width;
      int c;
      if (y < split) {
        c = bars[bar];
      } else if (y < split2) {
        c = bar.isEven ? bars[6 - bar] : 0xFF101010;
      } else {
        // Grey ramp and a moving white block.
        final v = (x * 255 / width).round();
        c = grey(v);
      }
      f.pixels[y * width + x] = c;
    }
  }
  final bx = ((math.sin(time * 1.3) * 0.5 + 0.5) * (width - 40)).round();
  for (var y = (height * 0.3).round(); y < (height * 0.45).round(); y++) {
    for (var x = bx; x < bx + 40; x++) {
      f.pixels[y * width + x] = 0xFFFFFFFF;
    }
  }
  return f;
}
