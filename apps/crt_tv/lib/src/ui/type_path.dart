import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../tv_controller.dart';

/// Lets you type or paste the TV folder's path, for when you know it and
/// would sooner not browse to it.
Future<void> typeLibraryPath(BuildContext context, TvController tv) async {
  final text = TextEditingController(text: tv.settings.libraryPath ?? '');
  final path = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('TV folder path'),
      content: TextField(
        controller: text,
        autofocus: true,
        decoration: InputDecoration(
          hintText: Platform.isWindows ? r'D:\TV' : '/home/you/Videos/TV',
        ),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(text.text.trim()),
          child: const Text('Use this folder'),
        ),
      ],
    ),
  );
  if (path == null || path.isEmpty) return;
  if (!Directory(path).existsSync()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t find a folder at "$path".')),
      );
    }
    return;
  }
  await tv.loadLibrary(path);
}
