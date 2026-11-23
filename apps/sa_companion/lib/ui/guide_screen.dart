import 'package:material_ui/material_ui.dart';

import '../data/game_data.dart';
import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart';

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  bool _reference = false;
  String _area = 'All';

  @override
  Widget build(BuildContext context) {
    final areas = [
      'All',
      ...{for (final p in places) p.area},
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _Segmented(
          reference: _reference,
          onChanged: (r) => setState(() => _reference = r),
        ),
        const SizedBox(height: 12),
        if (!_reference) ...[
          FilterChips(
            options: areas,
            selected: _area,
            onSelected: (a) => setState(() => _area = a),
          ),
          for (final p in places.where(
            (p) => _area == 'All' || p.area == _area,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SaCard(
                accent: SaColors.region(p.area),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.area.toUpperCase(),
                      style: condensed(
                        color: SaColors.region(p.area),
                        spacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      p.description,
                      style: const TextStyle(
                        color: SaColors.body,
                        fontSize: 15.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ] else
          for (final section in referenceSections) ...[
            SectionHeader(section.title),
            for (final block in section.blocks) _RefBlockView(block),
          ],
      ],
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.reference, required this.onChanged});

  final bool reference;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool value) {
      final on = reference == value;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: on ? SaColors.gold : Colors.transparent,
              alignment: Alignment.center,
              child: Text(
                label.toUpperCase(),
                style: condensed(
                  size: 16,
                  color: on ? const Color(0xFF1A1203) : SaColors.dim,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: SaColors.field,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: SaColors.line, spreadRadius: 1)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(children: [seg('Places', false), seg('Reference', true)]),
      ),
    );
  }
}

class _RefBlockView extends StatelessWidget {
  const _RefBlockView(this.block);

  final RefBlock block;

  @override
  Widget build(BuildContext context) {
    switch (block) {
      case RefCard(:final text):
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SaCard(
            child: Text(text, style: const TextStyle(fontSize: 15)),
          ),
        );
      case RefText(:final text):
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            text,
            style: const TextStyle(color: SaColors.dim, fontSize: 15),
          ),
        );
      case RefTable(:final rows):
        final columns = rows
            .map((r) => r.cells.length)
            .reduce((a, b) => a > b ? a : b);
        return Container(
          decoration: BoxDecoration(
            color: SaColors.p2,
            border: Border.all(color: SaColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            columnWidths: {
              for (var i = 0; i < columns; i++)
                i: i == 0
                    ? const FlexColumnWidth(1.4)
                    : const FlexColumnWidth(),
            },
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  decoration: r == rows.length - 1
                      ? null
                      : const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: SaColors.line),
                          ),
                        ),
                  children: [
                    for (var c = 0; c < columns; c++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          () {
                            final t = c < rows[r].cells.length
                                ? rows[r].cells[c]
                                : '';
                            return rows[r].header ? t.toUpperCase() : t;
                          }(),
                          style: rows[r].header
                              ? condensed(color: SaColors.gold, spacing: 1.2)
                              : const TextStyle(fontSize: 14.5),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
    }
  }
}
