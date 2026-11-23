import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'model.dart';

/// Trim, mark, play, name, tag and save a recording.
class EditorPage extends StatefulWidget {
  /// A take that was just recorded (or recovered).
  const EditorPage.newTake({
    super.key,
    required File this.file,
    required this.takes,
    this.markers = const [],
  }) : asset = null;

  /// A recording already in the Asset Locker.
  const EditorPage.asset({
    super.key,
    required AssetInfo this.asset,
    required this.takes,
  }) : file = null,
       markers = const [];

  final File? file;
  final AssetInfo? asset;
  final Takes takes;
  final List<double> markers;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

/// Makes the audio player (tests and screenshots swap in a silent one).
ClipPlayer Function() createPlayer = ClipPlayer.new;

class _EditorPageState extends State<EditorPage> {
  final _player = createPlayer();
  final _name = TextEditingController();
  final _tags = TextEditingController();
  File? _file;
  WavInfo? _info;
  Float32List _peaks = Float32List(0);
  List<double> _markers = [];
  double _start = 0, _end = 0, _cursor = 0;
  String? _error;
  bool _busy = false;
  bool _dirty = false;

  bool get _isNew => widget.asset == null;
  double get _length => _info?.seconds ?? 0;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_load(Shell.of(context)));
    }
  }

  @override
  void dispose() {
    _player
      ..removeListener(_onPlayer)
      ..dispose();
    _name.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _onPlayer() {
    if (mounted) setState(() {});
  }

  Future<void> _load(ShellServices shell) async {
    try {
      File file;
      final asset = widget.asset;
      if (asset == null) {
        file = widget.file!;
        _markers = List.of(widget.markers);
        final modified = await file.lastModified();
        _name.text = defaultName(modified);
        _tags.text = shell.settings.get(defaultTagsSetting);
      } else {
        final bytes = await shell.locker.read(asset);
        if (bytes == null) throw Exception('The recording file is missing.');
        file = widget.takes.scratchFile();
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        _markers = [
          for (final m in (asset.extra['markers'] as List?) ?? const [])
            if (m is num) m.toDouble(),
        ];
        _name.text = asset.name;
        _tags.text = asset.tags.join(', ');
      }
      final info = await readWavInfo(file);
      final peaks = await filePeaks(file, info);
      await _player.load(file);
      if (!mounted) return;
      setState(() {
        _file = file;
        _info = info;
        _peaks = peaks;
        _start = 0;
        _end = info.seconds;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _togglePlay() {
    Shell.of(context).tick();
    if (_player.playing) {
      unawaited(_player.stop());
      return;
    }
    final from = (_cursor >= _start && _cursor < _end - 0.05)
        ? _cursor
        : _start;
    unawaited(_player.play(from: from, to: _end));
  }

  double get _playhead => _player.playing ? _player.position : _cursor;

  void _seek(double t) {
    setState(() => _cursor = t);
    if (_player.playing) unawaited(_player.play(from: t, to: _end));
  }

  void _addMarker() {
    Shell.of(context).tick();
    setState(() {
      _markers = [..._markers, _playhead]..sort();
      _dirty = true;
    });
  }

  Future<Uint8List> _trimmedWav() async {
    final info = _info!;
    final rate = info.format.sampleRate;
    return extractWav(
      _file!,
      info,
      (_start * rate).round(),
      (_end * rate).round(),
    );
  }

  Future<void> _save() async {
    final shell = Shell.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final locker = shell.locker;
    final scheme = Theme.of(context).colorScheme;
    if (!locker.ready && !await locker.connect()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Connect the Asset Locker to save.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _player.stop();
      final wav = await _trimmedWav();
      final cut = trimMarkers(_markers, _start, _end);
      final peaks = Float32List.sublistView(
        _peaks,
        (_start * 100).floor().clamp(0, _peaks.length),
        (_end * 100).ceil().clamp(0, _peaks.length),
      );
      final thumb = await waveformPng(
        peaks,
        color: scheme.primary,
        background: scheme.surfaceContainerHighest,
      );
      final extra = <String, Object?>{
        'markers': cut.markers,
        'seconds': double.parse((cut.end - cut.start).toStringAsFixed(3)),
        'sampleRate': _info!.format.sampleRate,
      };
      final name = _name.text.trim().isEmpty ? 'Recording' : _name.text.trim();
      final tags = parseTags(_tags.text);
      final asset = widget.asset;
      if (asset == null) {
        await locker.save(
          type: AssetType.recording,
          name: name,
          tags: tags,
          bytes: wav,
          extension: 'wav',
          thumbnail: thumb,
          extra: extra,
        );
        await widget.file!.delete();
      } else {
        final next = await locker.replace(
          asset,
          wav,
          thumbnail: thumb,
          extra: extra,
        );
        await locker.update(next.copyWith(name: name, tags: tags));
      }
      messenger.showSnackBar(SnackBar(content: Text('Saved "$name"')));
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final shell = Shell.of(context);
    final wav = await _trimmedWav();
    final name = _name.text.trim().isEmpty ? 'recording' : _name.text.trim();
    await shell.exporter.exportFile('$name.wav', wav, mimeType: 'audio/wav');
  }

  Future<void> _discard() async {
    final nav = Navigator.of(context);
    final asset = widget.asset;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          asset == null
              ? 'Throw away this recording?'
              : 'Delete "${asset.name}"?',
        ),
        content: Text(
          asset == null
              ? 'It has not been saved.'
              : 'It is removed for every app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _player.stop();
    if (asset == null) {
      await widget.file!.delete();
    } else if (mounted) {
      await Shell.of(context).locker.delete(asset);
    }
    nav.pop();
  }

  Future<void> _confirmLeave() async {
    final nav = Navigator.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: Text(
          _isNew
              ? 'The recording stays under "Unsaved" so you can come back to it.'
              : 'Your changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'leave'),
            child: const Text('Leave'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == 'leave') {
      await _player.stop();
      nav.pop();
    } else if (choice == 'save') {
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canLeave = !_isNew && !_dirty;
    return PopScope(
      canPop: canLeave || _info == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _togglePlay,
          const SingleActivator(LogicalKeyboardKey.keyM): _addMarker,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(_isNew ? 'New recording' : 'Edit recording'),
              actions: [
                IconButton(
                  tooltip: 'Export WAV',
                  icon: const Icon(Icons.ios_share),
                  onPressed: _info == null ? null : _export,
                ),
                IconButton(
                  tooltip: _isNew ? 'Throw away' : 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _info == null ? null : _discard,
                ),
              ],
            ),
            body: _content(context),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
    }
    final info = _info;
    if (info == null) return const Center(child: CircularProgressIndicator());
    final text = Theme.of(context).textTheme;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final wave = WaveformView(
      peaks: _peaks,
      markers: _markers,
      trimStart: _start,
      trimEnd: _end,
      position: _playhead,
      onTrimChanged: (s, e) => setState(() {
        _start = s;
        _end = e;
        _dirty = true;
        if (_cursor < s || _cursor > e) _cursor = s;
      }),
      onSeek: _seek,
    );
    final times = Wrap(
      spacing: 16,
      children: [
        Text('Start ${formatSeconds(_start)}'),
        Text('End ${formatSeconds(_end)}'),
        Text('Length ${formatSeconds(_end - _start)}'),
        Text(info.format.toString(), style: text.bodySmall),
      ],
    );
    final transport = Row(
      children: [
        IconButton.filled(
          iconSize: 32,
          tooltip: _player.playing ? 'Stop (Space)' : 'Play (Space)',
          icon: Icon(_player.playing ? Icons.stop : Icons.play_arrow),
          onPressed: _togglePlay,
        ),
        const SizedBox(width: 8),
        Text(formatSeconds(_playhead), style: text.titleMedium),
        const Spacer(),
        OutlinedButton.icon(
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Marker'),
          onPressed: _addMarker,
        ),
        if (_start > 0 || _end < _length) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(() {
              _start = 0;
              _end = _length;
            }),
            child: const Text('Undo trim'),
          ),
        ],
      ],
    );
    final markers = _markers.isEmpty
        ? Text(
            'Drag the handles to trim. Tap the waveform to move the playhead.',
            style: text.bodySmall,
          )
        : Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _markers.length; i++)
                InputChip(
                  avatar: const Icon(Icons.flag, size: 16),
                  label: Text(formatSeconds(_markers[i])),
                  onPressed: () => _seek(_markers[i]),
                  onDeleted: () => setState(() {
                    _markers = [..._markers]..removeAt(i);
                    _dirty = true;
                  }),
                ),
            ],
          );
    final fields = Column(
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => _dirty = true,
        ),
        TextField(
          controller: _tags,
          decoration: const InputDecoration(
            labelText: 'Tags',
            hintText: 'outdoors, birds, rain',
          ),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isNew ? 'Save to Asset Locker' : 'Save changes'),
            onPressed: _busy ? null : _save,
          ),
        ),
      ],
    );
    if (landscape) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Expanded(child: wave),
                    const SizedBox(height: 8),
                    transport,
                    times,
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: ListView(children: [markers, fields])),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(height: 180, child: wave),
          const SizedBox(height: 8),
          times,
          const SizedBox(height: 8),
          transport,
          const SizedBox(height: 8),
          markers,
          const SizedBox(height: 8),
          fields,
        ],
      ),
    );
  }
}
