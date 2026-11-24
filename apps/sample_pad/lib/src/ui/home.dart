import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../controller.dart';
import '../library.dart';
import '../output.dart';
import 'loops_view.dart';
import 'pad_editor.dart';
import 'pads_view.dart';
import 'steps_view.dart';
import 'transport_bar.dart';

const loopTimingSetting = SliderSetting(
  key: 'loopTimingMs',
  title: 'Loop timing',
  subtitle: 'Raise if recorded loops sound late, lower if early.',
  defaultValue: 60,
  min: 0,
  max: 300,
  divisions: 60,
  section: 'Loop Station',
  format: _ms,
);

const masterSetting = SliderSetting(
  key: 'master',
  title: 'Master volume',
  defaultValue: 0.8,
  section: 'Sound',
  format: _pct,
);

String _ms(double v) => '${v.round()} ms';
String _pct(double v) => '${(v * 100).round()}%';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller, this.micFactory});

  /// For tests; normally created here with real audio.
  final PadController? controller;
  final MicRecorder Function()? micFactory;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PadController? _c;
  String? _error;
  int _tab = 0;
  bool _edit = false;
  SettingsStore? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settings == null) {
      _settings = Shell.of(context).settings..addListener(_applySettings);
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    try {
      var c = widget.controller;
      if (c == null) {
        final tmp = Directory(
          '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}sample_pad',
        );
        await tmp.create(recursive: true);
        c = PadController(
          output: SoLoudBeatOutput(),
          tempDir: tmp,
          micFactory: widget.micFactory,
        );
        await c.init();
      }
      if (!mounted) return;
      setState(() => _c = c);
      _applySettings();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start audio: $e');
    }
  }

  void _applySettings() {
    final c = _c;
    final s = _settings;
    if (c == null || s == null) return;
    c.latencyMs = s.get(loopTimingSetting);
    c.setMaster(s.get(masterSetting));
  }

  @override
  void dispose() {
    _settings?.removeListener(_applySettings);
    if (widget.controller == null) _c?.dispose();
    super.dispose();
  }

  void _editPad(int pad) {
    final c = _c!;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PadEditorPage(c: c, pad: pad, micFactory: widget.micFactory),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final c = _c;
    if (c == null) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.space) {
      if (e is KeyDownEvent) c.setPlaying(!c.playing);
      return KeyEventResult.handled;
    }
    final label = e.logicalKey.keyLabel.toUpperCase();
    final i = label.length == 1 ? padKeys.indexOf(label) : -1;
    if (i < 0) return KeyEventResult.ignored;
    if (e is KeyDownEvent) c.padDown(i);
    if (e is KeyUpEvent) c.padUp(i);
    return KeyEventResult.handled;
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

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

  Future<bool> _ensureLocker() async {
    final locker = Shell.of(context).locker;
    if (locker.ready || await locker.connect()) return true;
    _snack('Connect the Asset Locker first.');
    return false;
  }

  Future<void> _menu(String action) async {
    final c = _c!;
    final shell = Shell.of(context);
    final lib = PadLibrary(shell.locker);
    try {
      switch (action) {
        case 'new':
          c.newKit();
        case 'load':
          if (!await _ensureLocker() || !mounted) return;
          final info = await pickFromLocker(
            context,
            shell.locker,
            types: const [AssetType.preset],
          );
          if (info == null) return;
          final missing = await lib.loadKit(c, info);
          _snack(
            missing == 0
                ? 'Loaded "${c.kitName}"'
                : 'Loaded "${c.kitName}" ($missing sounds missing)',
          );
        case 'save':
          if (!await _ensureLocker()) return;
          final name = await _askName('Save kit', c.kitName);
          if (name == null) return;
          await lib.saveKit(c, name);
          _snack('Saved kit "$name"');
        case 'mix':
          final bars = await _askBars();
          if (bars == null || !await _ensureLocker()) return;
          final name = await _askName('Save mix', '${c.kitName} mix');
          if (name == null) return;
          await lib.saveMix(c, name, bars);
          _snack('Saved "$name" to Samples');
        case 'share':
          final bars = await _askBars();
          if (bars == null) return;
          final wav = await PadLibrary.renderWav(c, bars);
          await shell.exporter.exportFile(
            '${c.kitName}.wav',
            wav,
            mimeType: 'audio/wav',
          );
      }
    } catch (e) {
      _snack('Something went wrong: $e');
    }
  }

  Future<int?> _askBars() => showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('How many bars?'),
      children: [
        for (final b in [1, 2, 4, 8, 16])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, b),
            child: Text('$b bar${b == 1 ? '' : 's'}'),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sample Pad')),
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
            title: Text(c.kitName, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: _edit ? 'Done editing' : 'Edit pads',
                isSelected: _edit,
                icon: const Icon(Icons.tune),
                selectedIcon: const Icon(Icons.check),
                onPressed: () => setState(() => _edit = !_edit),
              ),
              PopupMenuButton<String>(
                tooltip: 'Kit',
                icon: const Icon(Icons.folder_outlined),
                onSelected: _menu,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'new', child: Text('New kit')),
                  PopupMenuItem(value: 'load', child: Text('Load kit…')),
                  PopupMenuItem(value: 'save', child: Text('Save kit…')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'mix',
                    child: Text('Save mix to Asset Locker…'),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Text('Export mix as WAV…'),
                  ),
                ],
              ),
              ...shellActions(context),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide =
                    box.maxWidth >= 840 && box.maxWidth > box.maxHeight;
                final pads = PadsView(c: c, onEdit: _editPad, editMode: _edit);
                final tabs = SegmentedButton<int>(
                  segments: [
                    if (!wide)
                      const ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.grid_view),
                        label: Text('Pads'),
                      ),
                    const ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.view_week_outlined),
                      label: Text('Steps'),
                    ),
                    const ButtonSegment(
                      value: 2,
                      icon: Icon(Icons.loop),
                      label: Text('Loops'),
                    ),
                  ],
                  selected: {wide && _tab == 0 ? 1 : _tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                );
                final tab = wide && _tab == 0 ? 1 : _tab;
                final panel = switch (tab) {
                  1 => StepsView(c: c),
                  2 => LoopsView(c: c),
                  _ => pads,
                };
                final editHint = _edit
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Tap a pad to edit it',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : const SizedBox.shrink();
                if (wide) {
                  return Column(
                    children: [
                      TransportBar(c: c),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  editHint,
                                  Expanded(child: pads),
                                ],
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: tabs,
                                  ),
                                  Expanded(child: panel),
                                ],
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
                    TransportBar(c: c),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: tabs,
                    ),
                    if (tab == 0) editHint,
                    Expanded(child: panel),
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
