/// Pure-Dart MP3 encoder (MPEG-1 Layer III, CBR, 44.1 kHz) with ID3 tags.
/// Its filters are probed from the decoder flutter_soloud ships (dr_mp3),
/// so what it writes is what our apps play back.
library;

export 'src/encoder.dart' show encodeMp3, Mp3Tags, bitrates;
