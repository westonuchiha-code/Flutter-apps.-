import 'package:material_ui/material_ui.dart';

import '../model/creature.dart';
import '../model/game_state.dart';
import '../render/monster_art.dart';

Future<void> showCreatureSheet(
  BuildContext context,
  GameState game,
  Creature c,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ListenableBuilder(
      listenable: game,
      builder: (context, _) => CreatureSheet(game: game, creature: c),
    ),
  );
}

/// Name, nickname, stats and actions for one monster.
class CreatureSheet extends StatelessWidget {
  const CreatureSheet({super.key, required this.game, required this.creature});

  final GameState game;
  final Creature creature;

  @override
  Widget build(BuildContext context) {
    final c = creature;
    final g = c.genome;
    final text = Theme.of(context).textTheme;
    final inRanch = c.home == Home.ranch;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          SizedBox(
            height: 180,
            child: MonsterPortrait(
              silhouette: g.silhouette,
              palette: paletteFor(g, c.individual),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  c.name,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Nickname',
                icon: const Icon(Icons.edit),
                onPressed: () => _rename(context),
              ),
            ],
          ),
          Text(
            [
              if (c.nickname != null) g.speciesName,
              '${g.tribe.label} tribe',
              g.element.label,
              c.individual.nature,
            ].join(' · '),
            style: text.bodyMedium?.copyWith(color: const Color(0xFF9AA39A)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text('${'★' * g.rarity.stars} ${g.rarity.label}')),
              if (c.individual.shiny) const Chip(label: Text('✦ Shiny')),
              Chip(label: Text(c.mood)),
            ],
          ),
          const SizedBox(height: 12),
          _Bar('Full', c.hunger, const Color(0xFFFFB13B)),
          _Bar('Happy', c.happiness, const Color(0xFFFF4F7A)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Bond: ${c.affection}'),
          ),
          const SizedBox(height: 16),
          Text('STATS', style: text.labelLarge?.copyWith(letterSpacing: 1.5)),
          const SizedBox(height: 6),
          _Bar(
            'HP',
            g.baseStats.hp / 99,
            const Color(0xFF8CFF5A),
            value: '${g.baseStats.hp}',
          ),
          _Bar(
            'ATK',
            g.baseStats.attack / 99,
            const Color(0xFFFF5A4F),
            value: '${g.baseStats.attack}',
          ),
          _Bar(
            'DEF',
            g.baseStats.defense / 99,
            const Color(0xFF4FA8FF),
            value: '${g.baseStats.defense}',
          ),
          _Bar(
            'SPD',
            g.baseStats.speed / 99,
            const Color(0xFFFFE14F),
            value: '${g.baseStats.speed}',
          ),
          const SizedBox(height: 12),
          Text(
            'Barcode ${g.code} · found ${_date(c.caughtAt)}',
            style: text.bodySmall?.copyWith(color: const Color(0xFF7A837A)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: Icon(
                    inRanch ? Icons.inventory_2_outlined : Icons.grass,
                  ),
                  label: Text(inRanch ? 'Send to Box' : 'Send to Ranch'),
                  onPressed: () {
                    final ok = game.moveTo(c, inRanch ? Home.box : Home.ranch);
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'The ranch is full (8). Move one to the Box first.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _release(context),
                child: const Text('Release'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _rename(BuildContext context) async {
    final name = await askNickname(
      context,
      creature.genome.speciesName,
      creature.nickname,
    );
    if (name != null) game.rename(creature, name);
  }

  Future<void> _release(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Release ${creature.name}?'),
        content: const Text('It will be gone for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Release'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      game.release(creature);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

/// Asks for a nickname. Returns '' to clear it, null if cancelled.
Future<String?> askNickname(
  BuildContext context,
  String species,
  String? current,
) {
  final controller = TextEditingController(text: current ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nickname'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 16,
        decoration: InputDecoration(hintText: species),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.fraction, this.color, {this.value});
  final String label;
  final double fraction;
  final Color color;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 8,
            color: color,
            backgroundColor: const Color(0xFF22262E),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        if (value != null)
          SizedBox(width: 32, child: Text(value!, textAlign: TextAlign.right)),
      ],
    ),
  );
}
