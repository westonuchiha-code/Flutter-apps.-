import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../model/game_state.dart';
import 'box_screen.dart';
import 'ranch_screen.dart';
import 'scan_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.game, this.scanner});

  final GameState game;
  final ScannerBuilder? scanner;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _tab = 0;
  Timer? _decay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Needs drift in real time.
    _decay = Timer.periodic(const Duration(minutes: 1), (_) {
      widget.game.applyDecay();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _decay?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.game.applyDecay();
    if (state == AppLifecycleState.paused) widget.game.saveNow();
  }

  void _go(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          // The ranch only animates while visible.
          TickerMode(
            enabled: _tab == 0,
            child: RanchScreen(game: game, onScan: () => _go(2)),
          ),
          BoxScreen(game: game, onScan: () => _go(2)),
          // The camera only runs while the Scan tab is open.
          _tab == 2
              ? ScanScreen(
                  game: game,
                  scanner: widget.scanner,
                  onKept: () => _go(0),
                )
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grass), label: 'Ranch'),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Box',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
        ],
      ),
    );
  }
}
