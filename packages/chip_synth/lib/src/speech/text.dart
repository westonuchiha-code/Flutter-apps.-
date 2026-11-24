// English text → speech sounds, by a small dictionary plus spelling rules.
// Good enough to be understood (the chips themselves were never perfect);
// anything inside [brackets] is taken as sounds directly, e.g. [HH EH L OW].

import 'phonemes.dart';

/// One word and its sounds.
class SpokenWord {
  const SpokenWord(this.text, this.phonemes, {this.pauseAfter = '_'});
  final String text;
  final List<String> phonemes;

  /// `_` between words, `__` after punctuation, '' for none.
  final String pauseAfter;

  @override
  String toString() => '$text[${phonemes.join(' ')}]';
}

/// Words the rules get wrong (and the most common ones).
const _dictionary = <String, String>{
  'a': 'AX',
  'the': 'DH AX',
  'of': 'AH V',
  'to': 'T UW',
  'and': 'AE N D',
  'you': 'Y UW',
  'your': 'Y AO R',
  'i': 'AY',
  'is': 'IH Z',
  'was': 'W AA Z',
  'are': 'AA R',
  'have': 'HH AE V',
  'has': 'HH AE Z',
  'do': 'D UW',
  'does': 'D AH Z',
  'done': 'D AH N',
  'said': 'S EH D',
  'says': 'S EH Z',
  'one': 'W AH N',
  'two': 'T UW',
  'three': 'TH R IY',
  'four': 'F AO R',
  'five': 'F AY V',
  'six': 'S IH K S',
  'seven': 'S EH V AX N',
  'eight': 'EY T',
  'nine': 'N AY N',
  'ten': 'T EH N',
  'eleven': 'IH L EH V AX N',
  'twelve': 'T W EH L V',
  'thirteen': 'TH ER T IY N',
  'fifteen': 'F IH F T IY N',
  'twenty': 'T W EH N T IY',
  'thirty': 'TH ER T IY',
  'forty': 'F AO R T IY',
  'fifty': 'F IH F T IY',
  'hundred': 'HH AH N D R AX D',
  'thousand': 'TH AW Z AX N D',
  'million': 'M IH L Y AX N',
  'zero': 'Z IH R OW',
  'this': 'DH IH S',
  'that': 'DH AE T',
  'these': 'DH IY Z',
  'those': 'DH OW Z',
  'they': 'DH EY',
  'them': 'DH EH M',
  'then': 'DH EH N',
  'than': 'DH AE N',
  'there': 'DH EH R',
  'their': 'DH EH R',
  'where': 'W EH R',
  'here': 'HH IY R',
  'were': 'W ER',
  'what': 'W AH T',
  'who': 'HH UW',
  'why': 'W AY',
  'how': 'HH AW',
  'with': 'W IH DH',
  'from': 'F R AH M',
  'for': 'F AO R',
  'or': 'AO R',
  'by': 'B AY',
  'my': 'M AY',
  'me': 'M IY',
  'we': 'W IY',
  'he': 'HH IY',
  'she': 'SH IY',
  'be': 'B IY',
  'it': 'IH T',
  'in': 'IH N',
  'on': 'AA N',
  'at': 'AE T',
  'as': 'AE Z',
  'an': 'AE N',
  'no': 'N OW',
  'go': 'G OW',
  'so': 'S OW',
  'not': 'N AA T',
  'all': 'AO L',
  'any': 'EH N IY',
  'many': 'M EH N IY',
  'some': 'S AH M',
  'come': 'K AH M',
  'love': 'L AH V',
  'give': 'G IH V',
  'live': 'L IH V',
  'gone': 'G AO N',
  'move': 'M UW V',
  'friend': 'F R EH N D',
  'people': 'P IY P AX L',
  'water': 'W AO T ER',
  'world': 'W ER L D',
  'hello': 'HH EH L OW',
  'hi': 'HH AY',
  'yes': 'Y EH S',
  'okay': 'OW K EY',
  'ok': 'OW K EY',
  'computer': 'K AX M P Y UW T ER',
  'robot': 'R OW B AA T',
  'machine': 'M AX SH IY N',
  'speech': 'S P IY CH',
  'chip': 'CH IH P',
  'music': 'M Y UW Z IH K',
  'game': 'G EY M',
  'over': 'OW V ER',
  'error': 'EH R ER',
  'again': 'AX G EH N',
  'only': 'OW N L IY',
  'very': 'V EH R IY',
  'every': 'EH V R IY',
  'could': 'K UH D',
  'would': 'W UH D',
  'should': 'SH UH D',
  'because': 'B IH K AO Z',
  'please': 'P L IY Z',
  'thank': 'TH AE NG K',
  'thanks': 'TH AE NG K S',
  'good': 'G UH D',
  'great': 'G R EY T',
  'one\'s': 'W AH N Z',
  'don\'t': 'D OW N T',
  'can\'t': 'K AE N T',
  'it\'s': 'IH T S',
  'i\'m': 'AY M',
  'you\'re': 'Y AO R',
  'eye': 'AY',
  'busy': 'B IH Z IY',
  'women': 'W IH M AX N',
  'woman': 'W UH M AX N',
  'colonel': 'K ER N AX L',
  'two\'s': 'T UW Z',
  'buy': 'B AY',
  'pretty': 'P R IH T IY',
  'sure': 'SH UH R',
  'ready': 'R EH D IY',
  'head': 'HH EH D',
  'bread': 'B R EH D',
  'dead': 'D EH D',
  'early': 'ER L IY',
  'learn': 'L ER N',
  'heart': 'HH AA R T',
  'once': 'W AH N S',
  'listen': 'L IH S AX N',
};

const _vowels = 'aeiouy';
bool _isVowel(String c) => _vowels.contains(c);

/// Turns one word (lower case letters) into sounds.
List<String> wordToPhonemes(String word) {
  final dict = _dictionary[word];
  if (dict != null) return dict.split(' ');
  final w = word;
  final out = <String>[];
  var i = 0;
  // Silent final e after a consonant makes the vowel before it long
  // ("make", "time", "note", "cute").
  final magicE =
      w.length > 2 &&
      w.endsWith('e') &&
      !_isVowel(w[w.length - 2]) &&
      w.length >= 3 &&
      _isVowel(w[w.length - 3]);
  final longVowelAt = magicE ? w.length - 3 : -1;

  bool at(String s) => w.startsWith(s, i);
  String? next(int k) => i + k < w.length ? w[i + k] : null;
  final atEnd = w.length;

  void add(String s) => out.addAll(s.split(' '));

  while (i < atEnd) {
    final c = w[i];
    final n1 = next(1);
    final rest = atEnd - i;

    // Endings first.
    if (rest == 4 && (at('tion'))) {
      add('SH AX N');
      i += 4;
      continue;
    }
    if (rest == 4 && at('sion')) {
      add('ZH AX N');
      i += 4;
      continue;
    }
    if (rest == 2 && at('le') && i > 0 && !_isVowel(w[i - 1])) {
      add('AX L');
      i += 2;
      continue;
    }
    if (rest == 2 && at('ed') && i > 1) {
      final prev = w[i - 1];
      add(
        prev == 't' || prev == 'd'
            ? 'IH D'
            : ('pkfsxc'.contains(prev) ||
                  w.substring(0, i).endsWith('sh') ||
                  w.substring(0, i).endsWith('ch'))
            ? 'T'
            : 'D',
      );
      i += 2;
      continue;
    }
    if (rest == 1 && c == 'e' && w.length > 2) {
      i++; // silent final e
      continue;
    }
    if (rest == 1 && c == 's' && i > 0 && !'ptkf'.contains(w[i - 1])) {
      add('Z');
      i++;
      continue;
    }
    if (rest == 1 && c == 'y') {
      add(
        w.length <= 3 && !w.substring(0, i).split('').any(_isVowel)
            ? 'AY'
            : 'IY',
      );
      i++;
      continue;
    }

    // Letter groups, longest first.
    const groups = <String, String>{
      'eigh': 'EY',
      'ough': 'AO',
      'augh': 'AO',
      'tion': 'SH AX N',
      'igh': 'AY',
      'tch': 'CH',
      'dge': 'JH',
      'sch': 'S K',
      'all': 'AO L',
      'alk': 'AO K',
      'ee': 'IY',
      'ea': 'IY',
      'oo': 'UW',
      'ou': 'AW',
      'oi': 'OY',
      'oy': 'OY',
      'ai': 'EY',
      'ay': 'EY',
      'au': 'AO',
      'aw': 'AO',
      'ew': 'UW',
      'ie': 'IY',
      'ei': 'EY',
      'oa': 'OW',
      'ue': 'UW',
      'ui': 'UW',
      'ar': 'AA R',
      'er': 'ER',
      'ir': 'ER',
      'ur': 'ER',
      'or': 'AO R',
      'th': 'TH',
      'sh': 'SH',
      'ch': 'CH',
      'ph': 'F',
      'wh': 'W',
      'ck': 'K',
      'ng': 'NG',
      'nk': 'NG K',
      'qu': 'K W',
    };
    var matched = false;
    for (final e in groups.entries) {
      if (at(e.key)) {
        // "ow" at the end is OW (snow); otherwise AW (cow) is handled below.
        add(e.value);
        i += e.key.length;
        matched = true;
        break;
      }
    }
    if (matched) continue;
    if (at('ow')) {
      add(i + 2 == atEnd ? 'OW' : 'AW');
      i += 2;
      continue;
    }
    if (i == 0 && at('kn')) {
      add('N');
      i += 2;
      continue;
    }
    if (i == 0 && at('wr')) {
      add('R');
      i += 2;
      continue;
    }
    if (rest == 2 && at('mb')) {
      add('M');
      i += 2;
      continue;
    }
    if (at('gh')) {
      i += 2; // silent (night, though)
      continue;
    }
    // Doubled consonants sound once.
    if (n1 == c && !_isVowel(c)) {
      i++;
      continue;
    }

    switch (c) {
      case 'a':
        add(i == longVowelAt ? 'EY' : 'AE');
      case 'e':
        add(i == longVowelAt ? 'IY' : 'EH');
      case 'i':
        add(i == longVowelAt ? 'AY' : 'IH');
      case 'o':
        add(i == longVowelAt ? 'OW' : 'AA');
      case 'u':
        add(i == longVowelAt ? 'UW' : 'AH');
      case 'y':
        add(i == 0 ? 'Y' : 'IH');
      case 'c':
        add(n1 != null && 'eiy'.contains(n1) ? 'S' : 'K');
      case 'g':
        add(n1 != null && 'eiy'.contains(n1) && i > 0 ? 'JH' : 'G');
      case 's':
        add(
          i > 0 && n1 != null && _isVowel(w[i - 1]) && _isVowel(n1) ? 'Z' : 'S',
        );
      case 'x':
        add(i == 0 ? 'Z' : 'K S');
      case 'b':
        add('B');
      case 'd':
        add('D');
      case 'f':
        add('F');
      case 'h':
        add('HH');
      case 'j':
        add('JH');
      case 'k':
        add('K');
      case 'l':
        add('L');
      case 'm':
        add('M');
      case 'n':
        add('N');
      case 'p':
        add('P');
      case 'q':
        add('K');
      case 'r':
        add('R');
      case 't':
        add('T');
      case 'v':
        add('V');
      case 'w':
        add('W');
      case 'z':
        add('Z');
    }
    i++;
  }
  return out;
}

const _ones = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const _tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

/// 0..999999 in words.
String numberToWords(int n) {
  if (n < 20) return _ones[n];
  if (n < 100) {
    return '${_tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${_ones[n % 10]}'}';
  }
  if (n < 1000) {
    return '${_ones[n ~/ 100]} hundred${n % 100 == 0 ? '' : ' ${numberToWords(n % 100)}'}';
  }
  if (n < 1000000) {
    return '${numberToWords(n ~/ 1000)} thousand${n % 1000 == 0 ? '' : ' ${numberToWords(n % 1000)}'}';
  }
  return n.toString().split('').map((d) => _ones[int.parse(d)]).join(' ');
}

/// Text → words with their sounds. `[AA B]` passes sounds straight through.
List<SpokenWord> textToSpeech(String text) {
  final words = <SpokenWord>[];
  final token = RegExp(r"\[([^\]]*)\]|[A-Za-z']+|\d+|[.,!?;:]");
  for (final m in token.allMatches(text)) {
    final t = m[0]!;
    if (m[1] != null) {
      final ph = m[1]!
          .toUpperCase()
          .split(RegExp(r'[\s,]+'))
          .where(phonemes.containsKey)
          .toList();
      if (ph.isNotEmpty) words.add(SpokenWord(t, ph));
    } else if (RegExp(r'^\d+$').hasMatch(t)) {
      final n = int.tryParse(t) ?? 0;
      for (final w in numberToWords(n).split(' ')) {
        words.add(SpokenWord(w, wordToPhonemes(w)));
      }
    } else if ('.,!?;:'.contains(t)) {
      if (words.isNotEmpty) {
        final last = words.removeLast();
        words.add(SpokenWord(last.text, last.phonemes, pauseAfter: '__'));
      }
    } else {
      final ph = wordToPhonemes(t.toLowerCase());
      if (ph.isNotEmpty) words.add(SpokenWord(t, ph));
    }
  }
  return words;
}

/// True if the text ends with a question mark (the voice rises).
bool isQuestion(String text) => text.trimRight().endsWith('?');
