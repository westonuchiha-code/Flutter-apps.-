import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../data/models.dart';
import '../data/progress.dart';
import 'follow_along_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.state, required this.onGo});

  final AppState state;

  /// Switches to another tab (index in the bottom bar).
  final ValueChanged<int> onGo;

  static const _defaultQuick = [
    'Full health, armor and \$250,000',
    'Jetpack',
    'Weapon set 1',
    'Clear wanted level',
  ];

  @override
  Widget build(BuildContext context) {
    final p = state.progress;
    final st = p.stats;
    final next = p.nextMission;
    final favs = allCheats.where(p.isFavorite).toList();
    final quick =
        (favs.isNotEmpty
                ? favs
                : [
                    for (final n in _defaultQuick)
                      ...allCheats.where((c) => c.name == n),
                  ])
            .take(6)
            .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        const _Hero(),
        const SizedBox(height: 12),
        SaCard(
          child: LayoutBuilder(
            builder: (context, c) {
              final radar = _Radar(percent: st.percent);
              final bars = Column(
                children: [
                  _Stat(
                    'Story',
                    '${st.storyDone} / $missionCount',
                    st.storyDone / missionCount,
                    MeterStyle.health,
                  ),
                  _Stat(
                    'Collectibles',
                    '${st.collected} / ${st.collectibleTotal}',
                    st.collected / st.collectibleTotal,
                    MeterStyle.armor,
                  ),
                  _Stat(
                    'Side jobs',
                    '${st.sideDone.floor()} / ${st.sideTotal}',
                    st.sideDone / st.sideTotal,
                    MeterStyle.gold,
                    last: true,
                  ),
                ],
              );
              if (c.maxWidth < 320) {
                return Column(
                  children: [radar, const SizedBox(height: 12), bars],
                );
              }
              return Row(
                children: [
                  radar,
                  const SizedBox(width: 14),
                  Expanded(child: bars),
                ],
              );
            },
          ),
        ),
        const SectionHeader('Next on your list'),
        if (next != null)
          _NextMissionCard(
            mission: next,
            onPass: () => state.passMission(next),
            onAll: () => onGo(2),
          )
        else
          SaCard(
            accent: SaColors.gold,
            accentWidth: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Every story mission is passed',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Head to the 100% tab for what's left: collectibles, "
                  'schools, races and the rest.',
                  style: TextStyle(color: SaColors.body, fontSize: 15.5),
                ),
                const SizedBox(height: 12),
                SaButton('Open 100%', onPressed: () => onGo(3)),
              ],
            ),
          ),
        SectionHeader(favs.isNotEmpty ? 'Your cheats' : 'Quick cheats'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.9,
          children: [
            for (final c in quick)
              SaCard(
                onTap: () => showFollowAlong(context, c),
                semanticLabel: '${c.name}. Tap to follow along.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.sports_esports_outlined,
                          size: 18,
                          color: SaColors.gold,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${c.buttons.length} BUTTONS',
                            overflow: TextOverflow.ellipsis,
                            style: condensed(color: SaColors.gold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
    this.label,
    this.value,
    this.fraction,
    this.style, {
    this.last = false,
  });

  final String label;
  final String value;
  final double fraction;
  final MeterStyle style;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 11),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: condensed(size: 14, color: SaColors.ink, spacing: 1.2),
              ),
            ),
            Text(value, style: condensed(size: 14, spacing: 1.2)),
          ],
        ),
        const SizedBox(height: 4),
        Meter(fraction, style: style),
      ],
    ),
  );
}

class _NextMissionCard extends StatelessWidget {
  const _NextMissionCard({
    required this.mission,
    required this.onPass,
    required this.onAll,
  });

  final Mission mission;
  final VoidCallback onPass;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final chapter = chapterOf(mission);
    final rc = SaColors.region(chapter);
    return SaCard(
      accent: rc,
      accentWidth: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$chapter · ${mission.giver}'.toUpperCase(),
            style: condensed(color: rc, spacing: 1.5),
          ),
          const SizedBox(height: 2),
          Text(
            mission.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            mission.tip,
            style: const TextStyle(color: SaColors.body, fontSize: 15.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SaButton('Mark passed', onPressed: onPass),
              SaButton(
                'All missions',
                kind: SaButtonKind.ghost,
                onPressed: onAll,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sunset skyline banner with the logo and a live clock.
class _Hero extends StatefulWidget {
  const _Hero();

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int v) => v.toString().padLeft(2, '0');
    return Container(
      height: 150,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: SaColors.line, spreadRadius: 1),
          BoxShadow(color: Colors.black, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: SkylinePainter()),
            Positioned(
              right: 14,
              top: 12,
              child: ExcludeSemantics(
                child: OutlinedText(
                  '${two(_now.hour)}:${two(_now.minute)}',
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 12,
              right: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, c) => OutlinedText(
                      'San Andreas',
                      size: c.maxWidth < 300 ? 26 : 31,
                      color: Colors.white,
                      stroke: 7,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'PS2 COMPANION',
                    style: condensed(size: 15, color: SaColors.gold, spacing: 3)
                        .copyWith(
                          shadows: const [
                            Shadow(color: Colors.black, offset: Offset(0, 2)),
                            Shadow(color: Colors.black, blurRadius: 6),
                          ],
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The original banner art: gradient sky, sun, downtown silhouette and two
/// palm trees (viewBox 560×150, anchored to the bottom like the SVG).
class SkylinePainter extends CustomPainter {
  const SkylinePainter();

  static const _buildings = [
    [118, 86, 26, 64],
    [146, 70, 20, 80],
    [168, 96, 30, 54],
    [200, 60, 18, 90],
    [220, 82, 28, 68],
    [250, 102, 24, 48],
    [276, 74, 22, 76],
    [300, 92, 30, 58],
    [332, 66, 20, 84],
    [354, 100, 26, 50],
    [382, 84, 22, 66],
    [406, 104, 34, 46],
    [442, 90, 24, 60],
    [0, 128, 560, 22],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(size.width / 560, size.height / 150);
    canvas
      ..save()
      ..translate((size.width - 560 * scale) / 2, size.height - 150 * scale)
      ..scale(scale);
    const box = Rect.fromLTWH(0, 0, 560, 150);
    canvas.drawRect(
      box,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1A3D), Color(0xFFB3432F), Color(0xFFF4A63A)],
        ).createShader(box),
    );
    canvas.drawCircle(
      const Offset(395, 92),
      30,
      Paint()..color = const Color(0xEBFFD783),
    );
    final dark = Paint()..color = const Color(0xFF150F16);
    for (final b in _buildings) {
      canvas.drawRect(
        Rect.fromLTWH(
          b[0].toDouble(),
          b[1].toDouble(),
          b[2].toDouble(),
          b[3].toDouble(),
        ),
        dark,
      );
    }
    final trunk = Paint()
      ..color = const Color(0xFF150F16)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    final frond = Paint()
      ..color = const Color(0xFF150F16)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.6;
    void palm(double baseX, double topX, double topY, double dir) {
      canvas.drawPath(
        Path()
          ..moveTo(baseX, 140)
          ..cubicTo(baseX + 3 * dir, 112, baseX - 2 * dir, 90, topX, topY),
        trunk,
      );
      for (final q in [
        [-24, -4, -38, 10],
        [-12, -18, -32, -14],
        [10, -18, 30, -14],
        [22, -6, 36, 8],
        [-4, -14, 0, -24],
      ]) {
        canvas.drawPath(
          Path()
            ..moveTo(topX, topY)
            ..relativeQuadraticBezierTo(
              q[0] * dir,
              q[1].toDouble(),
              q[2] * dir,
              q[3].toDouble(),
            ),
          frond,
        );
      }
    }

    palm(52, 58, 66, 1);
    palm(508, 502, 72, -1);
    canvas.drawRect(
      box,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.35, 1],
          colors: [Color(0x00000000), Color(0xBF000000)],
        ).createShader(box),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkylinePainter old) => false;
}

/// Radar-style progress ring.
class _Radar extends StatelessWidget {
  const _Radar({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Overall progress $percent percent',
    child: SizedBox.square(
      dimension: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(150),
            painter: _RadarPainter(percent / 100),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedText(
                '$percent%',
                size: 30,
                color: SaColors.money,
                stroke: 6,
              ),
              const SizedBox(height: 4),
              Text('PROGRESS', style: condensed(size: 12, spacing: 2)),
            ],
          ),
        ],
      ),
    ),
  );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 160);
    const c = Offset(80, 80);
    Paint stroke(Color color, double w) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    canvas
      ..drawCircle(c, 76, Paint()..color = const Color(0xFF0A0F0C))
      ..drawCircle(c, 76, stroke(Colors.black, 4))
      ..drawCircle(c, 76, stroke(const Color(0xFF2F3B35), 1.5))
      ..drawLine(
        const Offset(80, 10),
        const Offset(80, 150),
        stroke(const Color(0xFF18211C), 1.5),
      )
      ..drawLine(
        const Offset(10, 80),
        const Offset(150, 80),
        stroke(const Color(0xFF18211C), 1.5),
      )
      ..drawCircle(c, 40, stroke(const Color(0xFF18211C), 1.5))
      ..drawCircle(c, 66, stroke(const Color(0xFF1A231E), 9));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 66),
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      stroke(SaColors.money, 9),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.fraction != fraction;
}
