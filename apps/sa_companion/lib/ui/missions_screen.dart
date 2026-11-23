import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../data/game_data.dart';
import '../data/models.dart';
import '../data/progress.dart';
import 'theme.dart';
import 'widgets.dart';

class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  final _search = TextEditingController();
  String _chapter = 'All';
  final Set<String> _open = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.state.progress;
    final q = _search.text.trim().toLowerCase();
    final children = <Widget>[];
    for (final chapter in chapters) {
      if (_chapter != 'All' && _chapter != chapter.name) continue;
      final rows = chapter.missions
          .where(
            (m) =>
                q.isEmpty ||
                '${m.name} ${m.giver} ${m.tip}'.toLowerCase().contains(q),
          )
          .toList();
      if (rows.isEmpty) continue;
      final done = chapter.missions.where(p.missionPassed).length;
      children
        ..add(
          SectionHeader(
            chapter.name,
            count: '$done / ${chapter.missions.length}',
          ),
        )
        ..addAll([
          for (final m in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MissionCard(
                mission: m,
                color: SaColors.region(chapter.name),
                passed: p.missionPassed(m),
                open: _open.contains(slug(m.name)) || q.isNotEmpty,
                onToggleOpen: () => setState(() {
                  final id = slug(m.name);
                  if (!_open.remove(id)) _open.add(id);
                }),
                onTick: () => widget.state.toggleMission(m),
              ),
            ),
        ]);
    }
    if (children.isEmpty) {
      children.add(const EmptyMessage('No missions match that search.'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        SearchField(
          controller: _search,
          hint: 'Search missions',
          onChanged: (_) => setState(() {}),
        ),
        FilterChips(
          options: ['All', for (final c in chapters) c.name],
          selected: _chapter,
          onSelected: (c) => setState(() => _chapter = c),
        ),
        ...children,
      ],
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.mission,
    required this.color,
    required this.passed,
    required this.open,
    required this.onToggleOpen,
    required this.onTick,
  });

  final Mission mission;
  final Color color;
  final bool passed;
  final bool open;
  final VoidCallback onToggleOpen;
  final VoidCallback onTick;

  @override
  Widget build(BuildContext context) {
    return SaCard(
      accent: color,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TickBox(
            checked: passed,
            onTap: onTick,
            label: 'Mark ${mission.name} passed',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onToggleOpen,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 4, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mission.name,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                  color: passed ? SaColors.dim : SaColors.ink,
                                ),
                              ),
                              Text(
                                mission.giver.toUpperCase(),
                                style: condensed(color: color),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 150),
                          turns: open ? 0.5 : 0,
                          child: const Icon(
                            Icons.expand_more,
                            color: SaColors.dim,
                          ),
                        ),
                      ],
                    ),
                    if (open)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          mission.tip,
                          style: const TextStyle(
                            fontSize: 15.5,
                            color: SaColors.body,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
