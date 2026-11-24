import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:chip_synth/chip_synth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:speech_chip_lab/main.dart';
import 'package:speech_chip_lab/src/controller.dart';
import 'package:speech_chip_lab/src/output.dart';
import 'package:speech_chip_lab/src/ui/home.dart';

class FakeOutput implements SpeechOutput {
  final sent = <SpeechCommand>[];
  final _p = StreamController<SpeechProgress>.broadcast(sync: true);
  void emit(SpeechProgress p) => _p.add(p);

  @override
  Future<void> init() async {}
  @override
  void send(SpeechCommand c) => sent.add(c);
  @override
  Stream<SpeechProgress> get progress => _p.stream;
  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'speaking uses the question voice for questions and hand fixes',
    () async {
      final out = FakeOutput();
      final c = SpeechController(out);
      await c.init();
      c.setText('Is it raining?');
      c.fixWord('raining', ['R', 'EY', 'N', 'IH', 'NG']);
      c.speak();
      final say = out.sent.whereType<Say>().single;
      expect(say.settings.contour, Contour.question);
      expect(say.words.last.phonemes, ['R', 'EY', 'N', 'IH', 'NG']);
      out.emit(const SpeechProgress(1, true));
      expect(c.wordIndex, 1);
      out.emit(const SpeechProgress(2, false));
      expect(c.speaking, isFalse);
    },
  );

  test('singing steps through the words; sliding keeps the word', () async {
    final out = FakeOutput();
    final c = SpeechController(out);
    await c.init();
    c.setText('la di da');
    c.noteOn(60);
    c.noteOn(64); // slide while held
    c.noteOff(64);
    c.noteOn(67);
    c.noteOff(67);
    final sung = out.sent.whereType<SingWord>().toList();
    expect(sung.map((s) => s.word.text), ['la', 'di']);
    expect(sung.first.hz, closeTo(261.6, 0.1));
    expect(out.sent.whereType<SingPitch>().single.hz, closeTo(329.6, 0.1));
    expect(out.sent.whereType<ReleaseWord>(), hasLength(2));
    c.restartLyrics();
    expect(c.singNext, 0);
  });

  testWidgets('type, see the sounds, pick a chip, sing', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('speech_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final out = FakeOutput();
    final c = SpeechController(out);
    await tester.runAsync(c.init);
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(controller: c),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'make light');
    await tester.pump();
    expect(find.text('M EY K'), findsOneWidget);
    expect(find.text('L AY T'), findsOneWidget);

    await tester.tap(find.text('Votrax'));
    await tester.pump();
    expect(c.settings.chip, SpeechChip.votrax);
    expect(find.text('Clock (pitch, size and speed)'), findsOneWidget);

    await tester.tap(find.text('Speak'));
    expect(out.sent.whereType<Say>().single.settings.chip, SpeechChip.votrax);

    await tester.tap(find.text('Sing'));
    await tester.pump();
    final keys = find.byType(PianoKeyboard);
    final g = await tester.startGesture(
      tester.getBottomLeft(keys) + const Offset(10, -10),
    );
    await tester.pump();
    expect(out.sent.whereType<SingWord>().single.word.text, 'make');
    await g.up();
    await tester.pump();
    expect(find.text('Next: "light"'), findsOneWidget);
  });
}
