import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:save_screens/save_screens.dart';

/// Folders to read besides the emulators' usual ones.
const extraFoldersSetting = TextSetting(
  key: 'extraFolders',
  title: 'Extra save folders',
  subtitle:
      'One per line (or separated by ;). Memory cards in them show up too.',
  section: 'Save folders',
);

/// The order the grid starts in.
final sortSetting = ChoiceSetting(
  key: 'sort',
  title: 'Sort saves',
  defaultValue: '0',
  choices: {for (final (i, s) in MemoryCardState.sorts.indexed) '$i': s},
  section: 'Save folders',
);

final appConfig = AppShellConfig(
  id: 'save_manager',
  name: 'Save Manager',
  version: '0.1.0',
  description:
      'Memory cards of PS1, PS2, Dreamcast, GameCube, N64, Saturn and Neo Geo '
      'emulators, and PS3 saves: copy, move, back up, restore, undelete, '
      'export and import. Every change is backed up first.',
  accent: Look.cyan,
  defaultThemeMode: ThemeMode.dark,
  settings: [extraFoldersSetting, sortSetting],
);

void main() => runShellApp(appConfig, (_) => const HomePage());

/// Builds the controller's config (tests pass their own).
/// The save manager, with this app's settings around it.
class HomePage extends StatelessWidget {
  const HomePage({super.key, this.makeConfig, this.runner, this.showHints});

  /// Tests: their own folders.
  final ConfigMaker? makeConfig;

  final BackgroundRunner? runner;

  final bool? showHints;

  List<Widget> _actions(BuildContext context) => [
    for (final (tip, icon, page) in [
      ('Settings', Icons.settings_outlined, const SettingsPage() as Widget),
      ('About', Icons.info_outline, const AboutShellPage() as Widget),
    ])
      IconButton(
        tooltip: tip,
        color: Look.soft,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        icon: Icon(icon),
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => page)),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final services = Shell.of(context);
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) => SaveManagerHome(
        extraFolders: services.settings.get(extraFoldersSetting),
        sort: int.tryParse(services.settings.get(sortSetting)) ?? 0,
        actions: _actions(context),
        onTick: services.tick,
        makeConfig: makeConfig,
        runner: runner,
        showHints: showHints,
      ),
    );
  }
}
