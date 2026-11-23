import 'dart:convert';

import 'package:http/http.dart' as http;

const repoSlug = 'westonuchiha-code/Flutter-apps.-';
const repoUrl = 'https://github.com/$repoSlug';

/// Kinds of CI jobs per app, in display order.
enum JobKind {
  test('Analyze & test', 'Tests'),
  android('Android', 'Android'),
  windows('Windows', 'Windows'),
  linux('Linux', 'Linux'),
  publish('Publish latest builds', 'Release');

  const JobKind(this.prefix, this.label);
  final String prefix;
  final String label;
}

enum JobState { running, passed, failed, skipped }

JobState jobState(String? status, String? conclusion) {
  if (status != 'completed') return JobState.running;
  return switch (conclusion) {
    'success' => JobState.passed,
    'failure' || 'timed_out' || 'startup_failure' => JobState.failed,
    _ => JobState.skipped,
  };
}

enum FileKind { android, windows, linux }

class ReleaseFile {
  const ReleaseFile(this.name, this.url, this.size, this.kind);

  final String name;
  final String url;
  final int size;
  final FileKind kind;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.published,
    required this.builtFrom,
    required this.pageUrl,
    required this.files,
  });

  final String tag;
  final DateTime? published;

  /// "branch @ sha" from the release notes, or ''.
  final String builtFrom;
  final String pageUrl;
  final List<ReleaseFile> files;

  ReleaseFile? file(FileKind kind) {
    for (final f in files) {
      if (f.kind == kind) return f;
    }
    return null;
  }
}

class AppStatus {
  AppStatus(this.app);

  final String app;
  final Map<JobKind, JobState> jobs = {};
  final Map<JobKind, String> jobUrls = {};
  ReleaseInfo? release;

  JobState? get overall {
    if (jobs.isEmpty) return null;
    final states = jobs.values;
    if (states.contains(JobState.failed)) return JobState.failed;
    if (states.contains(JobState.running)) return JobState.running;
    return JobState.passed;
  }
}

class DashboardData {
  const DashboardData({
    required this.apps,
    required this.runState,
    required this.runUrl,
    required this.runTitle,
    required this.branch,
    required this.sha,
    required this.runTime,
  });

  final List<AppStatus> apps;
  final JobState? runState;
  final String runUrl;
  final String runTitle;
  final String branch;
  final String sha;
  final DateTime? runTime;
}

final _jobName = RegExp(r'^(.+?) \((\w+)');

FileKind? _fileKind(String name) {
  if (name.endsWith('.apk')) return FileKind.android;
  if (name.endsWith('-windows-x64.zip')) return FileKind.windows;
  if (name.endsWith('-linux-x64.tar.gz')) return FileKind.linux;
  return null;
}

/// Combines GitHub's latest run, its jobs and the releases (pure, testable).
DashboardData parseDashboard({
  required Map<String, Object?>? run,
  required List<Object?> jobs,
  required List<Object?> releases,
}) {
  final apps = <String, AppStatus>{};
  AppStatus app(String name) => apps.putIfAbsent(name, () => AppStatus(name));

  for (final j in jobs) {
    if (j is! Map) continue;
    final m = _jobName.firstMatch((j['name'] as String?) ?? '');
    if (m == null) continue;
    final kind = JobKind.values.where((k) => k.prefix == m.group(1));
    if (kind.isEmpty) continue;
    final a = app(m.group(2)!);
    a.jobs[kind.first] = jobState(
      j['status'] as String?,
      j['conclusion'] as String?,
    );
    final url = j['html_url'];
    if (url is String) a.jobUrls[kind.first] = url;
  }

  for (final r in releases) {
    if (r is! Map) continue;
    final tag = (r['tag_name'] as String?) ?? '';
    if (!tag.endsWith('-latest')) continue;
    final notes = (r['body'] as String?) ?? '';
    final built = RegExp(
      r'Built from (.+?)\.?$',
      multiLine: true,
    ).firstMatch(notes)?.group(1);
    app(tag.substring(0, tag.length - 7)).release = ReleaseInfo(
      tag: tag,
      published: DateTime.tryParse((r['published_at'] as String?) ?? ''),
      builtFrom: built ?? '',
      pageUrl: (r['html_url'] as String?) ?? '$repoUrl/releases/tag/$tag',
      files: [
        for (final f in (r['assets'] as List?) ?? const [])
          if (f is Map && _fileKind((f['name'] as String?) ?? '') != null)
            ReleaseFile(
              f['name']! as String,
              (f['browser_download_url'] as String?) ?? '',
              (f['size'] as num?)?.toInt() ?? 0,
              _fileKind(f['name']! as String)!,
            ),
      ],
    );
  }

  final list = apps.values.toList()..sort((a, b) => a.app.compareTo(b.app));
  return DashboardData(
    apps: list,
    runState: run == null
        ? null
        : jobState(run['status'] as String?, run['conclusion'] as String?),
    runUrl: (run?['html_url'] as String?) ?? '$repoUrl/actions',
    runTitle: (run?['display_title'] as String?) ?? '',
    branch: (run?['head_branch'] as String?) ?? '',
    sha: ((run?['head_sha'] as String?) ?? '')
        .padRight(7)
        .substring(0, 7)
        .trim(),
    runTime: DateTime.tryParse((run?['created_at'] as String?) ?? ''),
  );
}

class GitHubException implements Exception {
  GitHubException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads public CI and release data (no login needed; GitHub allows about
/// 60 requests an hour without one, and each refresh uses 3).
class GitHubClient {
  GitHubClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  Future<Object?> _get(String path) async {
    final res = await _http.get(
      Uri.parse('https://api.github.com/repos/$repoSlug/$path'),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'dev-dashboard',
      },
    );
    if (res.statusCode == 403 || res.statusCode == 429) {
      throw GitHubException(
        'GitHub limits how often this can refresh without a login. '
        'Try again in a few minutes.',
      );
    }
    if (res.statusCode != 200) {
      throw GitHubException('GitHub answered ${res.statusCode}.');
    }
    return jsonDecode(res.body);
  }

  Future<DashboardData> fetch() async {
    final runs = await _get('actions/runs?per_page=1');
    final runList = runs is Map ? runs['workflow_runs'] : null;
    final run = runList is List && runList.isNotEmpty
        ? (runList.first as Map).cast<String, Object?>()
        : null;
    final results = await Future.wait([
      run == null
          ? Future<Object?>.value(const {'jobs': []})
          : _get('actions/runs/${run['id']}/jobs?per_page=100'),
      _get('releases?per_page=100'),
    ]);
    final jobs = results[0];
    final releases = results[1];
    return parseDashboard(
      run: run,
      jobs: jobs is Map && jobs['jobs'] is List
          ? jobs['jobs'] as List
          : const [],
      releases: releases is List ? releases : const [],
    );
  }
}
