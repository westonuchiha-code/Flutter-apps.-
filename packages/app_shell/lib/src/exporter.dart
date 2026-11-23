import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Gets a file or text out of the app: the share sheet on Android, a
/// "Save as" dialog on Windows and Linux.
class Exporter {
  const Exporter();

  /// Returns a message for the user, or null if cancelled.
  Future<String?> exportFile(
    String fileName,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final ext = p.extension(fileName).replaceFirst('.', '');
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          if (ext.isNotEmpty)
            XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
        ],
      );
      if (location == null) return null;
      await File(location.path).writeAsBytes(bytes, flush: true);
      return 'Saved ${p.basename(location.path)}';
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    final r = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        title: fileName,
      ),
    );
    return r.status == ShareResultStatus.dismissed ? null : 'Exported';
  }

  /// Shares text (Android/Windows) or saves it as a .txt file (Linux).
  Future<String?> exportText(String fileName, String text) async {
    if (Platform.isLinux) {
      return exportFile(fileName, Uint8List.fromList(utf8.encode(text)));
    }
    await SharePlus.instance.share(ShareParams(text: text, subject: fileName));
    return null;
  }
}
