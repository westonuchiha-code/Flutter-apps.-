import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import '../engine/formats.dart';
import '../engine/warp.dart';
import 'views.dart';

const _pictureExtensions = [
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'webp',
  'tga',
  'tif',
  'tiff',
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});

  /// For tests.
  final TextureController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextureController c = widget.controller ?? TextureController();
  bool _opening = false;

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _open(String source) async {
    final shell = Shell.of(context);
    Uint8List? bytes;
    var name = 'Texture';
    try {
      if (source == 'locker') {
        final locker = shell.locker;
        if (!locker.ready && !await locker.connect()) return;
        if (!mounted) return;
        final info = await pickFromLocker(
          context,
          locker,
          types: const [AssetType.picture, AssetType.other],
        );
        if (info == null) return;
        if (!_pictureExtensions.contains(info.extension.toLowerCase())) {
          _snack('"${info.name}" is not a picture.');
          return;
        }
        bytes = await locker.read(info);
        name = info.name;
      } else {
        final file = await ImagePicker().pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 3000,
          maxHeight: 3000,
          imageQuality: 95,
        );
        if (file == null) return;
        bytes = await file.readAsBytes();
      }
      if (bytes == null || !mounted) return;
      setState(() => _opening = true);
      final ok = await c.openBytes(bytes, name: name);
      if (!ok) _snack('That picture could not be opened.');
    } catch (e) {
      if (mounted) _snack('Could not open the picture: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _pickSource() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _SourceList(onPick: (s) => Navigator.pop(context, s)),
      ),
    );
    if (source != null) await _open(source);
  }

  Future<void> _save(String what) async {
    final consoleVersion = what.startsWith('console');
    final toLocker = what.endsWith('locker');
    if ((consoleVersion ? c.consolePic : c.master) == null) return;
    final shell = Shell.of(context);
    var name = consoleVersion
        ? '${c.name} (${c.consoleLabel})'
        : '${c.name} (master ${c.settings!.size})';
    if (toLocker) {
      final picked = await _askName(name);
      if (picked == null) return;
      name = picked;
    }
    try {
      final png = consoleVersion ? await c.consolePng() : await c.masterPng();
      if (toLocker) {
        final locker = shell.locker;
        if (!locker.ready && !await locker.connect()) return;
        await locker.save(
          type: AssetType.picture,
          name: name,
          bytes: png,
          extension: 'png',
          tags: ['texture', if (consoleVersion) c.console.id else 'master'],
          extra: {
            'texture': true,
            'tiles': c.settings!.seamless,
            if (consoleVersion) ...{
              'console': c.console.id,
              'format': c.format.format.id,
              'size': c.size,
              'bytes': c.consoleBytes,
            } else
              'size': c.settings!.size,
          },
        );
        _snack('Saved to Pictures');
      } else {
        final file = name
            .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
            .trim()
            .replaceAll(' ', '_');
        await shell.exporter.exportFile(
          '${file.isEmpty ? 'texture' : file}.png',
          png,
          mimeType: 'image/png',
        );
      }
    } catch (e) {
      if (mounted) _snack('Could not save: $e');
    }
  }

  Future<String?> _askName(String initial) {
    final field = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save to Asset Locker'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) =>
              Navigator.pop(context, v.trim().isEmpty ? initial : v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              field.text.trim().isEmpty ? initial : field.text.trim(),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.photo == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Texture Capture'),
              actions: shellActions(context),
            ),
            body: _opening
                ? const Center(child: CircularProgressIndicator())
                : _Empty(onPick: _open),
          );
        }
        final serious = c.advice.where((a) => a.serious).length;
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(c.name, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: 'Open another photo',
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  onPressed: _opening ? null : _pickSource,
                ),
                PopupMenuButton<String>(
                  tooltip: 'Save',
                  icon: const Icon(Icons.save_alt),
                  onSelected: _save,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'master_locker',
                      child: Text('Save master to Asset Locker'),
                    ),
                    PopupMenuItem(
                      value: 'console_locker',
                      child: Text(
                        'Save ${c.console.name} version to Asset Locker',
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'master_share',
                      child: Text('Export master PNG'),
                    ),
                    PopupMenuItem(
                      value: 'console_share',
                      child: Text('Export ${c.console.name} PNG'),
                    ),
                  ],
                ),
                ...shellActions(context),
              ],
              bottom: TabBar(
                tabs: [
                  const Tab(text: 'Corners'),
                  Tab(
                    child: Badge(
                      isLabelVisible: c.advice.isNotEmpty,
                      label: Text('${c.advice.length}'),
                      backgroundColor: serious > 0
                          ? Colors.orange
                          : Colors.blueGrey,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('Texture'),
                      ),
                    ),
                  ),
                  const Tab(text: 'Console'),
                ],
              ),
            ),
            body: SafeArea(
              child: TabBarView(
                // Swiping would fight with dragging corners.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Pane(
                    preview: CornerEditor(controller: c),
                    controls: _CornerControls(c: c),
                  ),
                  _Pane(
                    preview: TexturePreview(
                      image: c.masterImage,
                      tiled: c.tiled,
                      smooth: true,
                      busy: c.workingMaster,
                      label: 'Master ${c.settings!.size}×${c.settings!.size}',
                    ),
                    controls: _TextureControls(c: c),
                  ),
                  _Pane(
                    preview: TexturePreview(
                      image: c.consoleImage,
                      tiled: c.tiled,
                      smooth: c.console.smooth,
                      busy: c.workingConsole || c.workingMaster,
                      label:
                          '${c.consoleLabel} · ${formatBytes(c.consoleBytes)}',
                    ),
                    controls: _ConsoleControls(c: c),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SourceList extends StatelessWidget {
  const _SourceList({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (Platform.isAndroid)
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Take a photo'),
          onTap: () => onPick('camera'),
        ),
      ListTile(
        leading: const Icon(Icons.photo_outlined),
        title: const Text('Picture on this device'),
        onTap: () => onPick('gallery'),
      ),
      ListTile(
        leading: const Icon(Icons.folder_shared_outlined),
        title: const Text('Picture from the Asset Locker'),
        onTap: () => onPick('locker'),
      ),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.texture,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Photo → game texture',
                style: t.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Tips: shoot the surface straight on, in soft even light (no '
                'flash, no direct sun, no shadow of you). Fill the frame and '
                'hold still.',
                style: t.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(child: _SourceList(onPick: onPick)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preview with controls beside it (wide) or below it (phone).
class _Pane extends StatelessWidget {
  const _Pane({required this.preview, required this.controls});
  final Widget preview, controls;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final surface = Theme.of(context).colorScheme.surface;
      final panel = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: controls,
      );
      if (box.maxWidth >= 800) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(color: Colors.black, child: preview),
            ),
            SizedBox(
              width: 340,
              child: Material(color: surface, child: panel),
            ),
          ],
        );
      }
      return Column(
        children: [
          Expanded(
            child: ColoredBox(color: Colors.black, child: preview),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.45),
            child: Material(color: surface, child: panel),
          ),
        ],
      );
    },
  );
}

class _CornerControls extends StatelessWidget {
  const _CornerControls({required this.c});
  final TextureController c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final side = quadSide(c.settings!.corners);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Drag the 4 corners onto the corners of the surface. The thick edge '
          'is the top of the texture; the white corner is its top-left.',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'The surface is about ${side.round()} pixels across in the photo.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: c.rotate,
              icon: const Icon(Icons.rotate_right),
              label: const Text('Turn'),
            ),
            OutlinedButton.icon(
              onPressed: c.resetCorners,
              icon: const Icon(Icons.crop_free),
              label: const Text('Whole photo'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TextureControls extends StatelessWidget {
  const _TextureControls({required this.c});
  final TextureController c;

  @override
  Widget build(BuildContext context) {
    final s = c.settings!;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in c.advice)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              a.serious ? Icons.warning_amber : Icons.info_outline,
              color: a.serious ? Colors.orange : null,
            ),
            title: Text(a.title),
            subtitle: Text(a.detail),
          ),
        if (c.advice.isNotEmpty) const Divider(),
        Text('Master size', style: t.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          segments: [
            for (final v in const [256, 512, 1024, 2048])
              ButtonSegment(value: v, label: Text('$v')),
          ],
          selected: {s.size},
          showSelectedIcon: false,
          onSelectionChanged: (v) => c.setMasterSize(v.first),
        ),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Even lighting',
          value: s.lighting,
          text: '${(s.lighting * 100).round()}%',
          onChanged: (v) => c.preview((s) => s.copyWith(lighting: v)),
          onChangeEnd: c.setLighting,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Make seamless'),
          subtitle: const Text('Blends the edges so it tiles without lines'),
          value: s.seamless,
          onChanged: c.setSeamless,
        ),
        if (s.seamless)
          _SliderRow(
            label: 'Edge blend',
            value: s.blend,
            min: 0.05,
            max: 0.45,
            text: '${(s.blend * 100).round()}%',
            onChanged: (v) => c.preview((s) => s.copyWith(blend: v)),
            onChangeEnd: c.setBlend,
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show 3×3 tiled'),
          value: c.tiled,
          onChanged: c.setTiled,
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.text,
    required this.onChanged,
    required this.onChangeEnd,
    this.min = 0,
    this.max = 1,
  });
  final String label, text;
  final double value, min, max;
  final ValueChanged<double> onChanged, onChangeEnd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 110, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
      SizedBox(width: 40, child: Text(text, textAlign: TextAlign.end)),
    ],
  );
}

class _ConsoleControls extends StatelessWidget {
  const _ConsoleControls({required this.c});
  final TextureController c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = c.format;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in consoles)
              ChoiceChip(
                label: Text(p.name),
                selected: p == c.console,
                onSelected: (_) => c.selectConsole(p),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(c.console.about, style: t.bodySmall),
        const SizedBox(height: 10),
        Text('Format', style: t.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final choice in c.console.formats)
              ChoiceChip(
                label: Text(choice.format.label),
                selected: choice == f,
                onSelected: (_) => c.selectFormat(choice),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Size', style: t.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in f.sizes)
              ChoiceChip(
                label: Text('$s'),
                selected: s == c.size,
                onSelected: (_) => c.setSize(s),
              ),
          ],
        ),
        if (f.format.canDither)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dither'),
            subtitle: const Text('Ordered dots instead of colour bands'),
            value: c.dither,
            onChanged: c.setDither,
          ),
        const SizedBox(height: 4),
        Text(
          '${c.size}×${c.size} ${f.format.label}: ${formatBytes(c.consoleBytes)} of video memory'
          '${f.format.colors > 0 && f.format.kind == FormatKind.clut ? ' (palette of ${f.format.colors})' : ''}.',
          style: t.bodySmall,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show 3×3 tiled'),
          value: c.tiled,
          onChanged: c.setTiled,
        ),
      ],
    );
  }
}
