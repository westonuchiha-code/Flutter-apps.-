import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:beat_kit/beat_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import '../library.dart';
import '../output.dart';
import 'pads_view.dart';

/// Load or record a sound for one pad and shape how it plays.
class PadEditorPage extends StatefulWidget {
  const PadEditorPage({
    super.key,
    required this.c,
    required this.pad,
    this.micFactory,
  });

  final PadController c;
  final int pad;
  final MicRecorder Function()? micFactory;

  @override
  State<PadEditorPage> createState() => _PadEditorPageState();
}

class _PadEditorPageState extends State<PadEditorPage> {
  MicRecorder? _mic;
  File? _micFile;
  bool _busy = false;
  String? _error;

  PadController get c => widget.c;
  int get pad => widget.pad;

  @override
  void dispose() {
    final mic = _mic;
    if (mic != null) unawaited(mic.stop().then((_) => mic.dispose()));
    super.dispose();
  }

  Future<void> _load() async {
    final shell = Shell.of(context);
    final info = await pickFromLocker(
      context,
      shell.locker,
      types: const [AssetType.sample, AssetType.recording],
    );
    if (info == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await PadLibrary(shell.locker).decode(info);
      c.setSample(
        pad,
        data,
        name: info.name,
        assetId: info.id,
        assetType: info.type.name,
      );
      c.setPad(pad, const PadSettings());
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _record() async {
    final mic = (widget.micFactory ?? MicRecorder.new)();
    final file = File(
      '${c.tempDir.path}${Platform.pathSeparator}pad-${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    setState(() {
      _mic = mic;
      _micFile = file;
      _error = null;
    });
    if (!await mic.start(file, sampleRate: engineRate)) {
      setState(() {
        _error = mic.error;
        _mic = null;
      });
      mic.dispose();
    }
  }

  Future<void> _stopRecording() async {
    final mic = _mic;
    final file = _micFile;
    if (mic == null || file == null) return;
    setState(() => _busy = true);
    try {
      await mic.stop();
      final bytes = await file.readAsBytes();
      final data = await Isolate.run(
        () => decodeWavMono(
          bytes,
          targetRate: engineRate,
          maxSeconds: maxSampleSeconds,
        ),
      );
      c.setSample(pad, data, name: 'Mic ${pad + 1}');
      c.setPad(pad, const PadSettings());
      c.trimSilence(pad);
    } catch (e) {
      _error = '$e';
    } finally {
      mic.dispose();
      if (await file.exists()) await file.delete();
      if (mounted) {
        setState(() {
          _mic = null;
          _busy = false;
        });
      }
    }
  }

  Future<void> _rename() async {
    final ctl = TextEditingController(text: c.pads[pad].name);
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pad name'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (v != null) c.renamePad(pad, v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final slot = c.pads[pad];
        return Scaffold(
          appBar: AppBar(
            title: Text(
              slot.isEmpty ? 'Pad ${pad + 1}' : '${pad + 1} · ${slot.name}',
            ),
            actions: [
              if (!slot.isEmpty) ...[
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _rename,
                ),
                IconButton(
                  tooltip: 'Clear pad',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => c.setSample(pad, null),
                ),
              ],
            ],
          ),
          body: SafeArea(child: _body(context, slot)),
        );
      },
    );
  }

  Widget _sources(BuildContext context) {
    final mic = _mic;
    if (mic != null) {
      return ListenableBuilder(
        listenable: mic,
        builder: (context, _) => Column(
          children: [
            Text(
              formatSeconds(mic.seconds),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            LevelMeter(level: mic.level, clipped: mic.clipped),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              onPressed: mic.state == MicState.recording
                  ? _stopRecording
                  : null,
            ),
            if (mic.error != null) Text(mic.error!),
          ],
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.tonalIcon(
          icon: const Icon(Icons.folder_open),
          label: const Text('From Asset Locker'),
          onPressed: _busy ? null : _load,
        ),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.mic),
          label: const Text('Record with mic'),
          onPressed: _busy ? null : _record,
        ),
      ],
    );
  }

  Widget _body(BuildContext context, PadSlot slot) {
    final theme = Theme.of(context);
    final s = slot.settings;
    final error = _error;
    final header = Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              error,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
    if (slot.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          header,
          const Text(
            'Put a sound on this pad: pick a sample or recording from the '
            'Asset Locker (WAV, up to 30 seconds), or record one now.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _sources(context),
        ],
      );
    }
    final secs = slot.seconds;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        header,
        SizedBox(
          height: 140,
          child: WaveformView(
            peaks: slot.peaks,
            trimStart: s.start * secs,
            trimEnd: s.end * secs,
            onTrimChanged: (a, b) =>
                c.setPad(pad, s.copyWith(start: a / secs, end: b / secs)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Listener(
              onPointerDown: (_) => c.padDown(pad),
              onPointerUp: (_) => c.padUp(pad),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: padColor(pad, theme.brightness),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${formatSeconds((s.end - s.start) * secs)} of ${formatSeconds(secs)}',
            ),
            const Spacer(),
            TextButton(
              onPressed: () => c.trimSilence(pad),
              child: const Text('Trim silence'),
            ),
          ],
        ),
        const Divider(height: 24),
        _labelled(
          'Pitch',
          '${s.pitch > 0 ? '+' : ''}${s.pitch.round()} semitones',
          Slider(
            value: s.pitch,
            min: -24,
            max: 24,
            divisions: 48,
            onChanged: (v) => c.setPad(pad, s.copyWith(pitch: v)),
          ),
        ),
        _labelled(
          'Volume',
          '${(s.volume * 100).round()}%',
          Slider(
            value: s.volume,
            onChanged: (v) => c.setPad(pad, s.copyWith(volume: v)),
          ),
        ),
        _labelled(
          'Pan',
          s.pan.abs() < 0.05
              ? 'Centre'
              : (s.pan < 0
                    ? 'Left ${(-s.pan * 100).round()}'
                    : 'Right ${(s.pan * 100).round()}'),
          Slider(
            value: s.pan,
            min: -1,
            max: 1,
            divisions: 20,
            onChanged: (v) => c.setPad(pad, s.copyWith(pan: v)),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reverse'),
          value: s.reverse,
          onChanged: (v) => c.setPad(pad, s.copyWith(reverse: v)),
        ),
        const SizedBox(height: 4),
        SegmentedButton<PadMode>(
          segments: [
            for (final m in PadMode.values)
              ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {s.mode},
          showSelectedIcon: false,
          onSelectionChanged: (v) => c.setPad(pad, s.copyWith(mode: v.first)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(switch (s.mode) {
            PadMode.oneShot => 'Plays to the end each tap.',
            PadMode.hold => 'Plays while you hold the pad.',
            PadMode.loop => 'Loops until you tap the pad again.',
          }, style: theme.textTheme.bodySmall),
        ),
        const Divider(height: 32),
        Text('Replace the sound', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _sources(context),
      ],
    );
  }

  Widget _labelled(String label, String value, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value),
          ],
        ),
        child,
      ],
    ),
  );
}
