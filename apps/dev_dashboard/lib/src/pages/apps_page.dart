import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../github.dart';
import '../installer.dart';
import '../time.dart';

/// CI status of every app plus one-tap install of the latest build.
class AppsPage extends StatefulWidget {
  const AppsPage({
    super.key,
    required this.github,
    required this.installer,
    this.onApps,
  });

  final GitHubClient github;
  final Installer installer;

  /// Reports the app ids found (for the to-do tags).
  final void Function(List<String> apps)? onApps;

  @override
  State<AppsPage> createState() => AppsPageState();
}

class AppsPageState extends State<AppsPage> {
  DashboardData? _data;
  Object? _error;
  bool _loading = false;
  final Map<String, double?> _progress = {};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final data = await widget.github.fetch();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
      widget.onApps?.call([for (final a in data.apps) a.app]);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _install(AppStatus app, ReleaseFile file) async {
    Shell.of(context).tick();
    setState(() => _progress[app.app] = 0);
    try {
      final f = await widget.installer.download(
        file,
        onProgress: (v) => setState(() => _progress[app.app] = v),
      );
      if (Platform.isAndroid) {
        final started = await widget.installer.installApk(f);
        if (!started) {
          _snack(
            'Allow "Install unknown apps" for Dev Dashboard, '
            'then come back and tap Install again.',
          );
        }
      } else {
        _snack('Saved to ${f.path}');
        await widget.installer.reveal(f);
      }
    } catch (e) {
      _snack('Download failed: $e');
    } finally {
      if (mounted) setState(() => _progress.remove(app.app));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (_error != null) {
        return _Message(
          text: '$_error',
          action: FilledButton(
            onPressed: refresh,
            child: const Text('Try again'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _RunCard(data: data),
          const SizedBox(height: 8),
          for (final app in data.apps)
            _AppCard(
              app: app,
              progress: _progress[app.app],
              busy: _progress.containsKey(app.app),
              onInstall: (f) => _install(app, f),
            ),
        ],
      ),
    );
  }
}

Future<void> openUrl(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.action});

  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          action,
        ],
      ),
    ),
  );
}

class StateIcon extends StatelessWidget {
  const StateIcon(this.state, {super.key, this.size = 18});

  final JobState? state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (state) {
      JobState.passed => Icon(
        Icons.check_circle,
        size: size,
        color: Colors.green.shade600,
      ),
      JobState.failed => Icon(Icons.cancel, size: size, color: scheme.error),
      JobState.running => SizedBox.square(
        dimension: size,
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      JobState.skipped || null => Icon(
        Icons.remove_circle_outline,
        size: size,
        color: scheme.outline,
      ),
    };
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final label = switch (data.runState) {
      JobState.passed => 'Latest build passed',
      JobState.failed => 'Latest build failed',
      JobState.running => 'Building now',
      _ => 'No builds yet',
    };
    return Card(
      child: ListTile(
        leading: StateIcon(data.runState, size: 28),
        title: Text(label),
        subtitle: Text(
          [
            if (data.runTitle.isNotEmpty) data.runTitle,
            [
              data.branch,
              data.sha,
              timeAgo(data.runTime),
            ].where((s) => s.isNotEmpty).join(' · '),
          ].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Open on GitHub',
          icon: const Icon(Icons.open_in_new),
          onPressed: () => openUrl(data.runUrl),
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.progress,
    required this.busy,
    required this.onInstall,
  });

  final AppStatus app;
  final double? progress;
  final bool busy;
  final void Function(ReleaseFile file) onInstall;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final release = app.release;
    final file = release?.file(currentFileKind);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StateIcon(app.overall, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text(app.app, style: text.titleMedium)),
                if (file != null)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.download),
                    label: Text(Platform.isAndroid ? 'Install' : 'Download'),
                    onPressed: busy ? null : () => onInstall(file),
                  ),
              ],
            ),
            if (app.jobs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in JobKind.values)
                    if (app.jobs[k] != null)
                      app.jobUrls[k] == null
                          ? Chip(
                              avatar: StateIcon(app.jobs[k]),
                              label: Text(k.label),
                              visualDensity: VisualDensity.compact,
                            )
                          : ActionChip(
                              avatar: StateIcon(app.jobs[k]),
                              label: Text(k.label),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => openUrl(app.jobUrls[k]!),
                            ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              release == null
                  ? 'No release yet'
                  : [
                      'Release ${timeAgo(release.published)}',
                      if (release.builtFrom.isNotEmpty) release.builtFrom,
                      if (file != null) sizeLabel(file.size),
                      if (file == null) 'no build for this platform',
                    ].join(' · '),
              style: text.bodySmall,
            ),
            if (busy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
            ],
          ],
        ),
      ),
    );
  }
}
