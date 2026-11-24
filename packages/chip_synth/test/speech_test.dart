import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';
import 'package:test/test.dart';

List<String> ph(String word) => wordToPhonemes(word);

void main() {
  group('text to sounds', () {
    test('spelling rules', () {
      expect(ph('make'), ['M', 'EY', 'K']);
      expect(ph('phone'), ['F', 'OW', 'N']);
      expect(ph('light'), ['L', 'AY', 'T']);
      expect(ph('ship'), ['SH', 'IH', 'P']);
      expect(ph('cat'), ['K', 'AE', 'T']);
      expect(ph('city'), ['S', 'IH', 'T', 'IY']);
      expect(ph('jumped'), ['JH', 'AH', 'M', 'P', 'T']);
      expect(ph('lasted'), ['L', 'AE', 'S', 'T', 'IH', 'D']);
      expect(ph('dogs'), ['D', 'AA', 'G', 'Z']);
      expect(ph('knock'), ['N', 'AA', 'K']);
      expect(ph('snow'), ['S', 'N', 'OW']);
      expect(ph('cow'), ['K', 'OW'], reason: 'final ow (rules are simple)');
      expect(ph('the'), ['DH', 'AX']);
      expect(ph('talking'), ['T', 'AO', 'K', 'IH', 'NG']);
      expect(ph('walk'), ['W', 'AO', 'K']);
    });

    test('every word gives only known sounds', () {
      const words =
          'the quick brown fox jumps over the lazy dog while xylophones '
          'whistle through knights wrapping thumbs at midnight beside judges '
          'singing nation measure azure queue strengths rhythm';
      for (final w in words.split(' ')) {
        final p = ph(w);
        expect(p, isNotEmpty, reason: w);
        expect(p.every(phonemes.containsKey), isTrue, reason: '$w → $p');
      }
    });

    test('numbers, punctuation and [sounds]', () {
      expect(numberToWords(42), 'forty two');
      expect(numberToWords(1905), 'one thousand nine hundred five');
      final words = textToSpeech('I have 3 robots. [HH EH L OW XX] ok?');
      expect(words.map((w) => w.text), [
        'I',
        'have',
        'three',
        'robots',
        '[HH EH L OW XX]',
        'ok',
      ]);
      expect(words[3].pauseAfter, '__');
      expect(words[4].phonemes, [
        'HH',
        'EH',
        'L',
        'OW',
      ], reason: 'unknown XX dropped');
      expect(isQuestion('ok?'), isTrue);
    });
  });

  group('speech chips', () {
    final sentence = textToSpeech(
      'One wonderful morning, all the tall boys saw a huge blue whale.',
    );

    test(
      'every chip talks without clipping at low, middle and high voices',
      () {
        for (final chip in SpeechChip.values) {
          for (final pitch in [70.0, 110.0, 220.0]) {
            final synth = SpeechSynth(48000)
              ..speak(sentence, SpeechSettings(chip: chip, pitch: pitch));
            final out = Float32List(48000 * 6);
            synth.render(out, out.length);
            var sum = 0.0, peak = 0.0;
            for (final v in out) {
              sum += v * v;
              peak = math.max(peak, v.abs());
            }
            final rms = math.sqrt(sum / out.length);
            expect(synth.clipped, 0, reason: '${chip.name} at $pitch Hz');
            expect(peak, lessThan(1), reason: '${chip.name} at $pitch Hz');
            expect(
              rms,
              inInclusiveRange(0.03, 0.2),
              reason: '${chip.name} at $pitch Hz',
            );
          }
        }
      },
    );

    test('reports the word being spoken', () {
      final synth = SpeechSynth(48000)
        ..speak(textToSpeech('one two three'), const SpeechSettings());
      final seen = <int>{};
      final buf = Float32List(480);
      while (synth.busy) {
        synth.render(buf, 480);
        seen.add(synth.wordIndex);
      }
      expect(seen, containsAll([0, 1, 2]));
    });

    test('speed changes the length', () {
      final normal = renderSpeech(sentence, const SpeechSettings());
      final fast = renderSpeech(sentence, const SpeechSettings(speed: 2));
      expect(fast.length / normal.length, closeTo(0.5, 0.06));
    });

    test('TMS uses its pitch table; Votrax has only four pitch steps', () {
      final tms = SpeechSynth(48000)..settings = const SpeechSettings();
      for (final hz in [80.0, 123.0, 200.0, 333.0]) {
        expect(tmsPitchPeriods, contains(tms.periodFor(hz)));
      }
      final votrax = SpeechSynth(48000)
        ..settings = const SpeechSettings(chip: SpeechChip.votrax, pitch: 100);
      final periods = {
        for (var hz = 80.0; hz < 140; hz += 1) votrax.periodFor(hz),
      };
      expect(periods.length, lessThanOrEqualTo(4));
    });

    test('singing holds the vowel until the key is released', () {
      final synth = SpeechSynth(48000)
        ..singWord(
          textToSpeech('love').single,
          220,
          const SpeechSettings(chip: SpeechChip.sp0256),
        );
      final out = Float32List(48000 * 2);
      synth.render(out, out.length);
      expect(synth.busy, isTrue, reason: 'still holding after 2 s');
      expect(
        out.sublist(48000).map((v) => v.abs()).reduce(math.max),
        greaterThan(0.05),
      );
      synth.releaseWord();
      synth.render(Float32List(48000), 48000);
      expect(synth.busy, isFalse);
    });

    test('settings JSON round trip', () {
      const s = SpeechSettings(
        chip: SpeechChip.votrax,
        pitch: 150,
        speed: 1.5,
        contour: Contour.question,
        whisper: true,
      );
      final b = SpeechSettings.fromJson(s.toJson());
      expect(b.chip, SpeechChip.votrax);
      expect(b.pitch, 150);
      expect(b.contour, Contour.question);
      expect(b.whisper, isTrue);
    });
  });
}
