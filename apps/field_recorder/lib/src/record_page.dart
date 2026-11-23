import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'editor_page.dart';
import 'model.dart';

/// Live recording: level, scrolling waveform, timer, markers.
class RecordPage extends StatefulWidget {
  const RecordPage({super.key, required this.takes, this.recorder});

  final Takes takes;

  /// For tests.
  final MicRecorder? recorder;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  late final MicRecorder _mic = widget.recorder ?? MicRecorder();
  File? _file;

  bool get _active =>
      _mic.state == MicState.recording || _mic.state == MicState.paused;

  @override
  void dispose() {
    unawaited(_wake(false));
    if (widget.recorder == null) _mic.dispose();
    super.dispose();
  }

  Future<void> _wake(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {}
  }

  Future<void> _start() async {
    final shell = Shell.of(context);
    shell.tick();
    final file = widget.takes.newFile();
    final ok = await _mic.start(
      file,
      sampleRate: int.parse(shell.settings.get(sampleRateSetting)),
      source: MicSource.byName(shell.settings.get(micSourceSetting)),
    );
    if (ok) {
      _file = file;
      await _wake(true);
    } else if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _stop() async {
    Shell.of(context).tick();
    final info = await _mic.stop();
    await _wake(false);
    final file = _file;
    if (!mounted || info == null || file == null) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage.newTake(
          file: file,
          markers: List.of(_mic.markers),
          takes: widget.takes,
        ),
      ),
    );
  }

  void _marker() {
    Shell.of(context).tick();
    _mic.addMarker();
  }

  void _pauseResume() {
    Shell.of(context).tick();
    _mic.state == MicState.paused ? _mic.resume() : _mic.pause();
  }

  Future<bool> _confirmLeave() async {
    if (!_active) return true;
    final keep = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Still recording'),
        content: const Text('Stop and keep this recording?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Throw away'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop and keep'),
          ),
        ],
      ),
    );
    if (keep == null) return false;
    if (keep) {
      await _stop();
      return false; // _stop already navigated
    }
    await _mic.stop();
    await _file?.delete();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave() && mounted) nav.pop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyR): () =>
              _active ? _stop() : _start(),
          const SingleActivator(LogicalKeyboardKey.space): () {
            if (_active) _pauseResume();
          },
          const SingleActivator(LogicalKeyboardKey.keyM): _marker,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(title: const Text('Record')),
            body: ListenableBuilder(
              listenable: _mic,
              builder: (context, _) => _body(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final state = _mic.state;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final big = Text(
      formatSeconds(_mic.seconds),
      style: text.displayMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        color: state == MicState.paused ? scheme.outline : null,
      ),
    );
    final status = Text(switch (state) {
      MicState.idle => 'Tap the red button to start',
      MicState.starting => 'Starting the microphone…',
      MicState.recording => 'Recording · ${_mic.markers.length} markers',
      MicState.paused => 'Paused',
      MicState.stopping => 'Finishing…',
    }, style: text.bodyMedium);

    final controls = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 28,
        children: [
          _RoundButton(
            tooltip: state == MicState.paused
                ? 'Resume (Space)'
                : 'Pause (Space)',
            icon: state == MicState.paused ? Icons.play_arrow : Icons.pause,
            onPressed: _active ? _pauseResume : null,
          ),
          _RoundButton(
            tooltip: _active ? 'Stop (R)' : 'Record (R)',
            icon: _active ? Icons.stop : Icons.fiber_manual_record,
            size: 84,
            color: scheme.error,
            iconColor: scheme.onError,
            onPressed: state == MicState.starting || state == MicState.stopping
                ? null
                : (_active ? _stop : _start),
          ),
          _RoundButton(
            tooltip: 'Marker (M)',
            icon: Icons.flag_outlined,
            onPressed: _active ? _marker : null,
          ),
        ],
      ),
    );

    final wave = WaveformView(
      peaks: _mic.peaks,
      peaksPerSecond: _mic.peaksPerSecond,
      live: true,
      markers: _mic.markers,
    );
    final meter = GestureDetector(
      onTap: _mic.resetClip,
      child: LevelMeter(level: _mic.level, clipped: _mic.clipped),
    );
    final error = _mic.error;

    final info = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        big,
        const SizedBox(height: 4),
        status,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
          ),
        if (Platform.isAndroid && _active)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Keep this screen open while recording.',
              style: text.bodySmall,
            ),
          ),
      ],
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: landscape
            ? Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Expanded(child: wave),
                        const SizedBox(height: 12),
                        meter,
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [info, const SizedBox(height: 24), controls],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  const SizedBox(height: 8),
                  info,
                  const SizedBox(height: 24),
                  Expanded(child: wave),
                  const SizedBox(height: 12),
                  meter,
                  const SizedBox(height: 32),
                  controls,
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 60,
    this.color,
    this.iconColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        shape: const CircleBorder(),
        color: enabled
            ? (color ?? scheme.secondaryContainer)
            : scheme.surfaceContainerHighest,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              icon,
              size: size * 0.45,
              color: enabled
                  ? (iconColor ?? scheme.onSecondaryContainer)
                  : scheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}
