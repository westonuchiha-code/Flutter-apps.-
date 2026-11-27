import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:cross_save/cross_save.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pokeville/pokeville.dart';

const folderSetting = TextSetting(
  key: 'folder',
  title: 'Pokéville folder',
  subtitle:
      'Empty: the usual one (Android: XMB Frontend/Pokeville, synced with '
      'the PC; Windows: the PC menu\'s own folder).',
  section: 'Pokéville',
);

const saveFoldersSetting = TextSetting(
  key: 'saveFolders',
  title: 'More game save folders',
  subtitle:
      'Folders to look in for Pokémon game saves (.srm / .sav), separated '
      'by ; (Android: XMB Frontend/Saves/RetroArch is always looked in; '
      "Windows: RetroArch's saves folder when it's found).",
  section: 'Pokéville',
);

const swapSetting = BoolSetting(
  key: 'swapAB',
  title: 'Swap A and B on a gamepad',
  defaultValue: false,
  section: 'Pokéville',
);

const appConfig = AppShellConfig(
  id: 'pokeville_app',
  name: 'Pokéville',
  version: '0.1.0',
  description:
      'Your Pokémon from every game, kept in Pokéville and synced with the '
      'PC XMB Frontend through Cross-Save.',
  accent: Color(0xFFE8463C),
  settings: [folderSetting, saveFoldersSetting, swapSetting],
);

const _channel = MethodChannel('pokeville/android');

void main() {
  registerPokevilleLicenses();
  runShellApp(appConfig, (_) => const HomePage());
}

/// Where Pokéville lives: the setting, else the XMB's synced folder
/// (Android), the PC menu's own folder (Windows) or Documents/Pokeville.
Future<({String folder, XmbFolders? xmb})> findPokeville(String chosen) async {
  if (chosen.trim().isNotEmpty) return (folder: chosen.trim(), xmb: null);
  if (Platform.isAndroid) {
    final root = await _channel.invokeMethod<String>('storageRoot') ?? '';
    final xmb = XmbFolders(p.join(root, 'XMB Frontend'));
    return (folder: xmb.pokeville, xmb: xmb);
  }
  if (Platform.isWindows) {
    final pub = Platform.environment['PUBLIC'] ?? r'C:\Users\Public';
    return (folder: p.join(pub, 'Documents', 'XMB Pokemon Box'), xmb: null);
  }
  final docs = await getApplicationDocumentsDirectory();
  return (folder: p.join(docs.path, 'Pokeville'), xmb: null);
}

/// The XMB Frontend's Cross-Save sign-in (Android, same signing key):
/// '' when it isn't installed or signed in.
Future<String> sharedToken() async {
  if (!Platform.isAndroid) return '';
  try {
    return await _channel.invokeMethod<String>('sharedToken') ?? '';
  } catch (_) {
    return '';
  }
}

/// Opens [url] in the browser (Android); false when it couldn't.
Future<bool> openUrl(String url) async {
  if (!Platform.isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('openUrl', {
          'urls': [url],
        }) ??
        false;
  } catch (_) {
    return false;
  }
}

/// Where to look for Pokémon game saves: the XMB's RetroArch saves
/// (Android), RetroArch's saves folder (Windows), plus [extra] (`;`
/// separated).
List<String> gameSaveRoots(XmbFolders? xmb, String extra) => [
  if (xmb != null) xmb.raSaves,
  if (Platform.isWindows) ...retroArchSaveDirs(),
  for (final d in extra.split(';'))
    if (d.trim().isNotEmpty) d.trim(),
];

/// The Pokémon game saves under the XMB's RetroArch saves, relative to it
/// ('/' separators): the only saves this app syncs.
Future<Set<String>> pokemonSaveNames(String raSaves) async => {
  for (final g in await runInBackground(findGameSaves, [raSaves]))
    p.relative(g.path, from: raSaves).replaceAll(r'\', '/'),
};

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String? _folder;
  XmbFolders? _xmb;
  bool _access = true;
  CrossSaveController? _sync;

  /// The token came from the XMB Frontend (one sign-in for both apps).
  bool _viaXmb = false;
  int _generation = 0; // a new one re-reads Pokéville (after a sync)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // after the first frame: _start reads the Shell above this widget
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_access) unawaited(_start());
    // Signed in (or again) in the XMB meanwhile: use it.
    if (state == AppLifecycleState.resumed && _sync != null) {
      unawaited(_useXmbSignIn(_sync!));
    }
    // Changes made here go to the PC when the app is left.
    if (state == AppLifecycleState.paused) unawaited(_sync?.sync());
  }

  Future<void> _start() async {
    final shell = Shell.of(context);
    if (Platform.isAndroid) {
      final ok = await _channel.invokeMethod<bool>('hasAllFiles') ?? false;
      if (!mounted) return;
      if (!ok) {
        setState(() => _access = false);
        return;
      }
    }
    final at = await findPokeville(shell.settings.get(folderSetting));
    CrossSaveController? sync;
    if (at.xmb != null) {
      final ra = at.xmb!.raSaves;
      // Pokéville, plus the Pokémon game saves it changes (the XMB syncs
      // every save; this app only the ones it found).
      sync =
          CrossSaveController(
              shell.storage,
              only: const ['pokeville', 'saves/retroarch'],
              files: {'saves/retroarch': () => pokemonSaveNames(ra)},
            )
            ..folders = at.xmb
            ..model = await _channel.invokeMethod<String>('deviceModel') ?? '';
      await sync.load();
      await _useXmbSignIn(sync);
    }
    if (!mounted) return;
    setState(() {
      _access = true;
      _folder = at.folder;
      _xmb = at.xmb;
      _sync = sync;
    });
    if (sync != null && sync.token.isNotEmpty) await _syncNow();
  }

  /// Takes the XMB Frontend's token when it has one this app lacks.
  Future<void> _useXmbSignIn(CrossSaveController sync) async {
    final t = await sharedToken();
    if (t.isEmpty) return;
    final changed = t != sync.token;
    await sync.adoptToken(t);
    if (!mounted) return;
    setState(() => _viaXmb = true);
    if (changed && _sync != null) await _syncNow();
  }

  Future<void> _syncNow() async {
    final rep = await _sync?.sync();
    if (!mounted || rep == null) return;
    setState(() => _generation++);
  }

  Future<void> _openSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SyncPage(controller: _sync, folder: _folder ?? '', viaXmb: _viaXmb),
      ),
    );
    if (mounted) setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    final services = Shell.of(context);
    if (!_access) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Pokéville lives in the XMB Frontend folder, beside your '
                  'game saves. Allow access to all files to open it.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  autofocus: true,
                  onPressed: () =>
                      unawaited(_channel.invokeMethod('requestAllFiles')),
                  child: const Text('Allow access'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final folder = _folder;
    if (folder == null) return const Scaffold(body: SizedBox.shrink());
    final sync = _sync;
    return CallbackShortcuts(
      // Start / F5: the sync page.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.gameButtonStart): _openSync,
        const SingleActivator(LogicalKeyboardKey.f5): _openSync,
      },
      child: Stack(
        children: [
          ListenableBuilder(
            listenable: services.settings,
            builder: (context, _) => PokevilleHome(
              folder,
              p.join(services.storage.directory.path, 'pokemon sprites'),
              key: ValueKey('$folder#$_generation'),
              swapAB: services.settings.get(swapSetting),
              games: PokeGames(
                gameSaveRoots(_xmb, services.settings.get(saveFoldersSetting)),
              ),
              onLeave: () => unawaited(SystemNavigator.pop()),
            ),
          ),
          Positioned(
            left: 4,
            top: 4,
            child: SafeArea(
              child: ListenableBuilder(
                listenable: sync ?? services.settings,
                builder: (context, _) => IconButton.filledTonal(
                  tooltip: 'Sync and settings (Start)',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  onPressed: _openSync,
                  icon: sync != null && sync.busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          sync != null && sync.conflicts.isNotEmpty
                              ? Icons.sync_problem
                              : Icons.sync,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cross-Save for Pokéville: the token, Sync now, the last result and
/// conflicts (pick which side to keep), plus the app's settings.
class SyncPage extends StatefulWidget {
  const SyncPage({
    super.key,
    required this.controller,
    required this.folder,
    this.viaXmb = false,
  });

  /// Signed in through the XMB Frontend (its token).
  final bool viaXmb;

  /// Null: this platform doesn't sync here (Windows: the PC menu does).
  final CrossSaveController? controller;
  final String folder;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  Future<void> _signIn(CrossSaveController c) async {
    final ok = await showGitHubSignIn(
      context,
      c,
      openUrl: openUrl,
      swapAB: Shell.of(context).settings.get(swapSetting),
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Signed in. Getting your saves…')),
    );
    final rep = await c.sync();
    if (rep == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(syncReportLines(rep).take(3).join('\n')),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pokéville'),
        actions: shellActions(context),
      ),
      body: c == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Pokéville folder: ${widget.folder}'),
                const SizedBox(height: 8),
                const Text(
                  'On this computer the PC XMB Frontend syncs Pokéville with '
                  'Cross-Save, so this app just opens its folder.',
                ),
              ],
            )
          : ListenableBuilder(
              listenable: c,
              builder: (context, _) => ListView(
                children: [
                  if (c.token.isEmpty)
                    ListTile(
                      autofocus: true,
                      leading: const Icon(Icons.login),
                      title: const Text('Sign in with GitHub'),
                      subtitle: const Text(
                        'Or sign in once in the XMB Frontend: this app then '
                        'uses it too',
                      ),
                      onTap: () => unawaited(_signIn(c)),
                    )
                  else
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('GitHub'),
                      subtitle: Text(
                        widget.viaXmb
                            ? 'Signed in through the XMB Frontend'
                            : 'Signed in',
                      ),
                      onTap: widget.viaXmb ? null : () => unawaited(_signIn(c)),
                      trailing: widget.viaXmb
                          ? null
                          : TextButton(
                              onPressed: () => unawaited(c.forgetToken()),
                              child: const Text('Sign out'),
                            ),
                    ),
                  ListTile(
                    leading: c.busy
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    title: const Text('Sync now'),
                    subtitle: Text(
                      c.last == null
                          ? 'Not synced yet'
                          : '${c.lastError ?? c.lastSummary} '
                                '(${TimeOfDay.fromDateTime(c.last!).format(context)})',
                    ),
                    enabled: c.token.isNotEmpty && !c.busy,
                    onTap: () => unawaited(c.sync()),
                  ),
                  for (final k in c.conflicts)
                    ListTile(
                      leading: const Icon(Icons.sync_problem),
                      title: Text(p.basename(k.key)),
                      subtitle: const Text(
                        'Changed here and on another device. Keep which?',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () =>
                                unawaited(c.resolve(k, keepThisDevice: true)),
                            child: const Text('This one'),
                          ),
                          TextButton(
                            onPressed: () =>
                                unawaited(c.resolve(k, keepThisDevice: false)),
                            child: const Text('The other'),
                          ),
                        ],
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Folder'),
                    subtitle: Text(widget.folder),
                  ),
                ],
              ),
            ),
    );
  }
}
