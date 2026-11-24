import 'dart:io';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixel_kit/pixel_kit.dart' as px;

import '../library.dart';

typedef Picture = ({int width, int height, Uint32List pixels});

/// Lets the user take a photo (Android) or pick a picture (device or Asset
/// Locker) and decodes it.
Future<Picture?> pickPicture(BuildContext context) async {
  final shell = Shell.of(context);
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (Platform.isAndroid)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Picture on this device'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_shared_outlined),
            title: const Text('Picture from the Asset Locker'),
            onTap: () => Navigator.pop(context, 'locker'),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  Uint8List? bytes;
  if (source == 'locker') {
    final locker = shell.locker;
    if (!locker.ready && !await locker.connect()) return null;
    if (!context.mounted) return null;
    final info = await pickFromLocker(
      context,
      locker,
      types: const [AssetType.sprite, AssetType.picture, AssetType.other],
    );
    if (info == null) return null;
    if (!pictureExtensions.contains(info.extension)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${info.name}" is not a picture.')),
        );
      }
      return null;
    }
    bytes = await locker.read(info);
  } else {
    final file = await ImagePicker().pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    bytes = await file?.readAsBytes();
  }
  if (bytes == null) return null;
  final pic = px.decodePicture(bytes);
  if (pic == null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That picture could not be opened.')),
    );
  }
  return pic;
}

/// Asks how many colours, previewing the palette made from [pic].
Future<px.Palette?> askPhotoPalette(BuildContext context, Picture pic) {
  var count = 16.0;
  return showDialog<px.Palette>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        final pal = px.paletteFromPixels(
          pic.pixels,
          count.round(),
          name: 'From photo (${count.round()})',
        );
        return AlertDialog(
          title: Text('${count.round()} colours'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: count,
                min: 2,
                max: 32,
                divisions: 30,
                onChanged: (v) => set(() => count = v),
              ),
              Wrap(
                children: [
                  for (final c in pal.colors)
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.all(1),
                      color: Color(c),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, pal),
              child: const Text('Use'),
            ),
          ],
        );
      },
    ),
  );
}

/// Asks how to bring a picture in as a layer: (snap to palette, dither).
Future<(bool, bool)?> askImportOptions(BuildContext context) {
  var snap = true, dither = false;
  return showDialog<(bool, bool)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: const Text('Add picture as a layer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('It is shrunk to fit the canvas.'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use only the palette colours'),
              value: snap,
              onChanged: (v) => set(() => snap = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Dither (checker pattern for in-between shades)',
              ),
              value: dither,
              onChanged: snap ? (v) => set(() => dither = v) : null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (snap, dither)),
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
