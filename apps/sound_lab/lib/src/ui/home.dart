import 'dart:async';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:flutter/services.dart';
import 'package:fx_kit/fx_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import '../library.dart';
import '../output.dart';
import 'effects_panel.dart';
import 'scope_view.dart';
import 'source_panel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});

  /// For tests; normally created here with real audio.
  final LabController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  LabController? _c;
  String? _error;
  int _tab = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      var c = widget.controller;
      if (c == null) {
        c = LabController(SoLoudLabOutput());
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

  Future<bool> _locker() async {
    final l = Shell.of(context).locker;
    if (l.ready || await l.connect()) return true;
    _snack('Connect the Asset Locker first.');
    return false;
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

  Future<void> _guard(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      _snack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadWave() async {
    if (!await _locker() || !mounted) return;
    final locker = Shell.of(context).locker;
    final info = await pickFromLocker(
      context,
      locker,
      types: const [AssetType.preset],
    );
    if (info == null) return;
    await _guard(() async {
      final w = wavesFromJson(await LabLibrary(locker).readJson(info));
      if (w == null) {
        _snack(
          '"${info.name}" has no drawn waves. Make one in Waveform Painter.',
        );
        return;
      }
      _c!.setWaves(w.$1, w.$2);
    });
  }

  Future<void> _loadSample() async {
    if (!await _locker() || !mounted) return;
    final locker = Shell.of(context).locker;
    final info = await pickFromLocker(
      context,
      locker,
      types: const [AssetType.sample, AssetType.recording],
    );
    if (info == null) return;
    await _guard(() async {
      final data = await LabLibrary(locker).decodeSample(info);
      _c!.setSample(info.name, data, id: info.id, type: info.type.name);
    });
  }

  Future<void> _menu(String action) async {
    final c = _c!;
    final shell = Shell.of(context);
    final lib = LabLibrary(shell.locker);
    switch (action) {
      case 'new':
        c.applyPreset(
          const SoundPreset(name: 'New sound', source: SourceKind.analog),
        );
        c.setSpec(labDefaultSpec);
      case 'rename':
        final n = await _askName('Rename', c.name);
        if (n != null) setState(() => c.name = n);
      case 'load':
        if (!await _locker() || !mounted) return;
        final info = await pickFromLocker(
          context,
          shell.locker,
          types: const [AssetType.preset],
        );
        if (info == null) return;
        await _guard(() async {
          final note = await lib.loadPreset(c, info);
          _snack(note ?? 'Loaded "${c.name}"');
        });
      case 'save':
        if (!await _locker()) return;
        final n = await _askName('Save sound', c.name);
        if (n == null) return;
        await _guard(() async {
          await lib.savePreset(c, n);
          _snack('Saved "$n" to Presets');
        });
      case 'note':
        if (!await _locker()) return;
        final n = await _askName(
          'Save a note (C4) as a sample',
          '${c.name} C4',
        );
        if (n == null) return;
        await _guard(() async {
          await lib.saveWav(n, await LabLibrary.renderNoteWav(c, 60), const [
            'note',
          ]);
          _snack('Saved "$n" to Samples');
        });
      case 'process':
        if (!await _locker()) return;
        final n = await _askName(
          'Save the processed sample',
          '${c.sampleName} (${c.name})',
        );
        if (n == null) return;
        await _guard(() async {
          await lib.saveWav(n, await LabLibrary.processSampleWav(c), const [
            'processed',
          ]);
          _snack('Saved "$n" to Samples');
        });
      case 'share':
        await _guard(() async {
          final wav = c.source == SourceKind.sample
              ? await LabLibrary.processSampleWav(c)
              : await LabLibrary.renderNoteWav(c, 60);
          await shell.exporter.exportFile(
            '${c.name}.wav',
            wav,
            mimeType: 'audio/wav',
          );
        });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final c = _c;
    if (c == null) return KeyEventResult.ignored;
    final label = e.logicalKey.keyLabel.toUpperCase();
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

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sound Lab')),
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
              PopupMenuButton<String>(
                tooltip: 'Sound',
                icon: const Icon(Icons.folder_outlined),
                onSelected: _menu,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'new', child: Text('New sound')),
                  const PopupMenuItem(value: 'rename', child: Text('Rename…')),
                  const PopupMenuItem(
                    value: 'load',
                    child: Text('Load sound or wave…'),
                  ),
                  const PopupMenuItem(
                    value: 'save',
                    child: Text('Save sound…'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'note',
                    child: Text('Save a note as a sample…'),
                  ),
                  if (c.source == SourceKind.sample)
                    const PopupMenuItem(
                      value: 'process',
                      child: Text('Save processed sample…'),
                    ),
                  const PopupMenuItem(
                    value: 'share',
                    child: Text('Export WAV…'),
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

  Widget _body(BuildContext context, LabController c) {
    final source = SourcePanel(
      c: c,
      onLoadWave: _loadWave,
      onLoadSample: _loadSample,
    );
    final effects = EffectsPanel(c: c);
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 840;
        final landscape = box.maxWidth > box.maxHeight;
        final keysHeight = landscape
            ? (box.maxHeight * 0.26).clamp(80.0, 150.0)
            : 130.0;
        return Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: SizedBox(
                height: landscape && !wide ? 56 : 92,
                child: ScopeView(scope: c.scope),
              ),
            ),
            if (!wide)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 0,
                      icon: const Icon(Icons.graphic_eq),
                      label: Text(_sourceLabel(c.source)),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: const Icon(Icons.tune),
                      label: Text('Effects (${c.fx.length})'),
                    ),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        Expanded(child: source),
                        const VerticalDivider(width: 1),
                        Expanded(child: effects),
                      ],
                    )
                  : (_tab == 0 ? source : effects),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Octave down (Z)',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: c.octave > 1
                        ? () => c.setOctave(c.octave - 1)
                        : null,
                  ),
                  Text('C${c.octave}'),
                  IconButton(
                    tooltip: 'Octave up (X)',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: c.octave < 7
                        ? () => c.setOctave(c.octave + 1)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap the scope for the spectrum',
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: SizedBox(
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
            ),
          ],
        );
      },
    );
  }

  static String _sourceLabel(SourceKind k) => switch (k) {
    SourceKind.analog => 'Analog',
    SourceKind.chip => 'Chip',
    SourceKind.wavetable => 'Wave',
    SourceKind.sample => 'Sample',
  };
}
