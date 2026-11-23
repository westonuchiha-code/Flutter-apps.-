import 'dart:io';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:material_ui/material_ui.dart';

import 'editor_page.dart';
import 'model.dart';
import 'record_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.takes, this.recorder});

  final Takes takes;

  /// For tests.
  final MicRecorder? recorder;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<File> _leftovers = const [];
  List<AssetInfo>? _recordings;
  String _query = '';
  AssetLocker? _locker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locker = Shell.of(context).locker;
    if (locker != _locker) {
      _locker?.removeListener(_refresh);
      _locker = locker..addListener(_refresh);
      _refresh();
    }
  }

  @override
  void dispose() {
    _locker?.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final leftovers = await widget.takes.leftovers();
    final locker = _locker!;
    List<AssetInfo>? recs;
    if (locker.ready) {
      try {
        recs = await locker.list(type: AssetType.recording);
      } catch (_) {
        recs = const [];
      }
    }
    if (!mounted) return;
    setState(() {
      _leftovers = leftovers;
      _recordings = recs;
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final shell = Shell.of(context);
    final locker = shell.locker;
    final q = _query.toLowerCase();
    final recs = [
      for (final r in _recordings ?? const <AssetInfo>[])
        if (q.isEmpty ||
            r.name.toLowerCase().contains(q) ||
            r.tags.any((t) => t.contains(q)))
          r,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(shell.config.name),
        actions: shellActions(context),
      ),
      floatingActionButton: FloatingActionButton.large(
        tooltip: 'Record',
        backgroundColor: Theme.of(context).colorScheme.error,
        foregroundColor: Theme.of(context).colorScheme.onError,
        onPressed: () =>
            _open(RecordPage(takes: widget.takes, recorder: widget.recorder)),
        child: const Icon(Icons.mic, size: 40),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            if (_leftovers.isNotEmpty) ...[
              const _Header('Unsaved'),
              for (final f in _leftovers)
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Unsaved recording'),
                  subtitle: FutureBuilder(
                    future: f.lastModified(),
                    builder: (context, s) =>
                        Text(s.data == null ? '' : defaultName(s.data!)),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _open(EditorPage.newTake(file: f, takes: widget.takes)),
                ),
            ],
            if (!locker.ready)
              SizedBox(height: 360, child: LockerConnectCard(locker: locker))
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search names and tags',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const _Header('Recordings'),
              if (_recordings == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (recs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    (_recordings ?? const []).isEmpty
                        ? 'No recordings yet. Tap the microphone to record.\n'
                              'Recordings are saved in the Asset Locker, '
                              'so other apps can use them.'
                        : 'No matches.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final r in recs)
                  _RecordingTile(
                    info: r,
                    locker: locker,
                    onTap: () =>
                        _open(EditorPage.asset(asset: r, takes: widget.takes)),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({
    required this.info,
    required this.locker,
    required this.onTap,
  });

  final AssetInfo info;
  final AssetLocker locker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final seconds = (info.extra['seconds'] as num?)?.toDouble();
    final markers = (info.extra['markers'] as List?)?.length ?? 0;
    final c = info.created.toLocal();
    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 64,
          height: 40,
          child: info.hasThumbnail
              ? FutureBuilder<Uint8List?>(
                  future: locker.thumbnail(info),
                  builder: (context, s) => s.data == null
                      ? const Icon(Icons.graphic_eq)
                      : Image.memory(s.data!, fit: BoxFit.cover),
                )
              : const Icon(Icons.graphic_eq),
        ),
      ),
      title: Text(info.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (seconds != null) formatSeconds(seconds, tenths: false),
          '${c.day}/${c.month}/${c.year}',
          if (markers > 0) '$markers markers',
          if (info.app != 'field_recorder') 'from ${info.app}',
          if (info.tags.isNotEmpty) info.tags.join(', '),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
