import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:optical_theremin/src/app/settings_store.dart';
import 'package:optical_theremin/src/core/music.dart';
import 'package:optical_theremin/src/core/settings.dart';
import 'package:optical_theremin/src/recording/take.dart';
import 'package:optical_theremin/src/recording/take_store.dart';
import 'package:optical_theremin/src/synth/engine.dart';
import 'package:optical_theremin/src/synth/wav.dart';

Take sampleTake({int frames = 50, String id = 't1'}) {
  final r = TakeRecorder(const SoundSpec(chipId: 'nes', patchId: 'pulse'));
  for (var i = 0; i < frames; i++) {
    r.add(
      hz: 220 + i.toDouble(),
      level: 0.8,
      timbre: 0.5,
      spec: i < frames ~/ 2
          ? const SoundSpec(chipId: 'nes', patchId: 'pulse')
          : const SoundSpec(chipId: 'sid', patchId: 'saw'),
    );
  }
  return r.finish(id: id, name: 'Test', now: DateTime(2026, 1, 2, 3, 4, 5));
}

void main() {
  test('recorder captures controls and sound changes', () {
    final take = sampleTake();
    expect(take.frames, 50);
    expect(take.duration, const Duration(milliseconds: 500));
    expect(take.specs.length, 2);
    expect(take.specs[1].frame, 25);
    expect(take.hz[10], 230);
  });

  test('take JSON round trip', () {
    final take = sampleTake();
    final copy = Take.fromJson(take.toJson());
    expect(copy.name, 'Test');
    expect(copy.hz, take.hz);
    expect(copy.level, take.level);
    expect(copy.specs.map((s) => s.spec), take.specs.map((s) => s.spec));
    expect(copy.created, take.created);
  });

  test('revoicing replaces the sound', () {
    final take = sampleTake();
    final revoiced = take.copyWith(
      sound: const SoundSpec(chipId: 'fm', patchId: 'bell'),
    );
    expect(revoiced.specs.length, 1);
    expect(revoiced.sound.chipId, 'fm');
    expect(revoiced.hz, same(take.hz));
  });

  test('renders a take with a tail, and encodes WAV', () {
    final take = sampleTake();
    final audio = renderTake(take, tail: 0.5);
    expect(audio.length, (0.5 * 48000 + 0.5 * 48000).round() * 2);
    var loud = 0.0;
    for (var i = 0; i < 24000 * 2; i++) {
      loud = loud > audio[i].abs() ? loud : audio[i].abs();
    }
    expect(loud, greaterThan(0.1));

    final wav = renderTakeWav(take);
    final bytes = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(bytes.getUint16(22, Endian.little), 2); // stereo
    expect(bytes.getUint32(24, Endian.little), 48000);
    expect(bytes.getUint32(40, Endian.little), wav.length - 44);
  });

  test('encodeWav16 clamps and converts', () {
    final wav = encodeWav16(Float32List.fromList([1, -1, 2, 0]), 8000);
    final b = ByteData.sublistView(wav);
    expect(b.getInt16(44, Endian.little), 32767);
    expect(b.getInt16(46, Endian.little), -32767);
    expect(b.getInt16(48, Endian.little), 32767);
    expect(b.getInt16(50, Endian.little), 0);
  });

  test('file take store saves, lists newest first, deletes', () async {
    final dir = await Directory.systemTemp.createTemp('takes');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileTakeStore(Directory('${dir.path}/rec'));
    expect(await store.list(), isEmpty);
    final older = sampleTake(id: 'a');
    final newer = Take(
      id: 'b',
      name: 'Newer',
      created: DateTime(2027),
      hz: older.hz,
      level: older.level,
      timbre: older.timbre,
      specs: older.specs,
    );
    await store.save(older);
    await store.save(newer);
    final listed = await store.list();
    expect(listed.map((t) => t.id), ['b', 'a']);
    await store.delete('a');
    expect((await store.list()).map((t) => t.id), ['b']);
  });

  test('settings JSON round trip and file store', () async {
    const settings = ThereminSettings(
      sound: SoundSpec(chipId: 'ay', patchId: 'buzz', echoMix: 0.4),
      lowNote: 40,
      highNote: 70,
      scale: ScaleType.blues,
      root: 3,
      secondControl: SecondControl.shape,
      invertSecond: true,
      cameraId: 'cam',
    );
    final copy = ThereminSettings.fromJson(settings.toJson());
    expect(copy.toJson(), settings.toJson());

    final dir = await Directory.systemTemp.createTemp('settings');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileSettingsStore(dir);
    expect(await store.load(), isNull);
    await store.save(settings);
    expect((await store.load())!.toJson(), settings.toJson());
    await File('${dir.path}/settings.json').writeAsString('{broken');
    expect(await store.load(), isNull);
  });
}
