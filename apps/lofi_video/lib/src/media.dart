import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_kit/audio_kit.dart' show parseWav, sampleAt;
import 'package:image/image.dart' as img;
import 'package:pixel_kit/pixel_kit.dart' as pk;
import 'package:video_kit/video_kit.dart';

/// The sample rate everything is mixed at.
const mixRate = 44100;

/// Something a scene shows or plays, decoded.
sealed class Media {
  const Media();
}

class ClipMedia extends Media {
  const ClipMedia(this.clip);
  final VideoClip clip;
}

class StillMedia extends Media {
  const StillMedia(this.frame);
  final VideoFrame frame;
}

/// An animation (Pixel Forge sprite or animated GIF).
class AnimMedia extends Media {
  AnimMedia(this.frames, this.durations)
    : total = durations.fold(0.0, (a, b) => a + b);
  final List<VideoFrame> frames;

  /// Seconds each frame shows.
  final List<double> durations;
  final double total;

  VideoFrame at(double t) {
    if (frames.length == 1 || total <= 0) {
      return frames.first;
    }
    var x = t % total;
    for (var i = 0; i < frames.length; i++) {
      if (x < durations[i]) {
        return frames[i];
      }
      x -= durations[i];
    }
    return frames.last;
  }
}

/// Stereo sound at [mixRate].
class SoundMedia extends Media {
  const SoundMedia(this.left, this.right);
  final Float32List left, right;
  double get seconds => left.length / mixRate;
}

const pictureExtensions = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'};

/// Decodes an asset's bytes by its extension. Big pictures are shrunk to at
/// most [maxSide] (the canvas is small anyway).
Media decodeMedia(String extension, Uint8List bytes, {int maxSide = 640}) {
  final ext = extension.toLowerCase();
  if (ext == clipExtension) {
    return ClipMedia(VideoClip.fromBytes(bytes));
  }
  if (ext == 'wav') {
    return decodeWavSound(bytes);
  }
  if (ext == 'json') {
    final s = pk.Sprite.fromJson(jsonDecode(utf8.decode(bytes)));
    return AnimMedia(
      [
        for (var f = 0; f < s.frames.length; f++)
          VideoFrame(s.width, s.height, _opaque(s.flatten(f))),
      ],
      [for (final f in s.frames) f.durationMs / 1000],
    );
  }
  if (pictureExtensions.contains(ext)) {
    final decoded = ext == 'gif'
        ? img.decodeGif(bytes)
        : img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Could not read the picture');
    }
    var image = img.bakeOrientation(decoded);
    final long = math.max(image.width, image.height);
    if (long > maxSide && image.numFrames == 1) {
      image = img.copyResize(
        image,
        width: image.width * maxSide ~/ long,
        height: image.height * maxSide ~/ long,
        interpolation: img.Interpolation.average,
      );
    }
    if (image.numFrames > 1) {
      return AnimMedia(
        [for (final f in image.frames) _toFrame(f)],
        [for (final f in image.frames) math.max(0.02, f.frameDuration / 1000)],
      );
    }
    return StillMedia(_toFrame(image));
  }
  throw FormatException('Lo-Fi Video Maker cannot use .$ext files');
}

Uint32List _opaque(Uint32List px) {
  // Transparent sprite pixels show the scene background (black).
  for (var i = 0; i < px.length; i++) {
    if ((px[i] >>> 24) < 128) {
      px[i] = 0xFF000000;
    }
  }
  return px;
}

VideoFrame _toFrame(img.Image image) {
  final rgba = image.convert(numChannels: 4, format: img.Format.uint8);
  final out = VideoFrame(rgba.width, rgba.height);
  var i = 0;
  for (final p in rgba) {
    out.pixels[i++] = p.a < 128
        ? 0xFF000000
        : 0xFF000000 | (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
  }
  return out;
}

/// WAV → stereo floats at [mixRate] (linear resampling).
SoundMedia decodeWavSound(Uint8List bytes) {
  final info = parseWav(bytes, totalLength: bytes.length);
  final f = info.format;
  final bd = ByteData.sublistView(bytes);
  final frames = info.frames;
  final step = f.sampleRate / mixRate;
  final n = (frames / step).floor();
  final l = Float32List(n), r = Float32List(n);
  double at(int frame, int ch) => sampleAt(
    bd,
    info.dataOffset +
        frame * f.frameBytes +
        math.min(ch, f.channels - 1) * f.bytesPerSample,
    f,
  );
  for (var i = 0; i < n; i++) {
    final pos = i * step;
    final a = pos.floor(), b = math.min(a + 1, frames - 1);
    final t = pos - a;
    l[i] = at(a, 0) * (1 - t) + at(b, 0) * t;
    r[i] = at(a, 1) * (1 - t) + at(b, 1) * t;
  }
  return SoundMedia(l, r);
}
