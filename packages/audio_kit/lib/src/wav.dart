import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Sample layout of a WAV file.
class WavFormat {
  const WavFormat({
    required this.sampleRate,
    this.channels = 1,
    this.bitsPerSample = 16,
    this.isFloat = false,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final bool isFloat;

  int get bytesPerSample => bitsPerSample ~/ 8;
  int get frameBytes => bytesPerSample * channels;

  @override
  String toString() =>
      '$sampleRate Hz, ${channels == 1 ? 'mono' : '$channels ch'}, '
      '${isFloat ? '32-bit float' : '$bitsPerSample-bit'}';
}

class WavException implements Exception {
  WavException(this.message);
  final String message;
  @override
  String toString() => 'WAV: $message';
}

/// Where the samples are inside a WAV file.
class WavInfo {
  const WavInfo(this.format, this.dataOffset, this.dataLength);

  final WavFormat format;
  final int dataOffset;
  final int dataLength;

  int get frames => dataLength ~/ format.frameBytes;
  Duration get duration =>
      Duration(microseconds: frames * 1000000 ~/ format.sampleRate);
  double get seconds => frames / format.sampleRate;
}

int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
String _tag(Uint8List b, int o) => String.fromCharCodes(b, o, o + 4);

/// Parses the header. [head] must reach the start of the data chunk;
/// [totalLength] (file size) fixes a data size left at 0 or too big
/// (e.g. after a crash mid-recording).
WavInfo parseWav(Uint8List head, {int? totalLength}) {
  if (head.length < 12 || _tag(head, 0) != 'RIFF' || _tag(head, 8) != 'WAVE') {
    throw WavException('not a WAV file');
  }
  WavFormat? format;
  var o = 12;
  while (o + 8 <= head.length) {
    final id = _tag(head, o);
    final size = _u32(head, o + 4);
    final body = o + 8;
    if (id == 'fmt ') {
      if (body + 16 > head.length) break;
      var tag = _u16(head, body);
      if (tag == 0xFFFE && size >= 40 && body + 26 <= head.length) {
        tag = _u16(head, body + 24); // WAVE_FORMAT_EXTENSIBLE sub-format
      }
      final bits = _u16(head, body + 14);
      if ((tag != 1 && tag != 3) ||
          ![8, 16, 24, 32].contains(bits) ||
          (tag == 3 && bits != 32)) {
        throw WavException('unsupported sample format');
      }
      format = WavFormat(
        sampleRate: _u32(head, body + 4),
        channels: math.max(1, _u16(head, body + 2)),
        bitsPerSample: bits,
        isFloat: tag == 3,
      );
    } else if (id == 'data') {
      if (format == null) throw WavException('data before format');
      final available = (totalLength ?? head.length) - body;
      final length = size == 0 || size > available ? available : size;
      return WavInfo(format, body, length - length % format.frameBytes);
    }
    o = body + size + (size & 1);
  }
  throw WavException('no audio data found');
}

/// A 44-byte header for [dataLength] bytes of samples.
Uint8List wavHeader(WavFormat f, int dataLength) {
  final b = ByteData(44);
  void tag(int o, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataLength, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, f.isFloat ? 3 : 1, Endian.little);
  b.setUint16(22, f.channels, Endian.little);
  b.setUint32(24, f.sampleRate, Endian.little);
  b.setUint32(28, f.sampleRate * f.frameBytes, Endian.little);
  b.setUint16(32, f.frameBytes, Endian.little);
  b.setUint16(34, f.bitsPerSample, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataLength, Endian.little);
  return b.buffer.asUint8List();
}

Uint8List buildWav(WavFormat f, Uint8List data) => Uint8List(44 + data.length)
  ..setRange(0, 44, wavHeader(f, data.length))
  ..setRange(44, 44 + data.length, data);

/// Converts float samples (-1..1) to 16-bit little-endian PCM.
Uint8List floatToPcm16(Float32List samples) {
  final out = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    final v = samples[i];
    out[i] = (v >= 1 ? 32767 : (v <= -1 ? -32768 : (v * 32767).round()));
  }
  return out.buffer.asUint8List();
}

/// Absolute peak per bucket of [framesPerPeak] frames (all channels).
Float32List pcmPeaks(Uint8List data, WavFormat f, int framesPerPeak) {
  final bd = ByteData.sublistView(data);
  final frames = data.length ~/ f.frameBytes;
  final out = Float32List((frames / framesPerPeak).ceil());
  for (var i = 0; i < frames; i++) {
    final base = i * f.frameBytes;
    var m = 0.0;
    for (var c = 0; c < f.channels; c++) {
      final v = sampleAt(bd, base + c * f.bytesPerSample, f).abs();
      if (v > m) m = v;
    }
    final k = i ~/ framesPerPeak;
    if (m > out[k]) out[k] = m;
  }
  return out;
}

/// One sample as -1..1.
double sampleAt(ByteData bd, int o, WavFormat f) {
  if (f.isFloat) return bd.getFloat32(o, Endian.little);
  return switch (f.bitsPerSample) {
    8 => (bd.getUint8(o) - 128) / 128,
    16 => bd.getInt16(o, Endian.little) / 32768,
    24 =>
      ((bd.getUint8(o) |
              (bd.getUint8(o + 1) << 8) |
              (bd.getInt8(o + 2) << 16)) /
          8388608),
    _ => bd.getInt32(o, Endian.little) / 2147483648,
  };
}

/// Reads the header of a WAV file.
Future<WavInfo> readWavInfo(File file) async {
  final raf = await file.open();
  try {
    final len = await raf.length();
    final head = await raf.read(math.min(len, 1 << 16));
    return parseWav(head, totalLength: len);
  } finally {
    await raf.close();
  }
}

/// Peaks for a whole file at [peaksPerSecond], read in chunks.
Future<Float32List> filePeaks(
  File file,
  WavInfo info, {
  int peaksPerSecond = 100,
}) async {
  final f = info.format;
  final per = math.max(1, f.sampleRate ~/ peaksPerSecond);
  final chunkBytes = per * f.frameBytes * 256;
  final out = BytesBuilderF32();
  final raf = await file.open();
  try {
    await raf.setPosition(info.dataOffset);
    var left = info.dataLength;
    while (left > 0) {
      final n = math.min(left, chunkBytes);
      final bytes = await raf.read(n);
      if (bytes.isEmpty) break;
      out.add(pcmPeaks(bytes, f, per));
      left -= bytes.length;
    }
  } finally {
    await raf.close();
  }
  return out.take();
}

/// Copies frames [start, end) into a new, complete WAV file in memory.
Future<Uint8List> extractWav(
  File file,
  WavInfo info,
  int start,
  int end,
) async {
  final s = start.clamp(0, info.frames);
  final e = end.clamp(s, info.frames);
  final raf = await file.open();
  try {
    await raf.setPosition(info.dataOffset + s * info.format.frameBytes);
    final data = await raf.read((e - s) * info.format.frameBytes);
    return buildWav(info.format, data);
  } finally {
    await raf.close();
  }
}

/// Growable Float32 list.
class BytesBuilderF32 {
  Float32List _data = Float32List(1024);
  int length = 0;

  void add(Float32List values) {
    if (length + values.length > _data.length) {
      final next = Float32List(
        math.max(_data.length * 2, length + values.length),
      );
      next.setRange(0, length, _data);
      _data = next;
    }
    _data.setRange(length, length + values.length, values);
    length += values.length;
  }

  void addOne(double v) {
    if (length == _data.length) {
      final next = Float32List(_data.length * 2)..setRange(0, length, _data);
      _data = next;
    }
    _data[length++] = v;
  }

  /// A view of the current values (valid until the next add).
  Float32List get view => Float32List.sublistView(_data, 0, length);

  Float32List take() => Float32List.fromList(view);
}

/// Streams 16-bit PCM to a WAV file, fixing the header on close.
class WavFileWriter {
  WavFileWriter._(this.file, this.format, this._raf);

  final File file;
  final WavFormat format;
  final RandomAccessFile _raf;
  int _dataLength = 0;

  int get dataLength => _dataLength;

  static Future<WavFileWriter> create(File file, WavFormat format) async {
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    await raf.writeFrom(wavHeader(format, 0));
    return WavFileWriter._(file, format, raf);
  }

  Future<void> add(Uint8List pcm) async {
    await _raf.writeFrom(pcm);
    _dataLength += pcm.length;
  }

  /// Writes the final sizes; the file stays readable even without this.
  Future<WavInfo> close() async {
    await _raf.setPosition(0);
    await _raf.writeFrom(wavHeader(format, _dataLength));
    await _raf.close();
    return WavInfo(format, 44, _dataLength);
  }
}
