import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../data/game_data.dart';
import '../data/models.dart';
import 'follow_along_sheet.dart';
import 'glyphs.dart';
import 'theme.dart';
import 'widgets.dart';

class CheatsScreen extends StatefulWidget {
  const CheatsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<CheatsScreen> createState() => _CheatsScreenState();
}

class _CheatsScreenState extends State<CheatsScreen> {
  final _search = TextEditingController();
  String _category = 'All';

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
    for (final cat in cheatCategories) {
      final rows = cat.cheats.where((c) {
        final inCategory =
            _category == 'All' ||
            _category == cat.name ||
            (_category == 'Favorites' && p.isFavorite(c));
        final matches =
            q.isEmpty ||
            '${c.name} ${c.note} ${cat.name}'.toLowerCase().contains(q);
        return inCategory && matches;
      }).toList();
      if (rows.isEmpty) continue;
      children
        ..add(SectionHeader(cat.name, count: '${rows.length}'))
        ..addAll([
          for (final c in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CheatCard(
                cheat: c,
                favorite: p.isFavorite(c),
                onFavorite: () => widget.state.toggleFavorite(c),
              ),
            ),
        ]);
    }
    if (children.isEmpty) {
      children.add(
        EmptyMessage(
          _category == 'Favorites' && q.isEmpty
              ? 'No favorites yet. Tap a star to keep a cheat here and on the '
                    'Home tab.'
              : 'No cheats match that search.',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const NoteBox(
          bold: 'Save to a spare slot first.',
          text:
              'Cheats can lock out 100% and can corrupt a save. Tap a code to '
              'follow along button by button.',
        ),
        SearchField(
          controller: _search,
          hint: 'Search cheats, e.g. jetpack',
          onChanged: (_) => setState(() {}),
        ),
        FilterChips(
          options: [
            'All',
            'Favorites',
            for (final c in cheatCategories) c.name,
          ],
          selected: _category,
          onSelected: (c) => setState(() => _category = c),
        ),
        ...children,
      ],
    );
  }
}

class _CheatCard extends StatelessWidget {
  const _CheatCard({
    required this.cheat,
    required this.favorite,
    required this.onFavorite,
  });

  final Cheat cheat;
  final bool favorite;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return SaCard(
      onTap: () => showFollowAlong(context, cheat),
      semanticLabel: '${cheat.name}. Tap to follow along.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cheat.name,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (cheat.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          cheat.note,
                          style: const TextStyle(
                            color: SaColors.dim,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: favorite
                    ? 'Remove ${cheat.name} from favorites'
                    : 'Favorite ${cheat.name}',
                visualDensity: VisualDensity.compact,
                onPressed: onFavorite,
                icon: Icon(
                  favorite ? Icons.star : Icons.star_border,
                  color: favorite ? SaColors.gold : const Color(0xFF55625B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ButtonSequence(cheat.buttons),
        ],
      ),
    );
  }
}
