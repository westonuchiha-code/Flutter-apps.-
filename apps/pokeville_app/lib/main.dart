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
  settings: [folderSetting, swapSetting],
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String? _folder;
  bool _access = true;
  CrossSaveController? _sync;
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
      sync = CrossSaveController(shell.storage, only: const ['pokeville'])
        ..folders = at.xmb
        ..model = await _channel.invokeMethod<String>('deviceModel') ?? '';
      await sync.load();
    }
    if (!mounted) return;
    setState(() {
      _access = true;
      _folder = at.folder;
      _sync = sync;
    });
    if (sync != null && sync.token.isNotEmpty) await _syncNow();
  }

  Future<void> _syncNow() async {
    final rep = await _sync?.sync();
    if (!mounted || rep == null) return;
    setState(() => _generation++);
  }

  Future<void> _openSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SyncPage(controller: _sync, folder: _folder ?? ''),
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
  const SyncPage({super.key, required this.controller, required this.folder});

  /// Null: this platform doesn't sync here (Windows: the PC menu does).
  final CrossSaveController? controller;
  final String folder;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  Future<void> _askToken(CrossSaveController c) async {
    final text = TextEditingController();
    final t = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GitHub token'),
        content: TextField(
          controller: text,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'The same fine-grained token as the XMB',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (t == null || t.trim().isEmpty) return;
    final err = await c.setToken(t);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err == null ? 'Token saved' : 'That token did not work: $err',
        ),
      ),
    );
    if (err == null) unawaited(c.sync());
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
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('GitHub token'),
                    subtitle: Text(
                      c.token.isEmpty
                          ? 'Not set: paste the same token as the XMB Frontend'
                          : 'Set',
                    ),
                    onTap: () => unawaited(_askToken(c)),
                    trailing: c.token.isEmpty
                        ? null
                        : TextButton(
                            onPressed: () => unawaited(c.forgetToken()),
                            child: const Text('Forget'),
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
