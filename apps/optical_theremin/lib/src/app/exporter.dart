import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands an exported audio file to the user.
abstract class Exporter {
  /// Returns a message for the user, or null if they cancelled.
  Future<String?> exportWav(String fileName, Uint8List wav);
}

/// Android: share sheet (save to Files / Drive, send to apps).
/// Windows and Linux: a "Save as" dialog.
class PlatformExporter implements Exporter {
  @override
  Future<String?> exportWav(String fileName, Uint8List wav) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'WAV audio', extensions: ['wav']),
        ],
      );
      if (location == null) return null;
      var path = location.path;
      if (p.extension(path).toLowerCase() != '.wav') path = '$path.wav';
      await File(path).writeAsBytes(wav, flush: true);
      return 'Saved ${p.basename(path)}';
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(wav, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'audio/wav')],
        title: fileName,
      ),
    );
    return result.status == ShareResultStatus.dismissed ? null : 'Exported';
  }
}
