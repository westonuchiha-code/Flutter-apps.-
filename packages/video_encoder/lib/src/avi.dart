import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'writer.dart';

/// Motion-JPEG video + 16-bit PCM sound in an AVI file (OpenDML-free AVI
/// 1.0, so keep it under ~1 GB). Pure Dart: works everywhere.
class AviWriter implements VideoWriter {
  AviWriter._(this.file, this.spec, this._raf, {this.quality = 90});

  static Future<AviWriter> open(
    File file,
    VideoSpec spec, {
    int quality = 90,
  }) async {
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    final w = AviWriter._(file, spec, raf, quality: quality);
    await raf.writeFrom(w._headers(0, 0, 0));
    await raf.writeFrom(_ascii('LIST'));
    w._moviSizeAt = await raf.position();
    await raf.writeFrom(_u32(0));
    await raf.writeFrom(_ascii('movi'));
    w._moviStart = await raf.position() - 4;
    return w;
  }

  @override
  final File file;
  @override
  final VideoSpec spec;
  final int quality;
  final RandomAccessFile _raf;
  late int _moviSizeAt, _moviStart;
  final _index = BytesBuilder();
  int _frames = 0, _audioBytes = 0, _maxChunk = 0;
  bool _done = false;

  @override
  Future<void> addFrame(Uint32List argb) async {
    final image = img.Image(
      width: spec.width,
      height: spec.height,
      numChannels: 3,
    );
    var i = 0;
    for (final p in image) {
      final c = argb[i++];
      p
        ..r = (c >> 16) & 255
        ..g = (c >> 8) & 255
        ..b = c & 255;
    }
    final jpeg = img.encodeJpg(
      image,
      quality: quality,
      chroma: img.JpegChroma.yuv444,
    );
    await _chunk('00dc', jpeg, keyFrame: true);
    _frames++;
  }

  @override
  Future<void> addAudio(Int16List pcm) async {
    if (!spec.audio || pcm.isEmpty) return;
    final bytes = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
    await _chunk('01wb', bytes, keyFrame: true);
    _audioBytes += bytes.length;
  }

  Future<void> _chunk(
    String id,
    Uint8List data, {
    required bool keyFrame,
  }) async {
    final offset = await _raf.position() - _moviStart;
    await _raf.writeFrom(_ascii(id));
    await _raf.writeFrom(_u32(data.length));
    await _raf.writeFrom(data);
    if (data.length.isOdd) await _raf.writeFrom([0]);
    _index
      ..add(_ascii(id))
      ..add(_u32(keyFrame ? 0x10 : 0))
      ..add(_u32(offset))
      ..add(_u32(data.length));
    if (data.length > _maxChunk) _maxChunk = data.length;
  }

  @override
  Future<File> finish() async {
    if (_done) return file;
    _done = true;
    final moviEnd = await _raf.position();
    final idx = _index.takeBytes();
    await _raf.writeFrom(_ascii('idx1'));
    await _raf.writeFrom(_u32(idx.length));
    await _raf.writeFrom(idx);
    final end = await _raf.position();
    // Patch sizes and counts.
    await _raf.setPosition(_moviSizeAt);
    await _raf.writeFrom(_u32(moviEnd - _moviSizeAt - 4));
    await _raf.setPosition(0);
    await _raf.writeFrom(_headers(end - 8, _frames, _audioBytes));
    await _raf.close();
    return file;
  }

  @override
  Future<void> cancel() async {
    if (_done) return;
    _done = true;
    await _raf.close();
    if (await file.exists()) await file.delete();
  }

  /// RIFF header, hdrl list (main header, video and audio streams). Always
  /// the same length so it can be rewritten in place at the end.
  Uint8List _headers(int riffSize, int frames, int audioBytes) {
    final s = spec;
    final b = BytesBuilder();
    final usPerFrame = 1000000 ~/ s.fps;
    final blockAlign = s.channels * 2;
    final strlVideo = BytesBuilder()
      ..add(_ascii('strh'))
      ..add(_u32(56))
      ..add(_ascii('vids'))
      ..add(_ascii('MJPG'))
      ..add(_u32(0)) // flags
      ..add(_u16(0))
      ..add(_u16(0)) // priority, language
      ..add(_u32(0)) // initial frames
      ..add(_u32(1)) // scale
      ..add(_u32(s.fps)) // rate
      ..add(_u32(0)) // start
      ..add(_u32(frames)) // length
      ..add(_u32(_maxChunk)) // suggested buffer
      ..add(_u32(0xFFFFFFFF)) // quality
      ..add(_u32(0)) // sample size
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(s.width))
      ..add(_u16(s.height))
      ..add(_ascii('strf'))
      ..add(_u32(40))
      ..add(_u32(40))
      ..add(_u32(s.width))
      ..add(_u32(s.height))
      ..add(_u16(1))
      ..add(_u16(24))
      ..add(_ascii('MJPG'))
      ..add(_u32(s.width * s.height * 3))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u32(0));
    final strlAudio = BytesBuilder()
      ..add(_ascii('strh'))
      ..add(_u32(56))
      ..add(_ascii('auds'))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(0))
      ..add(_u32(blockAlign)) // scale
      ..add(_u32(s.sampleRate * blockAlign)) // rate (bytes/s)
      ..add(_u32(0))
      ..add(_u32(audioBytes)) // length in bytes / scale... (blocks)
      ..add(_u32(s.sampleRate * blockAlign))
      ..add(_u32(0xFFFFFFFF))
      ..add(_u32(blockAlign))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_ascii('strf'))
      ..add(_u32(16))
      ..add(_u16(1)) // PCM
      ..add(_u16(s.channels))
      ..add(_u32(s.sampleRate))
      ..add(_u32(s.sampleRate * blockAlign))
      ..add(_u16(blockAlign))
      ..add(_u16(16));
    final v = strlVideo.takeBytes();
    final a = strlAudio.takeBytes();
    final hdrl = BytesBuilder()
      ..add(_ascii('hdrl'))
      ..add(_ascii('avih'))
      ..add(_u32(56))
      ..add(_u32(usPerFrame))
      ..add(_u32(0)) // max bytes/s
      ..add(_u32(0))
      ..add(_u32(0x10)) // AVIF_HASINDEX
      ..add(_u32(frames))
      ..add(_u32(0))
      ..add(_u32(s.audio ? 2 : 1))
      ..add(_u32(_maxChunk))
      ..add(_u32(s.width))
      ..add(_u32(s.height))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_ascii('LIST'))
      ..add(_u32(v.length + 4))
      ..add(_ascii('strl'))
      ..add(v);
    if (s.audio) {
      hdrl
        ..add(_ascii('LIST'))
        ..add(_u32(a.length + 4))
        ..add(_ascii('strl'))
        ..add(a);
    }
    final h = hdrl.takeBytes();
    b
      ..add(_ascii('RIFF'))
      ..add(_u32(riffSize))
      ..add(_ascii('AVI '))
      ..add(_ascii('LIST'))
      ..add(_u32(h.length))
      ..add(h);
    return b.takeBytes();
  }
}

Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);
Uint8List _u32(int v) => (ByteData(
  4,
)..setUint32(0, v & 0xFFFFFFFF, Endian.little)).buffer.asUint8List();
Uint8List _u16(int v) =>
    (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List();
