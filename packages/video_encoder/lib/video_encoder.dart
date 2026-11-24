/// Writes videos with sound.
///
/// - [Mp4Writer]: H.264 + AAC in MP4 using the system encoders (Android
///   MediaCodec, Windows Media Foundation). Plays and shares everywhere.
/// - [AviWriter]: pure Dart, Motion-JPEG + 16-bit PCM in AVI. Works on every
///   platform (plays in VLC, browsers' downloads are another matter).
///
/// [openVideoWriter] picks MP4 where the system can encode it.
library;

export 'src/avi.dart';
export 'src/convert.dart';
export 'src/mp4.dart';
export 'src/writer.dart';
