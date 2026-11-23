import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:dev_dashboard/main.dart';
import 'package:dev_dashboard/src/github.dart';
import 'package:dev_dashboard/src/pages/assets_page.dart';
import 'package:dev_dashboard/src/time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _jobs = [
  {
    'name': 'Analyze & test (scan_ranch)',
    'status': 'completed',
    'conclusion': 'success',
  },
  {
    'name': 'Android (scan_ranch)',
    'status': 'completed',
    'conclusion': 'failure',
    'html_url': 'u',
  },
  {
    'name': 'Windows (starter_app)',
    'status': 'in_progress',
    'conclusion': null,
  },
  {
    'name': 'Linux (starter_app, best-effort)',
    'status': 'completed',
    'conclusion': 'success',
  },
  {'name': 'Discover apps', 'status': 'completed', 'conclusion': 'success'},
];
final _releases = [
  {
    'tag_name': 'starter_app-latest',
    'published_at': '2026-11-23T10:00:00Z',
    'html_url': 'r',
    'body': 'Built from main @ abc1234.\nAndroid: download',
    'assets': [
      {
        'name': 'starter_app-android.apk',
        'browser_download_url': 'a',
        'size': 10,
      },
      {
        'name': 'starter_app-windows-x64.zip',
        'browser_download_url': 'w',
        'size': 20,
      },
      {
        'name': 'starter_app-linux-x64.tar.gz',
        'browser_download_url': 'l',
        'size': 30,
      },
    ],
  },
  {'tag_name': 'v1.0', 'assets': []},
];

DashboardData _data() => parseDashboard(
  run: {
    'status': 'in_progress',
    'html_url': 'run',
    'head_branch': 'main',
    'head_sha': 'abcdef123456',
    'display_title': 'Add things',
  },
  jobs: _jobs,
  releases: _releases,
);

class FakeGitHub extends GitHubClient {
  @override
  Future<DashboardData> fetch() async => _data();
}

void main() {
  test('parses jobs and releases per app', () {
    final d = _data();
    expect(d.apps.map((a) => a.app), ['scan_ranch', 'starter_app']);
    final scan = d.apps.first;
    expect(scan.jobs[JobKind.test], JobState.passed);
    expect(scan.jobs[JobKind.android], JobState.failed);
    expect(scan.overall, JobState.failed);
    expect(scan.jobUrls[JobKind.android], 'u');
    final starter = d.apps.last;
    expect(starter.jobs[JobKind.windows], JobState.running);
    expect(starter.jobs[JobKind.linux], JobState.passed);
    expect(starter.overall, JobState.running);
    expect(starter.release!.builtFrom, 'main @ abc1234');
    expect(starter.release!.file(FileKind.android)!.url, 'a');
    expect(starter.release!.file(FileKind.linux)!.size, 30);
    expect(d.sha, 'abcdef1');
    expect(d.runState, JobState.running);
  });

  test('time and size labels, preview kinds', () {
    final now = DateTime(2026, 1, 2, 12);
    expect(
      timeAgo(now.subtract(const Duration(minutes: 5)), now: now),
      '5 min ago',
    );
    expect(
      timeAgo(now.subtract(const Duration(hours: 3)), now: now),
      '3 h ago',
    );
    expect(
      timeAgo(now.subtract(const Duration(days: 4)), now: now),
      '4 days ago',
    );
    expect(sizeLabel(3 * 1024 * 1024), '3.0 MB');
    expect(previewKind('png'), PreviewKind.image);
    expect(previewKind('wav'), PreviewKind.audio);
    expect(previewKind('json'), PreviewKind.text);
    expect(previewKind('bin'), PreviewKind.none);
  });

  testWidgets('shows apps, errors and the to-do list', (tester) async {
    final dir = Directory.systemTemp.createTempSync('dash_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(() async {
      final s = await ShellServices.create(appConfig, root: dir);
      final other = AssetLocker.atDirectory(
        'scan_ranch',
        Directory('${dir.path}/${AssetLocker.folderName}'),
      );
      await other.writeErrorReport({
        'name': 'Scan Ranch',
        'version': '1.0',
        'entries': [
          {
            'time': DateTime.now().toIso8601String(),
            'error': 'Bad egg',
            'stack': '',
            'fatal': false,
          },
        ],
      });
      return s;
    }))!;
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(github: FakeGitHub()),
      ),
    );
    await tester.pump();
    expect(find.text('scan_ranch'), findsOneWidget);
    expect(find.text('starter_app'), findsOneWidget);
    expect(find.text('Building now'), findsOneWidget);

    Future<void> settleIo(Finder f) async {
      for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await tester.tap(find.text('Errors'));
    await settleIo(find.text('Scan Ranch'));
    expect(find.text('Scan Ranch'), findsOneWidget);

    await tester.tap(find.text('To-do'));
    await settleIo(find.text('Nothing to do.'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a to-do'),
      'Fix eggs',
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    expect(find.text('Fix eggs'), findsOneWidget);
    var saved = <TodoItem>[];
    for (var i = 0; i < 50 && saved.isEmpty; i++) {
      await tester.pump();
      saved = (await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return services.locker.readTodos();
      }))!;
    }
    expect(saved.single.text, 'Fix eggs');
    await tester.pump(const Duration(seconds: 1));
  });
}
