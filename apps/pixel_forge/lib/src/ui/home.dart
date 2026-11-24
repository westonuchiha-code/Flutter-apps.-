import 'dart:async';
import 'dart:convert';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixel_kit/pixel_kit.dart' as px;

import '../editor.dart';
import '../library.dart';
import '../map_editor.dart';
import 'map_page.dart';
import 'pictures.dart';
import 'timeline.dart';
import 'canvas_view.dart';
import 'panels.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.editor});

  /// For tests.
  final Editor? editor;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Editor e = widget.editor ?? Editor();
  final _canvasKey = GlobalKey<CanvasViewState>();
  AssetInfo? _openAsset;
  bool _busy = false;

  @override
  void dispose() {
    if (widget.editor == null) e.dispose();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<bool> _locker() async {
    final l = Shell.of(context).locker;
    if (l.ready || await l.connect()) return true;
    _snack('Connect the Asset Locker first.');
    return false;
  }

  Future<void> _guard(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } catch (err) {
      _snack('Something went wrong: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName(String title, String initial) async {
    final ctl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctl.dispose();
    return v == null || v.isEmpty ? null : v;
  }

  Future<(int, int)?> _askSize(String title, int w, int h) async {
    var cw = w, ch = h;
    return showDialog<(int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in [8, 16, 24, 32, 48, 64, 128, 256])
                    ChoiceChip(
                      label: Text('$s×$s'),
                      selected: cw == s && ch == s,
                      onSelected: (_) => set(() {
                        cw = s;
                        ch = s;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('w$cw'),
                      initialValue: '$cw',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Width'),
                      onChanged: (v) => cw = int.tryParse(v) ?? cw,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('h$ch'),
                      initialValue: '$ch',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Height'),
                      onChanged: (v) => ch = int.tryParse(v) ?? ch,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Up to ${px.Sprite.maxSize}×${px.Sprite.maxSize}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                cw.clamp(1, px.Sprite.maxSize),
                ch.clamp(1, px.Sprite.maxSize),
              )),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    if (!e.dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text(
          '"${e.name}" has changes that are not saved. Throw them away?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Throw away'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _menu(String action) async {
    final shell = Shell.of(context);
    final lib = ForgeLibrary(shell.locker);
    switch (action) {
      case 'new':
        if (!await _confirmDiscard()) return;
        final size = await _askSize('New sprite', 32, 32);
        if (size == null) return;
        e.load(px.Sprite.blank(size.$1, size.$2), 'Untitled');
        _openAsset = null;
      case 'open':
        if (!await _confirmDiscard() || !await _locker() || !mounted) return;
        final info = await pickFromLocker(
          context,
          shell.locker,
          types: const [AssetType.sprite, AssetType.other],
        );
        if (info == null) return;
        await _guard(() async {
          final s = await lib.open(info);
          e.load(s, info.name);
          _openAsset = info.extension == 'json' ? info : null;
        });
      case 'save':
      case 'saveAs':
        if (!await _locker()) return;
        if (action == 'saveAs' || _openAsset == null) {
          final n = await _askName('Save sprite', e.name);
          if (n == null) return;
          e.name = n;
          _openAsset = null;
        }
        await _guard(() async {
          _openAsset = await lib.saveSprite(e, replace: _openAsset);
          e.markSaved();
          _snack('Saved "${e.name}" to Sprites');
        });
      case 'png':
        final scale = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('PNG size'),
            children: [
              for (final s in [1, 2, 4, 8, 16])
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, s),
                  child: Text(
                    '×$s (${e.sprite.width * s}×${e.sprite.height * s})',
                  ),
                ),
            ],
          ),
        );
        if (scale == null || !mounted) return;
        final where = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Where to?'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'locker'),
                child: const Text('Asset Locker (Sprites)'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'share'),
                child: const Text('Export / share'),
              ),
            ],
          ),
        );
        if (where == null) return;
        if (where == 'locker' && !await _locker()) return;
        await _guard(() async {
          if (where == 'locker') {
            await lib.exportPng(e, scale);
            _snack('Saved PNG to Sprites');
          } else {
            await shell.exporter.exportFile(
              '${e.name}.png',
              px.spriteToPng(e.sprite, frame: e.frame, scale: scale),
              mimeType: 'image/png',
            );
          }
        });
      case 'sheet':
      case 'gif':
        final isGif = action == 'gif';
        final scale = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(isGif ? 'GIF size' : 'Sprite sheet size'),
            children: [
              for (final sc in [1, 2, 4, 8])
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, sc),
                  child: Text('×$sc'),
                ),
            ],
          ),
        );
        if (scale == null || !mounted) return;
        final where = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Where to?'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'locker'),
                child: const Text('Asset Locker (Sprites)'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'share'),
                child: const Text('Export / share'),
              ),
            ],
          ),
        );
        if (where == null) return;
        if (where == 'locker' && !await _locker()) return;
        await _guard(() async {
          final n = e.sprite.frames.length;
          final cols = n <= 8 ? 0 : (n / 2).ceil().clamp(1, 16);
          final bytes = isGif
              ? px.spriteToGif(e.sprite, scale: scale)
              : px.spriteSheetPng(e.sprite, columns: cols, scale: scale);
          final ext = isGif ? 'gif' : 'png';
          final label = isGif ? '${e.name} (animated)' : '${e.name} (sheet)';
          if (where == 'locker') {
            await shell.locker.save(
              type: AssetType.sprite,
              name: label,
              bytes: bytes,
              extension: ext,
              thumbnail: ForgeLibrary.thumbnail(e.sprite),
              tags: ['pixel forge', ext],
              extra: {
                'frames': n,
                'frameWidth': e.sprite.width * scale,
                'frameHeight': e.sprite.height * scale,
              },
            );
            _snack('Saved "$label" to Sprites');
          } else {
            await shell.exporter.exportFile(
              '${e.name}.$ext',
              bytes,
              mimeType: isGif ? 'image/gif' : 'image/png',
            );
          }
        });
      case 'picture':
        final pic = await pickPicture(context);
        if (pic == null || !mounted) return;
        final opts = await askImportOptions(context);
        if (opts == null) return;
        e.importPicture(pic, snap: opts.$1, dither: opts.$2);
      case 'map':
        final size = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Tile size'),
            children: [
              for (final t in [8, 16, 32])
                if (t <= e.sprite.width && t <= e.sprite.height)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, t),
                    child: Text('$t×$t pixels'),
                  ),
            ],
          ),
        );
        if (size == null || !mounted) return;
        final m = MapEditor.fromPicture(
          e.sprite.flatten(e.frame),
          e.sprite.width,
          e.sprite.height,
          size,
        )..name = '${e.name} map';
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MapPage(map: m, sprite: e),
          ),
        );
      case 'openMap':
        if (!await _locker() || !mounted) return;
        final info = await pickFromLocker(
          context,
          shell.locker,
          types: const [AssetType.map],
        );
        if (info == null || !mounted) return;
        px.TileMap? map;
        await _guard(() async {
          final bytes = await shell.locker.read(info);
          if (bytes == null) throw StateError('The file is missing.');
          map = px.TileMap.fromJson(jsonDecode(utf8.decode(bytes)));
        });
        if (map == null || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MapPage(
              map: MapEditor(map!, name: info.name),
              sprite: e,
              asset: info,
            ),
          ),
        );
      case 'resize':
        final size = await _askSize(
          'Canvas size',
          e.sprite.width,
          e.sprite.height,
        );
        if (size != null) e.resize(size.$1, size.$2);
      case 'fit':
        _canvasKey.currentState?.fit();
    }
  }

  Future<void> _palettes() async {
    final shell = Shell.of(context);
    final lib = ForgeLibrary(shell.locker);
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            for (final p in px.builtInPalettes)
              ListTile(
                title: Text(p.name),
                subtitle: Wrap(
                  children: [
                    for (final c in p.colors.take(32))
                      Container(width: 12, height: 12, color: toColor(c)),
                  ],
                ),
                onTap: () => Navigator.pop(context, p),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Colours used in this sprite'),
              onTap: () => Navigator.pop(context, 'used'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Load from Asset Locker…'),
              onTap: () => Navigator.pop(context, 'load'),
            ),
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: const Text('Save this palette to Asset Locker'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add the current colour to this palette'),
              onTap: () => Navigator.pop(context, 'add'),
            ),
            ListTile(
              leading: const Icon(Icons.filter_vintage_outlined),
              title: const Text('Snap the whole sprite to this palette'),
              subtitle: const Text(
                'Every pixel becomes the nearest palette colour',
              ),
              onTap: () => Navigator.pop(context, 'reduce'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case px.Palette():
        e.setPalette(choice);
      case 'photo':
        final pic = await pickPicture(context);
        if (pic == null || !mounted) return;
        final p = await askPhotoPalette(context, pic);
        if (p != null && p.colors.isNotEmpty) e.setPalette(p);
      case 'used':
        final p = e.paletteFromSprite();
        if (p.colors.isEmpty) {
          _snack('Nothing drawn yet.');
        } else {
          e.setPalette(p);
        }
      case 'add':
        if (e.primary != 0 && !e.palette.colors.contains(e.primary)) {
          e.setPalette(
            px.Palette(e.palette.name, [...e.palette.colors, e.primary]),
          );
        }
      case 'reduce':
        e.reduceToPalette();
      case 'save':
        if (!await _locker()) return;
        final n = await _askName('Save palette', e.palette.name);
        if (n == null) return;
        await _guard(() async {
          await lib.savePalette(px.Palette(n, e.palette.colors));
          _snack('Saved palette "$n"');
        });
      case 'load':
        if (!await _locker() || !mounted) return;
        final info = await pickFromLocker(
          context,
          shell.locker,
          types: const [AssetType.palette],
        );
        if (info == null) return;
        await _guard(() async => e.setPalette(await lib.openPalette(info)));
    }
  }

  Future<void> _editColor() async {
    final c = await editColor(context, e.primary);
    if (c != null) e.setPrimary(c);
  }

  void _layersSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ListenableBuilder(
            listenable: e,
            builder: (context, _) => LayersPanel(e: e),
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final k = ev.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      shift ? e.redo() : e.undo();
    } else if (ctrl && k == LogicalKeyboardKey.keyY) {
      e.redo();
    } else if (ctrl && k == LogicalKeyboardKey.keyC) {
      e.copySelection();
    } else if (ctrl && k == LogicalKeyboardKey.keyV) {
      e.paste();
    } else if (ctrl && k == LogicalKeyboardKey.keyA) {
      e.selectAll();
    } else if (ctrl && k == LogicalKeyboardKey.keyS) {
      unawaited(_menu('save'));
    } else if (k == LogicalKeyboardKey.delete ||
        k == LogicalKeyboardKey.backspace) {
      e.deleteSelection();
    } else if (k == LogicalKeyboardKey.escape) {
      e.deselect();
    } else if (k == LogicalKeyboardKey.keyX) {
      e.swapColors();
    } else if (k == LogicalKeyboardKey.bracketLeft) {
      e.setBrush(e.brushSize - 1);
    } else if (k == LogicalKeyboardKey.bracketRight) {
      e.setBrush(e.brushSize + 1);
    } else {
      final label = k.keyLabel.toUpperCase();
      final tool = Tool.values.where((t) => t.key == label).firstOrNull;
      if (tool == null) return KeyEventResult.ignored;
      e.setTool(tool);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: e,
      builder: (context, _) => Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: () async {
                final n = await _askName('Rename', e.name);
                if (n != null) setState(() => e.name = n);
              },
              child: Text(
                '${e.name}${e.dirty ? ' •' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Undo (Ctrl+Z)',
                icon: const Icon(Icons.undo),
                onPressed: e.canUndo ? e.undo : null,
              ),
              IconButton(
                tooltip: 'Redo (Ctrl+Y)',
                icon: const Icon(Icons.redo),
                onPressed: e.canRedo ? e.redo : null,
              ),
              PopupMenuButton<String>(
                tooltip: 'Sprite',
                icon: const Icon(Icons.folder_outlined),
                onSelected: _menu,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'new', child: Text('New…')),
                  PopupMenuItem(
                    value: 'open',
                    child: Text('Open from Asset Locker…'),
                  ),
                  PopupMenuItem(value: 'save', child: Text('Save (Ctrl+S)')),
                  PopupMenuItem(value: 'saveAs', child: Text('Save as…')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'png', child: Text('Export PNG…')),
                  PopupMenuItem(
                    value: 'sheet',
                    child: Text('Export sprite sheet…'),
                  ),
                  PopupMenuItem(
                    value: 'gif',
                    child: Text('Export animated GIF…'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'picture',
                    child: Text('Add a picture as a layer…'),
                  ),
                  PopupMenuItem(
                    value: 'map',
                    child: Text('Tile map from this sprite…'),
                  ),
                  PopupMenuItem(
                    value: 'openMap',
                    child: Text('Open a tile map…'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'resize', child: Text('Canvas size…')),
                  PopupMenuItem(value: 'fit', child: Text('Fit to screen')),
                ],
              ),
              ...shellActions(context),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final canvas = CanvasView(key: _canvasKey, editor: e);
                final wide = box.maxWidth >= 900;
                if (wide) {
                  return Column(
                    children: [
                      if (_busy) const LinearProgressIndicator(),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 60,
                              child: ToolBar(e: e, vertical: true),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(child: canvas),
                                  const Divider(height: 1),
                                  Timeline(e: e),
                                ],
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            SizedBox(
                              width: 300,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    ColorBar(
                                      e: e,
                                      onEditColor: _editColor,
                                      onPalettes: _palettes,
                                      grid: true,
                                    ),
                                    const Divider(height: 24),
                                    Expanded(child: LayersPanel(e: e)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    Expanded(child: canvas),
                    const Divider(height: 1),
                    Timeline(e: e),
                    ToolBar(e: e),
                    Row(
                      children: [
                        Expanded(
                          child: ColorBar(
                            e: e,
                            onEditColor: _editColor,
                            onPalettes: _palettes,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Layers',
                          icon: Badge(
                            label: Text('${e.sprite.layers.length}'),
                            child: const Icon(Icons.layers_outlined),
                          ),
                          onPressed: _layersSheet,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
