import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import '../output.dart';
import '../patch.dart';
import '../shape.dart';
import 'image_import.dart';
import 'sound_sheet.dart';
import 'wave_canvas.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});

  /// For tests; normally created here with real audio.
  final PainterController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PainterController? _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      var c = widget.controller;
      if (c == null) {
        c = PainterController(SoLoudWaveOutput());
        await c.init();
      }
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start audio: $e');
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _c?.dispose();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final c = _c;
    if (c == null) return KeyEventResult.ignored;
    final label = e.logicalKey.keyLabel.toUpperCase();
    if (e is KeyDownEvent &&
        HardwareKeyboard.instance.isControlPressed &&
        label == 'Z') {
      c.undo();
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent && label == 'Z') {
      c.setOctave(c.octave - 1);
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent && label == 'X') {
      c.setOctave(c.octave + 1);
      return KeyEventResult.handled;
    }
    final i = label.length == 1 ? pianoKeys.indexOf(label) : -1;
    if (i < 0) return KeyEventResult.ignored;
    final note = (c.octave + 1) * 12 + i;
    if (e is KeyDownEvent) c.noteOn(note);
    if (e is KeyUpEvent) c.noteOff(note);
    return KeyEventResult.handled;
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

  Future<bool> _locker() async {
    final l = Shell.of(context).locker;
    if (l.ready || await l.connect()) return true;
    _snack('Connect the Asset Locker first.');
    return false;
  }

  Future<Uint8List> _thumb(PainterController c) => waveformPng(
    Float32List.fromList([
      for (final v in c.buildTable().cycleAt(c.morph)) v.abs(),
    ]),
  );

  Future<void> _menu(String action) async {
    final c = _c!;
    final shell = Shell.of(context);
    final locker = shell.locker;
    try {
      switch (action) {
        case 'new':
          c.loadPatch(
            WavePatch(
              name: 'New wave',
              waves: [WavePreset.sine.build()],
              spec: defaultSpec,
            ),
          );
        case 'rename':
          final n = await _askName('Rename', c.name);
          if (n != null) setState(() => c.name = n);
        case 'load':
          if (!await _locker() || !mounted) return;
          final info = await pickFromLocker(
            context,
            locker,
            types: const [AssetType.preset],
          );
          if (info == null) return;
          final bytes = await locker.read(info);
          if (bytes == null) throw StateError('The file is missing.');
          c.loadPatch(WavePatch.fromJson(jsonDecode(utf8.decode(bytes))));
          _snack('Loaded "${c.name}"');
        case 'save':
          if (!await _locker()) return;
          final n = await _askName('Save wave', c.name);
          if (n == null) return;
          c.name = n;
          await locker.save(
            type: AssetType.preset,
            name: n,
            bytes: utf8.encode(
              const JsonEncoder.withIndent(' ').convert(c.toPatch().toJson()),
            ),
            extension: 'json',
            thumbnail: await _thumb(c),
            tags: const ['wavetable', 'waveform painter'],
            extra: {'kind': WavePatch.kind, 'waves': c.waves.length},
          );
          _snack('Saved "$n" to Presets');
        case 'note':
          if (!await _locker()) return;
          final n = await _askName('Save a note as a sample', '${c.name} C4');
          if (n == null) return;
          final table = c.buildTable();
          final spec = c.spec;
          final morph = c.morph;
          final wav = await Isolate.run(
            () =>
                renderNote(table, spec, morph, PainterController.noteHz(60), 2),
          );
          await locker.save(
            type: AssetType.sample,
            name: n,
            bytes: wav,
            extension: 'wav',
            thumbnail: await waveformPng(
              floatPeaks(decodeWavMono(wav), synthRate ~/ 100),
            ),
            tags: const ['waveform painter', 'note'],
            extra: {'seconds': 2.0, 'note': 'C4'},
          );
          _snack('Saved "$n" to Samples (load it on a Sample Pad pad)');
        case 'cycle':
          if (!await _locker()) return;
          final n = await _askName('Save single-cycle WAV', c.name);
          if (n == null) return;
          await locker.save(
            type: AssetType.sample,
            name: n,
            bytes: c.singleCycleWav(),
            extension: 'wav',
            thumbnail: await _thumb(c),
            tags: const ['single cycle', 'waveform painter'],
          );
          _snack('Saved "$n" to Samples');
        case 'share':
          await shell.exporter.exportFile(
            '${c.name}.wav',
            c.singleCycleWav(),
            mimeType: 'audio/wav',
          );
      }
    } catch (e) {
      _snack('Something went wrong: $e');
    }
  }

  Future<void> _fromImage() async {
    final c = _c!;
    final w = await importWaveFromImage(context);
    if (w != null) c.apply((_) => w);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Waveform Painter')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Text(_error!),
        ),
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: () => _menu('rename'),
              child: Text(c.name, overflow: TextOverflow.ellipsis),
            ),
            actions: [
              IconButton(
                tooltip: 'Undo (Ctrl+Z)',
                icon: const Icon(Icons.undo),
                onPressed: c.canUndo ? c.undo : null,
              ),
              PopupMenuButton<String>(
                tooltip: 'Wave',
                icon: const Icon(Icons.folder_outlined),
                onSelected: _menu,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'new', child: Text('New wave')),
                  PopupMenuItem(value: 'rename', child: Text('Rename…')),
                  PopupMenuItem(value: 'load', child: Text('Load wave…')),
                  PopupMenuItem(value: 'save', child: Text('Save wave…')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'note',
                    child: Text('Save a note as a sample…'),
                  ),
                  PopupMenuItem(
                    value: 'cycle',
                    child: Text('Save single-cycle WAV…'),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Text('Export single-cycle WAV…'),
                  ),
                ],
              ),
              ...shellActions(context),
            ],
          ),
          body: SafeArea(child: _body(context, c)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, PainterController c) {
    final waveTabs = Row(
      children: [
        for (var i = 0; i < c.waves.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(String.fromCharCode(65 + i)),
              selected: c.selected == i,
              onSelected: (_) => c.select(i),
            ),
          ),
        if (c.waves.length < maxWaves)
          IconButton(
            tooltip: 'Add a wave to morph to',
            icon: const Icon(Icons.add),
            onPressed: c.addWave,
          ),
        if (c.waves.length > 1)
          IconButton(
            tooltip: 'Remove this wave',
            icon: const Icon(Icons.remove),
            onPressed: c.removeWave,
          ),
        const Spacer(),
        SegmentedButton<DrawTool>(
          segments: const [
            ButtonSegment(
              value: DrawTool.pen,
              icon: Icon(Icons.gesture),
              tooltip: 'Freehand',
            ),
            ButtonSegment(
              value: DrawTool.line,
              icon: Icon(Icons.show_chart),
              tooltip: 'Line',
            ),
          ],
          selected: {c.tool},
          showSelectedIcon: false,
          onSelectionChanged: (s) => c.setTool(s.first),
        ),
      ],
    );
    final tools = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          PopupMenuButton<WavePreset>(
            tooltip: 'Start from a shape',
            onSelected: (p) => c.apply((_) => p.build()),
            itemBuilder: (context) => [
              for (final p in WavePreset.values)
                PopupMenuItem(value: p, child: Text(p.label)),
            ],
            child: const Chip(
              avatar: Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text('Shapes'),
            ),
          ),
          for (final (label, icon, op) in [
            ('Smooth', Icons.blur_on, smooth),
            ('Mirror', Icons.flip, mirror),
            ('Normalize', Icons.height, normalize),
            ('Invert', Icons.swap_vert, invert),
            ('Reverse', Icons.swap_horiz, reverse),
          ])
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ActionChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                onPressed: () => c.apply(op),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ActionChip(
              avatar: const Icon(Icons.image_outlined, size: 18),
              label: const Text('From picture'),
              onPressed: _fromImage,
            ),
          ),
        ],
      ),
    );
    final playRow = Row(
      children: [
        IconButton(
          tooltip: 'Octave down (Z)',
          icon: const Icon(Icons.chevron_left),
          onPressed: c.octave > 1 ? () => c.setOctave(c.octave - 1) : null,
        ),
        Text('C${c.octave}'),
        IconButton(
          tooltip: 'Octave up (X)',
          icon: const Icon(Icons.chevron_right),
          onPressed: c.octave < 7 ? () => c.setOctave(c.octave + 1) : null,
        ),
        if (c.waves.length > 1) ...[
          const SizedBox(width: 4),
          const Text('Morph'),
          Expanded(
            child: Slider(value: c.morph, onChanged: c.setMorph),
          ),
        ] else
          const Spacer(),
        IconButton.filledTonal(
          tooltip: 'Sound',
          icon: const Icon(Icons.tune),
          onPressed: () => showSoundSheet(context, c),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final landscape = box.maxWidth > box.maxHeight;
        final keysHeight = landscape
            ? (box.maxHeight * 0.32).clamp(90.0, 170.0)
            : 150.0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            children: [
              waveTabs,
              const SizedBox(height: 6),
              Expanded(child: WaveCanvas(c: c)),
              const SizedBox(height: 6),
              tools,
              playRow,
              SizedBox(
                height: keysHeight,
                child: PianoKeyboard(
                  baseNote: (c.octave + 1) * 12,
                  isDown: c.isDown,
                  onNoteOn: c.noteOn,
                  onNoteOff: c.noteOff,
                  repaint: c,
                  octaves: box.maxWidth > 700 ? 3 : 2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Picture of one cycle as a line (Asset Locker thumbnail).
Future<Uint8List> waveLinePng(
  Float32List cycle,
  Color color, {
  int width = 256,
  int height = 128,
}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF1B1F27),
  );
  final path = Path();
  for (var x = 0; x < width; x++) {
    final v = cycle[(x * cycle.length / width).floor()];
    final y = (1 - v) / 2 * (height - 16) + 8;
    x == 0 ? path.moveTo(0, y) : path.lineTo(x.toDouble(), y);
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  final img = await rec.endRecording().toImage(width, height);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}
