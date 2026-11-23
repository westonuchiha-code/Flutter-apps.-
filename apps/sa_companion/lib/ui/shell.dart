import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../data/progress.dart';
import 'cheats_screen.dart';
import 'guide_screen.dart';
import 'home_screen.dart';
import 'missions_screen.dart';
import 'theme.dart';
import 'tracker_screen.dart';
import 'widgets.dart';

/// Top HUD bar, five tabs and the "Mission passed" banner.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.state});

  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _titles = [
    'SA Companion',
    'Cheats',
    'Missions',
    '100%',
    'Guide',
  ];
  static const _tabs = [
    (Icons.home_outlined, 'Home'),
    (Icons.sports_esports_outlined, 'Cheats'),
    (Icons.flag_outlined, 'Missions'),
    (Icons.checklist, '100%'),
    (Icons.place_outlined, 'Guide'),
  ];

  String _subtitle() => switch (_tab) {
    0 => 'PS2 · Unofficial',
    1 => '${allCheats.length} codes',
    2 => '${widget.state.progress.storyDone} of $missionCount passed',
    3 => 'Counts toward 100%',
    _ => 'Places & reference',
  };

  void _go(int tab) {
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF080A09),
      ),
      child: PopScope(
        // Back goes to Home before leaving the app.
        canPop: _tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _tab = 0);
        },
        child: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: _Backdrop()),
              Column(
                children: [
                  ListenableBuilder(
                    listenable: state,
                    builder: (context, _) => _TopBar(
                      title: _titles[_tab],
                      subtitle: _subtitle(),
                      stats: state.progress.stats,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: ListenableBuilder(
                          listenable: state,
                          builder: (context, _) => IndexedStack(
                            index: _tab,
                            children: [
                              HomeScreen(state: state, onGo: _go),
                              CheatsScreen(state: state),
                              MissionsScreen(state: state),
                              TrackerScreen(state: state),
                              const GuideScreen(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _BottomBar(index: _tab, tabs: _tabs, onTap: _go),
                ],
              ),
              MissionPassedBanner(name: state.missionPassed),
            ],
          ),
        ),
      ),
    );
  }
}

/// Warm glow at the top of the dark background.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(0, -1.35),
        radius: 1.1,
        colors: [Color(0xFF3A2312), SaColors.bg],
        stops: [0, 0.7],
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.stats,
  });

  final String title;
  final String subtitle;
  final Stats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF8060807), Color(0xE6080A09)],
        ),
        border: Border(bottom: BorderSide(color: Colors.black, width: 2)),
        boxShadow: [BoxShadow(color: SaColors.line, offset: Offset(0, 1))],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: OutlinedText(title, size: 21, maxLines: 1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle.toUpperCase(),
                        style: condensed(weight: FontWeight.w600, spacing: 1.3),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: 'Overall progress ${stats.percent} percent',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      OutlinedText(
                        '${stats.percent}%',
                        size: 22,
                        color: SaColors.money,
                        shadow: false,
                      ),
                      const SizedBox(height: 3),
                      WantedStars(stats.stars),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.tabs,
    required this.onTap,
  });

  final int index;
  final List<(IconData, String)> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF8060807), Color(0xE6080A09)],
        ),
        border: Border(top: BorderSide(color: Colors.black, width: 2)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    button: true,
                    label: tabs[i].$2,
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => onTap(i),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(2, 7, 2, 8),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: i == index
                                  ? SaColors.gold
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          gradient: i == index
                              ? const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x24F3B93A),
                                    Colors.transparent,
                                  ],
                                )
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tabs[i].$1,
                              size: 24,
                              color: i == index ? SaColors.gold : SaColors.dim,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tabs[i].$2.toUpperCase(),
                              style: condensed(
                                size: 12,
                                color: i == index
                                    ? SaColors.gold
                                    : SaColors.dim,
                                spacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "MISSION PASSED" banner, like the game, shown when a mission is ticked.
class MissionPassedBanner extends StatefulWidget {
  const MissionPassedBanner({super.key, required this.name});

  final ValueNotifier<String?> name;

  @override
  State<MissionPassedBanner> createState() => _MissionPassedBannerState();
}

class _MissionPassedBannerState extends State<MissionPassedBanner>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  );
  String _shown = '';

  @override
  void initState() {
    super.initState();
    widget.name.addListener(_onPassed);
  }

  @override
  void dispose() {
    widget.name.removeListener(_onPassed);
    _anim.dispose();
    super.dispose();
  }

  void _onPassed() {
    final name = widget.name.value;
    if (name == null) return;
    widget.name.value = null;
    HapticFeedback.mediumImpact();
    setState(() => _shown = name);
    unawaited(_anim.forward(from: 0));
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Mission passed: $name',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final t = _anim.value;
          if (!_anim.isAnimating) return const SizedBox.shrink();
          // Pop in, hold, then drift up and fade (like the original CSS).
          final opacity = t < 0.1 ? t / 0.1 : (t > 0.8 ? (1 - t) / 0.2 : 1.0);
          final scale = reduceMotion
              ? 1.0
              : t < 0.1
              ? 0.7 + 0.36 * (t / 0.1)
              : t < 0.16
              ? 1.06 - 0.06 * ((t - 0.1) / 0.06)
              : 1.0;
          final dy = t > 0.8 && !reduceMotion ? -14 * (t - 0.8) / 0.2 : 0.0;
          return Align(
            alignment: const Alignment(0, -0.32),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Transform.scale(scale: scale, child: child),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OutlinedText(
                'Mission passed',
                size: 36,
                color: SaColors.gold,
                stroke: 9,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _shown.toUpperCase(),
                textAlign: TextAlign.center,
                style: condensed(size: 20, color: Colors.white, spacing: 2)
                    .copyWith(
                      shadows: const [
                        Shadow(color: Colors.black, offset: Offset(0, 2)),
                        Shadow(color: Colors.black, blurRadius: 8),
                      ],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
