import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/theremin_controller.dart';
import 'play_area.dart';
import 'recordings_page.dart';
import 'scope_view.dart';
import 'settings_panel.dart';
import 'sound_picker.dart';

class ThereminPage extends StatefulWidget {
  const ThereminPage({super.key, required this.controller});

  final ThereminController controller;

  @override
  State<ThereminPage> createState() => _ThereminPageState();
}

class _ThereminPageState extends State<ThereminPage>
    with WidgetsBindingObserver {
  ThereminController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.toast.addListener(_showToast);
  }

  @override
  void dispose() {
    controller.toast.removeListener(_showToast);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _showToast() {
    final message = controller.toast.value;
    if (message == null || !mounted) return;
    controller.toast.value = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openRecordings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordingsPage(controller: controller),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera in the background (required on Android).
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(controller.pause());
      case AppLifecycleState.resumed:
        if (controller.initialized) unawaited(controller.resume());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: SettingsPanel(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Optical Theremin'),
            actions: [
              IconButton(
                tooltip: 'Recordings',
                icon: const Icon(Icons.library_music_outlined),
                onPressed: _openRecordings,
              ),
              if (!wide)
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.tune),
                  onPressed: _openSettings,
                ),
            ],
          ),
          body: SafeArea(
            child: wide
                ? Row(
                    children: [
                      Expanded(child: _PlayColumn(controller: controller)),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 380,
                        child: SettingsPanel(controller: controller),
                      ),
                    ],
                  )
                : _PlayColumn(controller: controller),
          ),
        );
      },
    );
  }
}

class _PlayColumn extends StatelessWidget {
  const _PlayColumn({required this.controller});

  final ThereminController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (!c.initialized) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = <(String, bool)>[
          if (c.audioError != null) (c.audioError!, true),
          if (c.cameraError != null) (c.cameraError!, true),
          if (c.calibrationMessage != null)
            (c.calibrationMessage!, !c.calibrated),
          if (!c.usingTouch &&
              !c.calibrated &&
              !c.calibrating &&
              c.calibrationMessage == null &&
              c.frame != null)
            (
              'Tip: tap Calibrate for the best response to your lighting.',
              false,
            ),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              for (final (text, isError) in messages)
                _Banner(text: text, isError: isError),
              SoundPicker(
                spec: c.settings.sound,
                onChanged: c.updateSound,
                dense: true,
              ),
              const SizedBox(height: 12),
              Expanded(child: PlaySurface(controller: c)),
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: Row(
                  children: [
                    Expanded(child: NoteReadout(controller: c)),
                    const SizedBox(width: 12),
                    Expanded(child: ScopeView(data: c.scope)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                      onPressed: c.audioError != null ? null : c.togglePlaying,
                      icon: Icon(c.playing ? Icons.stop : Icons.play_arrow),
                      label: Text(c.playing ? 'Stop' : 'Play'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        backgroundColor: c.recording
                            ? Colors.red
                            : Colors.red.shade900,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: c.audioError != null
                          ? null
                          : c.toggleRecording,
                      icon: Icon(
                        c.recording
                            ? Icons.stop_circle_outlined
                            : Icons.fiber_manual_record,
                      ),
                      label: Text(
                        c.recording
                            ? formatDuration(c.recordingTime)
                            : 'Record',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed:
                          c.usingTouch || c.calibrating || c.frame == null
                          ? null
                          : c.calibrate,
                      icon: const Icon(Icons.wb_sunny_outlined),
                      label: const Text('Calibrate'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isError ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.info_outline,
                color: isError
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: isError
                        ? scheme.onErrorContainer
                        : scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
