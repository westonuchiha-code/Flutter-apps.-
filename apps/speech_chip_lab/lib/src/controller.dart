import 'dart:async';
import 'dart:math' as math;

import 'package:chip_synth/chip_synth.dart';
import 'package:flutter/foundation.dart';

import 'output.dart';

const exampleText =
    'Hello. I am a talking computer. Would you like to play a game?';

class SpeechController extends ChangeNotifier {
  SpeechController(this.output);

  final SpeechOutput output;
  StreamSubscription<SpeechProgress>? _sub;

  String text = exampleText;
  SpeechSettings settings = const SpeechSettings();

  /// Sounds the user fixed by hand, by lower-case word.
  final overrides = <String, List<String>>{};

  bool speaking = false;
  int wordIndex = -1;

  // Singing: each key sings the next word.
  int singNext = 0;
  int? _singNote;
  int octave = 3;

  Future<void> init() async {
    _sub = output.progress.listen((p) {
      wordIndex = p.wordIndex;
      speaking = p.busy;
      notifyListeners();
    });
    await output.init();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(output.dispose());
    super.dispose();
  }

  /// The words of [text] with their sounds (hand fixes applied).
  List<SpokenWord> get words => [
    for (final w in textToSpeech(text))
      overrides[w.text.toLowerCase()] == null
          ? w
          : SpokenWord(
              w.text,
              overrides[w.text.toLowerCase()]!,
              pauseAfter: w.pauseAfter,
            ),
  ];

  void setText(String t) {
    text = t;
    singNext = 0;
    notifyListeners();
  }

  void setSettings(SpeechSettings s) {
    settings = s;
    notifyListeners();
  }

  void fixWord(String word, List<String> sounds) {
    overrides[word.toLowerCase()] = sounds;
    notifyListeners();
  }

  void clearFix(String word) {
    overrides.remove(word.toLowerCase());
    notifyListeners();
  }

  SpeechSettings get _effective => settings.copyWith(
    contour: settings.contour == Contour.statement && isQuestion(text)
        ? Contour.question
        : settings.contour,
  );

  void speak() {
    final w = words;
    if (w.isEmpty) return;
    output.send(Say(w, _effective));
    speaking = true;
    wordIndex = 0;
    notifyListeners();
  }

  void stop() {
    output.send(const StopSpeech());
    speaking = false;
    notifyListeners();
  }

  // ---- Singing ----

  static double noteHz(int n) => 440 * math.pow(2, (n - 69) / 12).toDouble();

  bool isDown(int note) => _singNote == note;

  /// Sings the next word at [note]; holds its vowel while the key is down.
  void noteOn(int note) {
    final w = words;
    if (w.isEmpty) return;
    if (_singNote != null) {
      // Sliding to another key: the held word follows the new pitch.
      _singNote = note;
      output.send(SingPitch(noteHz(note)));
      notifyListeners();
      return;
    }
    final i = singNext % w.length;
    _singNote = note;
    output.send(
      SingWord(w[i], noteHz(note), settings.copyWith(contour: Contour.flat)),
    );
    wordIndex = i;
    singNext = i + 1;
    notifyListeners();
  }

  void noteOff(int note) {
    if (_singNote != note) return;
    _singNote = null;
    output.send(const ReleaseWord());
    notifyListeners();
  }

  void restartLyrics() {
    singNext = 0;
    notifyListeners();
  }

  void setOctave(int o) {
    octave = o.clamp(1, 6);
    notifyListeners();
  }
}
