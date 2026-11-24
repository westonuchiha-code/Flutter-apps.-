import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../mood.dart';

/// Plays a pet's frames (sharp pixels) on a sky that follows the time of
/// day and the weather.
class PetStage extends StatefulWidget {
  const PetStage({
    super.key,
    required this.frames,
    required this.mood,
    required this.look,
    this.child,
  });

  final List<ui.Image> frames;
  final Mood mood;
  final WeatherLook look;
  final Widget? child;

  @override
  State<PetStage> createState() => _PetStageState();
}

class _PetStageState extends State<PetStage> {
  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(PetStage old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) {
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    final ms = widget.mood == Mood.asleep
        ? 700
        : (widget.mood == Mood.happy ? 220 : 380);
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (mounted) {
        setState(() => _frame++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<Color> _sky() {
    final h = DateTime.now().hour;
    final grey = switch (widget.look) {
      WeatherLook.rain ||
      WeatherLook.storm ||
      WeatherLook.fog ||
      WeatherLook.cloud ||
      WeatherLook.snow => true,
      _ => false,
    };
    if (h < 6 || h >= 21) {
      return const [Color(0xFF0E1330), Color(0xFF26305E)];
    }
    if (h < 8 || h >= 18) {
      return const [Color(0xFF5A4A8C), Color(0xFFF29E6D)];
    }
    return grey
        ? const [Color(0xFF7C8796), Color(0xFFB5BDC8)]
        : const [Color(0xFF6EC3FF), Color(0xFFCDEBFF)];
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.frames;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _sky(),
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 24,
            child: ColoredBox(color: Color(0x3326472A)),
          ),
          if (f.isNotEmpty)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) {
                  // Whole-number scale (crisp pixels), at most ×10.
                  final k = ((box.biggest.shortestSide - 16) / 32)
                      .floor()
                      .clamp(1, 10);
                  return Align(
                    alignment: const Alignment(0, 0.6),
                    child: SizedBox.square(
                      dimension: 32.0 * k,
                      child: RawImage(
                        image: f[_frame % f.length],
                        filterQuality: FilterQuality.none,
                        fit: BoxFit.fill,
                      ),
                    ),
                  );
                },
              ),
            ),
          ?widget.child,
        ],
      ),
    );
  }
}
