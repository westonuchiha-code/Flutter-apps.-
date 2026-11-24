import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'frame.dart';

/// Chip Cam video clips: frames exactly as they were shown (each machine's
/// own resolution), with their times, plus optional mono 16-bit sound.
///
/// File layout: "LFCLIP01", frame and sound blobs, the JSON index, the
/// index length (u32 LE), "LFCLIPIX". Frames are PNG when they have 256
/// colours or fewer (pixel-exact), JPEG otherwise (noisy signal effects).
class ClipFrameInfo {
  const ClipFrameInfo(
    this.time,
    this.width,
    this.height,
    this.format,
    this.offset,
    this.length,
  );
  final double time;
  final int width, height;
  final String format;
  final int offset, length;

  Map<String, Object?> toJson() => {
    't': (time * 1000).round(),
    'w': width,
    'h': height,
    'f': format,
    'o': offset,
    'l': length,
  };

  factory ClipFrameInfo.fromJson(Map j) => ClipFrameInfo(
    (j['t'] as num) / 1000,
    (j['w'] as num).toInt(),
    (j['h'] as num).toInt(),
    j['f'] as String,
    (j['o'] as num).toInt(),
    (j['l'] as num).toInt(),
  );
}

const clipKind = 'video_clip';
const clipExtension = 'lfclip';
const _head = 'LFCLIP01', _tail = 'LFCLIPIX';

/// Encodes one frame for a clip: (format, bytes).
(String, Uint8List) encodeClipFrame(VideoFrame f) {
  final image = img.Image(width: f.width, height: f.height, numChannels: 3);
  final colors = <int>{};
  var i = 0;
  for (final p in image) {
    final c = f.pixels[i++];
    if (colors.length <= 256) colors.add(c);
    p
      ..r = (c >> 16) & 255
      ..g = (c >> 8) & 255
      ..b = c & 255;
  }
  if (colors.length <= 256) return ('png', img.encodePng(image, level: 6));
  return ('jpg', img.encodeJpg(image, quality: 90));
}

VideoFrame decodeClipFrame(Uint8List bytes) {
  final image = img.decodeImage(bytes)!;
  final out = VideoFrame(image.width, image.height);
  var i = 0;
  for (final p in image) {
    out.pixels[i++] =
        0xFF000000 | (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
  }
  return out;
}

/// Writes a clip to a file as it is recorded.
class ClipWriter {
  ClipWriter._(this.file, this._raf);

  static Future<ClipWriter> create(File file) async {
    final raf = await file.open(mode: FileMode.write);
    await raf.writeFrom(ascii.encode(_head));
    return ClipWriter._(file, raf);
  }

  final File file;
  final RandomAccessFile _raf;
  final frames = <ClipFrameInfo>[];

  double get duration => frames.isEmpty ? 0 : frames.last.time;

  /// Adds a frame shown at [time] seconds (from the start of the clip).
  Future<void> addFrame(VideoFrame f, double time) async {
    final (format, bytes) = encodeClipFrame(f);
    await addEncoded(format, bytes, f.width, f.height, time);
  }

  Future<void> addEncoded(
    String format,
    Uint8List bytes,
    int w,
    int h,
    double time,
  ) async {
    final offset = await _raf.position();
    await _raf.writeFrom(bytes);
    frames.add(ClipFrameInfo(time, w, h, format, offset, bytes.length));
  }

  /// Finishes the file, with optional mono 16-bit sound.
  Future<File> finish({
    Int16List? sound,
    int sampleRate = 48000,
    double? length,
    Map<String, Object?> extra = const {},
  }) async {
    Map<String, Object?>? audio;
    if (sound != null && sound.isNotEmpty) {
      final offset = await _raf.position();
      final bytes = sound.buffer.asUint8List(
        sound.offsetInBytes,
        sound.lengthInBytes,
      );
      await _raf.writeFrom(bytes);
      audio = {
        'rate': sampleRate,
        'channels': 1,
        'o': offset,
        'l': bytes.length,
      };
    }
    final index = utf8.encode(
      jsonEncode({
        'kind': clipKind,
        'version': 1,
        'length': length ?? duration,
        'frames': [for (final f in frames) f.toJson()],
        'audio': ?audio,
        ...extra,
      }),
    );
    await _raf.writeFrom(index);
    await _raf.writeFrom(
      (ByteData(
        4,
      )..setUint32(0, index.length, Endian.little)).buffer.asUint8List(),
    );
    await _raf.writeFrom(ascii.encode(_tail));
    await _raf.close();
    return file;
  }

  Future<void> cancel() async {
    await _raf.close();
    if (await file.exists()) await file.delete();
  }
}

/// A clip read into memory.
class VideoClip {
  VideoClip._(
    this.bytes,
    this.frames,
    this.length,
    this.sampleRate,
    this._audioOffset,
    this._audioLength,
    this.extra,
  );

  factory VideoClip.fromBytes(Uint8List bytes) {
    if (bytes.length < 20 ||
        ascii.decode(bytes.sublist(0, 8), allowInvalid: true) != _head ||
        ascii.decode(bytes.sublist(bytes.length - 8), allowInvalid: true) !=
            _tail) {
      throw const FormatException('Not a Chip Cam clip');
    }
    final n = ByteData.sublistView(bytes)
        .getUint32(bytes.length - 12, Endian.little);
    final j = jsonDecode(
      utf8.decode(bytes.sublist(bytes.length - 12 - n, bytes.length - 12)),
    ) as Map;
    if (j['kind'] != clipKind) {
      throw const FormatException('Not a Chip Cam clip');
    }
    final frames = [
      for (final f in j['frames'] as List) ClipFrameInfo.fromJson(f as Map),
    ];
    final audio = j['audio'] as Map?;
    return VideoClip._(
      bytes,
      frames,
      ((j['length'] as num?) ?? (frames.isEmpty ? 0 : frames.last.time))
          .toDouble(),
      (audio?['rate'] as num?)?.toInt() ?? 0,
      (audio?['o'] as num?)?.toInt() ?? 0,
      (audio?['l'] as num?)?.toInt() ?? 0,
      {
        for (final e in j.entries)
          if (!const {
            'kind',
            'version',
            'length',
            'frames',
            'audio',
          }.contains(e.key))
            e.key as String: e.value,
      },
    );
  }

  final Uint8List bytes;
  final List<ClipFrameInfo> frames;

  /// Seconds.
  final double length;
  final int sampleRate;
  final int _audioOffset, _audioLength;
  final Map<String, Object?> extra;

  bool get hasSound => _audioLength > 0;

  /// Mono 16-bit samples at [sampleRate].
  Int16List get sound {
    if (!hasSound) return Int16List(0);
    final copy = Uint8List.fromList(
      bytes.sublist(_audioOffset, _audioOffset + _audioLength),
    );
    return copy.buffer.asInt16List(0, copy.length ~/ 2);
  }

  /// The frame showing at [time] seconds (the last one whose time ≤ [time]).
  int indexAt(double time) {
    var lo = 0, hi = frames.length - 1;
    if (hi < 0) return -1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (frames[mid].time <= time) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  final _cache = <int, VideoFrame>{};

  /// Decoded frame [i] (the last few are kept).
  VideoFrame frame(int i) {
    final hit = _cache[i];
    if (hit != null) return hit;
    final f = frames[i];
    final out = decodeClipFrame(
      Uint8List.sublistView(bytes, f.offset, f.offset + f.length),
    );
    if (_cache.length > 4) _cache.remove(_cache.keys.first);
    return _cache[i] = out;
  }

  VideoFrame frameAt(double time) =>
      frame(indexAt(time).clamp(0, frames.length - 1));
}
