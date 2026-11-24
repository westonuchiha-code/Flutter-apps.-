import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_kit/video_kit.dart';

import '../export.dart';
import '../media.dart';
import '../project.dart';

/// Export settings, progress and what to do with the result.
class ExportSheet extends StatefulWidget {
  const ExportSheet({
    super.key,
    required this.project,
    required this.media,
    required this.titles,
    this.test = false,
  });

  final Project project;
  final Map<String, Media> media;
  final Map<String, VideoFrame> titles;

  /// The 2-second self-test: checks this device can make videos.
  final bool test;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  var _size = exportSizes[1];
  var _fps = 30;
  ExportJob? _job;
  double _progress = 0;
  File? _result;
  String? _error;
  final _watch = Stopwatch();

  @override
  void initState() {
    super.initState();
    if (widget.test) unawaited(_run());
  }

  @override
  void dispose() {
    _job?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final job = ExportJob(
      project: widget.project,
      media: widget.media,
      titles: widget.titles,
      width: _size.$1,
      height: _size.$2,
      fps: _fps,
    );
    setState(() {
      _job = job;
      _progress = 0;
      _error = null;
      _result = null;
    });
    job.progress.stream.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
    _watch
      ..reset()
      ..start();
    try {
      final dir = await getTemporaryDirectory();
      final name = widget.project.name
          .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
          .trim()
          .replaceAll(' ', '_');
      final file = await job.run(
        '${dir.path}${Platform.pathSeparator}${name.isEmpty ? 'video' : name}',
      );
      if (mounted) setState(() => _result = file);
      if (file == null && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _watch.stop();
      if (mounted) setState(() => _job = null);
    }
  }

  Future<void> _saveToLocker() async {
    final f = _result!;
    final shell = Shell.of(context);
    final locker = shell.locker;
    if (!locker.ready && !await locker.connect()) return;
    final ext = f.path.split('.').last;
    await locker.save(
      type: AssetType.video,
      name: widget.project.name,
      bytes: await f.readAsBytes(),
      extension: ext,
      tags: ['lofi video'],
      extra: {
        'seconds': widget.project.duration,
        'width': _size.$1,
        'height': _size.$2,
        'fps': _fps,
      },
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved to Videos')));
    }
  }

  Future<void> _share() async {
    final f = _result!;
    final ext = f.path.split('.').last;
    await Shell.of(context).exporter.exportFile(
      f.uri.pathSegments.last,
      await f.readAsBytes(),
      mimeType: ext == 'mp4' ? 'video/mp4' : 'video/x-msvideo',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final result = _result;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.test ? 'Test export' : 'Export video',
              style: t.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_error != null) ...[
              Text(
                'Export failed: $_error',
                style: const TextStyle(color: Colors.orangeAccent),
              ),
              const SizedBox(height: 8),
              Text(
                widget.test
                    ? 'This device could not make an MP4. Please tell Claude what the message says.'
                    : 'Try the Test export in the menu to check this device.',
                style: t.bodySmall,
              ),
            ] else if (result != null) ...[
              Text(
                '${result.path.endsWith('.mp4') ? 'MP4' : 'AVI'}: ${widget.project.duration.toStringAsFixed(1)} s, '
                '${(result.lengthSync() / 1048576).toStringAsFixed(1)} MB, '
                'made in ${(_watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s.',
              ),
              if (!result.path.endsWith('.mp4'))
                Text(
                  'MP4 is not available on this system, so this is an AVI (plays in VLC).',
                  style: t.bodySmall,
                ),
              if (widget.test)
                Text('Video export works on this device.', style: t.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!widget.test)
                    FilledButton.icon(
                      onPressed: _saveToLocker,
                      icon: const Icon(Icons.folder_shared_outlined),
                      label: const Text('Save to Asset Locker'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Export / share'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ] else if (_job != null) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${(_progress * 100).round()}%  (${(_progress * _job!.frameCount).round()} / ${_job!.frameCount} frames)',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _job?.cancel(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ] else ...[
              Text('Size (4:3)', style: t.labelLarge),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in exportSizes)
                    ChoiceChip(
                      label: Text('${s.$1}×${s.$2}'),
                      selected: s == _size,
                      onSelected: (_) => setState(() => _size = s),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Frames per second', style: t.labelLarge),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in exportRates)
                    ChoiceChip(
                      label: Text('$r'),
                      selected: r == _fps,
                      onSelected: (_) => setState(() => _fps = r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _run,
                icon: const Icon(Icons.movie_creation_outlined),
                label: const Text('Export'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
