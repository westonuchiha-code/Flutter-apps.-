import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../time.dart';

/// One app's published error report.
class AppErrors {
  AppErrors(this.app, Map<String, Object?> json)
    : name = (json['name'] as String?) ?? app,
      version = (json['version'] as String?) ?? '',
      platform = (json['platform'] as String?) ?? '',
      entries = [
        for (final e in (json['entries'] as List?) ?? const [])
          if (e is Map) CrashEntry.fromJson(e.cast<String, Object?>()),
      ]..sort((a, b) => b.time.compareTo(a.time));

  final String app;
  final String name;
  final String version;
  final String platform;
  final List<CrashEntry> entries;

  String report() {
    final b = StringBuffer('$name $version ($platform): error report\n\n');
    for (final e in entries) {
      b
        ..writeln(
          '[${e.time.toIso8601String()}]${e.fatal ? ' FATAL' : ''}'
          '${e.context == null ? '' : ' (${e.context})'}',
        )
        ..writeln(e.error)
        ..writeln(e.stack)
        ..writeln();
    }
    return b.toString();
  }
}

/// Every app's error log, read from the Asset Locker.
class ErrorsPage extends StatefulWidget {
  const ErrorsPage({super.key});

  @override
  State<ErrorsPage> createState() => ErrorsPageState();
}

class ErrorsPageState extends State<ErrorsPage> {
  Future<List<AppErrors>>? _future;
  AssetLocker? _locker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locker = Shell.of(context).locker;
    if (locker != _locker) {
      _locker?.removeListener(refresh);
      _locker = locker..addListener(refresh);
      refresh();
    }
  }

  @override
  void dispose() {
    _locker?.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    final locker = _locker!;
    setState(() {
      _future = locker.ready ? _load(locker) : null;
    });
  }

  static Future<List<AppErrors>> _load(AssetLocker locker) async {
    final reports = await locker.readErrorReports();
    return [for (final e in reports.entries) AppErrors(e.key, e.value)]
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final shell = Shell.of(context);
    final locker = shell.locker;
    if (!locker.ready) return LockerConnectCard(locker: locker);
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        final apps = snap.data ?? const <AppErrors>[];
        if (apps.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No errors reported.\n\nApps built on the App Shell Kit '
                'report here once their Asset Locker is connected.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final a in apps)
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(a.name),
                    subtitle: Text(
                      '${a.entries.length} error${a.entries.length == 1 ? '' : 's'}'
                      ' · last ${timeAgo(a.entries.firstOrNull?.time)}'
                      '${a.version.isEmpty ? '' : ' · v${a.version}'}'
                      '${a.platform.isEmpty ? '' : ' · ${a.platform}'}',
                    ),
                    children: [
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Share'),
                            onPressed: () => shell.exporter.exportText(
                              '${a.app}-errors.txt',
                              a.report(),
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Clear'),
                            onPressed: () => locker.clearErrorReport(a.app),
                          ),
                        ],
                      ),
                      for (final e in a.entries)
                        ExpansionTile(
                          title: Text(
                            e.error,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${e.time.toLocal()}${e.fatal ? ' · fatal' : ''}',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                '${e.context ?? ''}\n${e.stack}'.trim(),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
