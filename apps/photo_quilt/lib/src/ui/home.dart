import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixel_kit/pixel_kit.dart' as pk;

import '../quilt.dart';
import '../work.dart';

const _pictureExtensions = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'];

const seamColors = [0xFFF2EEE4, 0xFFFFFFFF, 0xFF1A1A1A, 0xFF8A6E4B, 0xFFD9534F];

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.photo});

  /// For tests and screenshots.
  final Picture? photo;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Picture? _photo;
  String _name = 'Quilt';
  int _columns = 24;
  double _detail = 0.6;

  /// -1: colours from the photo; otherwise a built-in palette.
  int _paletteIndex = -1;
  int _photoColors = 12;
  List<int> _fromPhoto = const [];
  int _seam = 1;
  int _seamColor = seamColors.first;
  bool _stitches = true, _texture = true;

  Quilt? _quilt;
  ui.Image? _image;
  Picture? _picture;
  bool _busy = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    final p = widget.photo;
    if (p != null) {
      unawaited(_setPhoto(p, 'Quilt'));
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  List<int> get _palette =>
      _paletteIndex < 0 ? _fromPhoto : pk.builtInPalettes[_paletteIndex].colors;

  QuiltSettings get _settings => QuiltSettings(
    columns: _columns,
    palette: _palette,
    detail: _detail,
    patchSize: _columns <= 24 ? 32 : 24,
    seam: _seam,
    seamColor: _seamColor,
    stitches: _stitches,
    texture: _texture,
  );

  Future<void> _setPhoto(Picture p, String name) async {
    _photo = p;
    _name = name;
    _fromPhoto = await runInBackground(photoPalette, (p, _photoColors));
    await _rebuild();
  }

  Future<void> _rebuild({bool newPalette = false}) async {
    final p = _photo;
    if (p == null) {
      return;
    }
    final gen = ++_gen;
    setState(() => _busy = true);
    if (newPalette) {
      _fromPhoto = await runInBackground(photoPalette, (p, _photoColors));
    }
    final (q, pic) = await runInBackground(buildQuilt, (p, _settings));
    if (gen != _gen || !mounted) {
      return;
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pic.pixels.buffer.asUint8List(),
      pic.width,
      pic.height,
      ui.PixelFormat.bgra8888,
      c.complete,
    );
    final image = await c.future;
    if (gen != _gen || !mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _quilt = q;
      _picture = pic;
      _busy = false;
    });
  }

  Future<void> _open() async {
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
    if (source == null || !mounted) {
      return;
    }
    try {
      Uint8List? bytes;
      var name = 'Quilt';
      if (source == 'locker') {
        final locker = shell.locker;
        if (!locker.ready && !await locker.connect()) {
          return;
        }
        if (!mounted) {
          return;
        }
        final info = await pickFromLocker(
          context,
          locker,
          types: const [AssetType.picture, AssetType.other],
        );
        if (info == null) {
          return;
        }
        if (!_pictureExtensions.contains(info.extension.toLowerCase())) {
          _snack('"${info.name}" is not a picture.');
          return;
        }
        bytes = await locker.read(info);
        name = '${info.name} quilt';
      } else {
        final file = await ImagePicker().pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
        );
        bytes = await file?.readAsBytes();
      }
      if (bytes == null) {
        return;
      }
      setState(() => _busy = true);
      final p = await runInBackground(decodePhoto, bytes);
      if (p == null) {
        _snack('That picture could not be opened.');
        setState(() => _busy = false);
        return;
      }
      await _setPhoto(p, name);
    } catch (e) {
      if (mounted) {
        _snack('Could not open the picture: $e');
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save(String how) async {
    final pic = _picture;
    if (pic == null) {
      return;
    }
    final shell = Shell.of(context);
    try {
      if (how == 'palette') {
        final locker = shell.locker;
        if (!locker.ready && !await locker.connect()) {
          return;
        }
        final pal = pk.Palette('$_name colours', _palette);
        await locker.save(
          type: AssetType.palette,
          name: pal.name,
          bytes: utf8.encode(jsonEncode(pal.toJson())),
          extension: 'json',
          tags: const ['photo quilt'],
          extra: {'kind': pk.Palette.kind, 'colors': pal.colors.length},
        );
        _snack('Palette saved: use it in Pixel Forge.');
        return;
      }
      final png = await runInBackground(encodePng, pic);
      if (how == 'locker') {
        final locker = shell.locker;
        if (!locker.ready && !await locker.connect()) {
          return;
        }
        await locker.save(
          type: AssetType.picture,
          name: _name,
          bytes: png,
          extension: 'png',
          tags: const ['photo quilt'],
          extra: {
            'columns': _quilt!.columns,
            'rows': _quilt!.rows,
            'colors': _palette.length,
          },
        );
        _snack('Saved to Pictures');
      } else {
        final file = _name
            .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
            .trim()
            .replaceAll(' ', '_');
        await shell.exporter.exportFile(
          '${file.isEmpty ? 'quilt' : file}.png',
          png,
          mimeType: 'image/png',
        );
      }
    } catch (e) {
      if (mounted) {
        _snack('Could not save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photo != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Tile Quilt'),
        actions: [
          IconButton(
            tooltip: 'Open a photo',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _open,
          ),
          if (_picture != null)
            PopupMenuButton<String>(
              tooltip: 'Save',
              icon: const Icon(Icons.save_alt),
              onSelected: _save,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'locker',
                  child: Text('Save quilt to Asset Locker'),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Text('Export / share PNG'),
                ),
                PopupMenuItem(
                  value: 'palette',
                  child: Text('Save the palette (for Pixel Forge)'),
                ),
              ],
            ),
          ...shellActions(context),
        ],
      ),
      body: SafeArea(
        child: !hasPhoto
            ? Center(
                child: _busy
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.grid_view,
                              size: 64,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Turn a photo into a quilt.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _open,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: const Text('Open a photo'),
                            ),
                          ],
                        ),
                      ),
              )
            : LayoutBuilder(
                builder: (context, box) {
                  final preview = Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(0xFF26231F),
                          child: _image == null
                              ? const SizedBox()
                              : InteractiveViewer(
                                  maxScale: 8,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: RawImage(
                                        image: _image,
                                        filterQuality: FilterQuality.medium,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      if (_busy)
                        const Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  );
                  final controls = _controls(context);
                  if (box.maxWidth >= 800) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: preview),
                        SizedBox(width: 360, child: controls),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: preview),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: box.maxHeight * 0.45,
                        ),
                        child: controls,
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _slider(
    String label,
    String value,
    double v,
    double min,
    double max,
    int div,
    ValueChanged<double> onChanged,
    ValueChanged<double> onEnd,
  ) => Row(
    children: [
      SizedBox(width: 92, child: Text(label)),
      Expanded(
        child: Slider(
          value: v,
          min: min,
          max: max,
          divisions: div,
          onChanged: onChanged,
          onChangeEnd: onEnd,
        ),
      ),
      SizedBox(width: 40, child: Text(value, textAlign: TextAlign.end)),
    ],
  );

  Widget _controls(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _quilt;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (q != null)
            Text(
              '${q.columns} × ${q.rows} patches · ${q.counts.entries.map((e) => '${e.value} ${e.key.toLowerCase()}').join(', ')}',
              style: t.bodySmall,
            ),
          _slider(
            'Across',
            '$_columns',
            _columns.toDouble(),
            12,
            64,
            52,
            (v) => setState(() => _columns = v.round()),
            (_) => _rebuild(),
          ),
          _slider(
            'Detail',
            '${(_detail * 100).round()}%',
            _detail,
            0,
            1,
            20,
            (v) => setState(() => _detail = v),
            (_) => _rebuild(),
          ),
          const SizedBox(height: 4),
          Text('Fabric colours', style: t.labelLarge),
          DropdownButton<int>(
            isExpanded: true,
            value: _paletteIndex,
            items: [
              const DropdownMenuItem(value: -1, child: Text('From the photo')),
              for (var i = 0; i < pk.builtInPalettes.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(pk.builtInPalettes[i].name),
                ),
            ],
            onChanged: (v) {
              setState(() => _paletteIndex = v ?? -1);
              unawaited(_rebuild());
            },
          ),
          if (_paletteIndex < 0)
            _slider(
              'Colours',
              '$_photoColors',
              _photoColors.toDouble(),
              4,
              32,
              28,
              (v) => setState(() => _photoColors = v.round()),
              (_) => _rebuild(newPalette: true),
            ),
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final c in _palette)
                Container(width: 18, height: 18, color: Color(c)),
            ],
          ),
          const SizedBox(height: 8),
          _slider(
            'Seams',
            '$_seam px',
            _seam.toDouble(),
            0,
            4,
            4,
            (v) => setState(() => _seam = v.round()),
            (_) => _rebuild(),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final c in seamColors)
                InkWell(
                  onTap: () {
                    setState(() => _seamColor = c);
                    unawaited(_rebuild());
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(c),
                      border: Border.all(
                        color: c == _seamColor ? Colors.amber : Colors.white24,
                        width: c == _seamColor ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Quilting stitches'),
            value: _stitches,
            onChanged: (v) {
              setState(() => _stitches = v);
              unawaited(_rebuild());
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fabric texture'),
            value: _texture,
            onChanged: (v) {
              setState(() => _texture = v);
              unawaited(_rebuild());
            },
          ),
        ],
      ),
    );
  }
}
