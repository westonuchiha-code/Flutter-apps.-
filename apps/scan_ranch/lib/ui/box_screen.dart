import 'package:material_ui/material_ui.dart';

import '../model/creature.dart';
import '../model/game_state.dart';
import '../render/monster_art.dart';
import 'creature_sheet.dart';

/// Every monster you own: the ones on the ranch and the ones in storage.
class BoxScreen extends StatelessWidget {
  const BoxScreen({super.key, required this.game, required this.onScan});

  final GameState game;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final ranch = game.ranch, box = game.box;
        return SafeArea(
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'MONSTERS',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              if (game.creatures.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No monsters yet.'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: onScan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan a barcode'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (ranch.isNotEmpty)
                ..._section(
                  context,
                  'ON THE RANCH  ${ranch.length}/$ranchCapacity',
                  ranch,
                ),
              if (box.isNotEmpty)
                ..._section(context, 'IN THE BOX  ${box.length}', box),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<Creature> list,
  ) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: Color(0xFF8CFF5A),
          ),
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.8,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) => _Card(game: game, creature: list[i]),
      ),
    ),
  ];
}

class _Card extends StatelessWidget {
  const _Card({required this.game, required this.creature});
  final GameState game;
  final Creature creature;

  @override
  Widget build(BuildContext context) {
    final c = creature, g = c.genome;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF14171D),
      child: InkWell(
        onTap: () => showCreatureSheet(context, game, c),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MonsterPortrait(
                  silhouette: g.silhouette,
                  palette: paletteFor(g, c.individual),
                ),
              ),
              Text(
                c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '${'★' * g.rarity.stars} ${g.element.label}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9AA39A)),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: c.hunger,
                minHeight: 4,
                color: c.hunger < 0.25
                    ? const Color(0xFFFF5A4F)
                    : const Color(0xFFFFB13B),
                backgroundColor: const Color(0xFF22262E),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
