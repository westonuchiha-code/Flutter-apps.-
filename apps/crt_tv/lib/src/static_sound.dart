import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Writes a short burst of TV-static hiss as a WAV file (made in code, so
/// there's no sound file to ship) and returns its path.
Future<String?> ensureStaticSound(Directory dataDir) async {
  final file = File('${dataDir.path}${Platform.pathSeparator}static_v1.wav');
  try {
    if (file.existsSync() && file.lengthSync() > 44) return file.path;
    await file.writeAsBytes(_buildStaticWav(), flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

Uint8List _buildStaticWav() {
  const sampleRate = 22050;
  const seconds = 1.5;
  final samples = (sampleRate * seconds).round();
  final random = Random(7);
  final bytes = ByteData(44 + samples * 2);

  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  // Standard 16-bit mono PCM WAV header.
  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, samples * 2, Endian.little);

  // White noise, lightly smoothed so it hisses rather than screeches, with a
  // quick fade at both ends so it doesn't click.
  var smoothed = 0.0;
  for (var i = 0; i < samples; i++) {
    final white = random.nextDouble() * 2 - 1;
    smoothed = smoothed * 0.35 + white * 0.65;
    final fadeIn = min(1.0, i / (sampleRate * 0.02));
    final fadeOut = min(1.0, (samples - i) / (sampleRate * 0.08));
    final flutter = 0.85 + 0.15 * sin(i / sampleRate * 2 * pi * 60);
    final value = smoothed * fadeIn * fadeOut * flutter * 0.55;
    // |value| stays under 0.6, so this always fits in 16 bits.
    bytes.setInt16(44 + i * 2, (value * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
