import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'src/github.dart';
import 'src/installer.dart';
import 'src/pages/apps_page.dart';
import 'src/pages/assets_page.dart';
import 'src/pages/errors_page.dart';
import 'src/pages/todo_page.dart';

const appConfig = AppShellConfig(
  id: 'dev_dashboard',
  name: 'Dev Dashboard',
  version: '0.1.0',
  description:
      'Build status and installs for every app in the repo, their error '
      'reports, the shared Asset Locker and a to-do list.',
  accent: Color(0xFF2E9E6B),
);

void main() => runShellApp(appConfig, (_) => HomePage());

/// Apps known before GitHub answers (to-do tags).
const _defaultApps = [
  'dev_dashboard',
  'optical_theremin',
  'sa_companion',
  'scan_ranch',
  'starter_app',
  'touch_synth',
];

class HomePage extends StatefulWidget {
  HomePage({super.key, GitHubClient? github, Installer? installer})
    : github = github ?? GitHubClient(),
      installer = installer ?? Installer();

  final GitHubClient github;
  final Installer installer;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  final _apps = ValueNotifier<List<String>>(_defaultApps);
  final _appsKey = GlobalKey<AppsPageState>();
  final _errorsKey = GlobalKey<ErrorsPageState>();

  static const _tabs = [
    (Icons.apps_outlined, Icons.apps, 'Apps'),
    (Icons.bug_report_outlined, Icons.bug_report, 'Errors'),
    (Icons.folder_outlined, Icons.folder, 'Assets'),
    (Icons.checklist_outlined, Icons.checklist, 'To-do'),
  ];

  @override
  void dispose() {
    _apps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final pages = [
      AppsPage(
        key: _appsKey,
        github: widget.github,
        installer: widget.installer,
        onApps: (a) => _apps.value = {..._defaultApps, ...a}.toList()..sort(),
      ),
      ErrorsPage(key: _errorsKey),
      const AssetsPage(),
      TodoPage(apps: _apps),
    ];
    final body = IndexedStack(index: _tab, children: pages);
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabs[_tab].$3),
        actions: [
          if (_tab < 2)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => _tab == 0
                  ? _appsKey.currentState?.refresh()
                  : _errorsKey.currentState?.refresh(),
            ),
          ...shellActions(context),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    for (final t in _tabs)
                      NavigationRailDestination(
                        icon: Icon(t.$1),
                        selectedIcon: Icon(t.$2),
                        label: Text(t.$3),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (final t in _tabs)
                  NavigationDestination(
                    icon: Icon(t.$1),
                    selectedIcon: Icon(t.$2),
                    label: t.$3,
                  ),
              ],
            ),
    );
  }
}

@visibleForTesting
const defaultApps = _defaultApps;
