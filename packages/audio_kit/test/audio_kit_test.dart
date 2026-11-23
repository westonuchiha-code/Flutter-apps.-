import 'dart:io';
import 'dart:typed_data';

import 'package:audio_kit/audio_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Uint8List _pcm16(List<int> v) => Int16List.fromList(v).buffer.asUint8List();

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('audio_kit_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('header round trip and sample decoding', () {
    const f = WavFormat(sampleRate: 48000);
    final wav = buildWav(f, _pcm16([0, 16384, -32768, 32767]));
    final info = parseWav(wav);
    expect(info.format.sampleRate, 48000);
    expect(info.frames, 4);
    expect(info.dataOffset, 44);
    final bd = ByteData.sublistView(wav);
    expect(sampleAt(bd, 46, f), closeTo(0.5, 1e-4));
    expect(sampleAt(bd, 48, f), -1);
  });

  test('float and 24-bit stereo', () {
    final fl = Float32List.fromList([0.25, -0.5]).buffer.asUint8List();
    const ff = WavFormat(sampleRate: 8000, bitsPerSample: 32, isFloat: true);
    final info = parseWav(buildWav(ff, fl));
    expect(info.format.isFloat, isTrue);
    expect(pcmPeaks(fl, ff, 2), [0.5]);

    const f24 = WavFormat(sampleRate: 8000, channels: 2, bitsPerSample: 24);
    final d = Uint8List.fromList([0, 0, 0x40, 0, 0, 0xC0]); // +0.5, -0.5
    expect(parseWav(buildWav(f24, d)).frames, 1);
    expect(pcmPeaks(d, f24, 1).single, closeTo(0.5, 1e-6));
  });

  test('size 0 (unfinished file) uses the real length; junk is rejected', () {
    final wav = buildWav(const WavFormat(sampleRate: 100), _pcm16([1, 2, 3]));
    wav.buffer.asByteData().setUint32(40, 0, Endian.little);
    expect(parseWav(wav).frames, 3);
    expect(
      () => parseWav(Uint8List.fromList(List.filled(50, 7))),
      throwsA(isA<WavException>()),
    );
  });

  test('float to 16-bit clamps', () {
    final out = Int16List.view(
      floatToPcm16(Float32List.fromList([2, -2, 0.5])).buffer,
    );
    expect(out, [32767, -32768, 16384]);
  });

  test('streaming writer, file peaks and extract', () async {
    const f = WavFormat(sampleRate: 1000);
    final file = File('${dir.path}/rec.wav');
    final w = await WavFileWriter.create(file, f);
    await w.add(_pcm16(List.generate(1000, (i) => i < 500 ? 3277 : 16384)));
    await w.add(_pcm16(List.filled(500, -32768)));
    await w.close();
    final info = await readWavInfo(file);
    expect(info.frames, 1500);
    expect(info.seconds, 1.5);
    final peaks = await filePeaks(file, info, peaksPerSecond: 10);
    expect(peaks.length, 15);
    expect(peaks.first, closeTo(0.1, 1e-3));
    expect(peaks[7], closeTo(0.5, 1e-3));
    expect(peaks.last, 1.0);
    final cut = await extractWav(file, info, 400, 600);
    final ci = parseWav(cut);
    expect(ci.frames, 200);
    expect(Int16List.sublistView(cut, 44).first, 3277);
    expect(Int16List.sublistView(cut, 44).last, 16384);
  });

  test('peak tracker buckets, level and clip', () {
    final t = PeakTracker(4);
    t.add(Float32List.fromList([0.1, -0.3, 0.2, 0, 0.5, 0.1]));
    expect(t.peaks.view, [closeTo(0.3, 1e-6)]);
    expect(t.level, 0.5);
    expect(t.frames, 6);
    t.add(Float32List.fromList([1, 0]));
    expect(t.peaks.view.last, 1);
    expect(t.clipped, isTrue);
    t.resetClip();
    expect(t.clipped, isFalse);
  });

  test('helpers', () {
    expect(formatSeconds(65.34), '1:05.3');
    expect(formatSeconds(5, tenths: false), '0:05');
    expect(
      peakIn(Float32List.fromList([0.1, 0.9, 0.2]), 0, 2),
      closeTo(0.9, 1e-6),
    );
    expect(LevelMeter.toDb(1), 0);
    expect(LevelMeter.toDb(0), -60);
  });

  testWidgets('waveform trim handles drag and taps seek', (tester) async {
    double s = 1, e = 9, seek = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) => Center(
            child: SizedBox(
              width: 600,
              height: 120,
              child: WaveformView(
                peaks: Float32List.fromList(List.filled(1000, 0.5)),
                trimStart: s,
                trimEnd: e,
                onTrimChanged: (a, b) => set(() {
                  s = a;
                  e = b;
                }),
                onSeek: (t) => seek = t,
              ),
            ),
          ),
        ),
      ),
    );
    final box = tester.getTopLeft(find.byType(WaveformView));
    // Drag the start handle (x = 60) to x = 180.
    await tester.dragFrom(box + const Offset(60, 60), const Offset(120, 0));
    await tester.pump();
    expect(s, closeTo(3, 0.3));
    expect(e, 9);
    await tester.tapAt(box + const Offset(300, 60));
    expect(seek, closeTo(5, 0.1));
  });

  testWidgets('waveform png', (tester) async {
    final png = (await tester.runAsync(
      () => waveformPng(Float32List.fromList([0.1, 0.9, 0.4])),
    ))!;
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
  });
}
