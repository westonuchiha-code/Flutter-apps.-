import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// Green on-screen text with a soft glow, like an 80s TV's channel display.
TextStyle osdStyle(double size, {double opacity = 1}) => TextStyle(
      color: const Color(0xFF5CFF3A).withValues(alpha: opacity),
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: size * 0.08,
      height: 1.1,
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Consolas', 'Courier New', 'DejaVu Sans Mono', 'Menlo'],
      shadows: [
        Shadow(color: const Color(0xFF2BFF00).withValues(alpha: 0.7), blurRadius: size * 0.35),
        Shadow(color: Colors.black.withValues(alpha: 0.9), offset: Offset(size * 0.05, size * 0.05)),
      ],
    );

/// Channel number (top right) and what's on (bottom left).
class ChannelOsd extends StatelessWidget {
  const ChannelOsd({super.key, this.channel, this.name, this.title});

  final String? channel;
  final String? name;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight;
        final big = max(18.0, h * 0.085);
        final small = max(11.0, h * 0.042);
        final ch = channel;
        final channelName = name;
        final showTitle = title;
        return Stack(
          children: [
            if (ch != null)
              Positioned(
                top: h * 0.06,
                right: h * 0.07,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(ch, style: osdStyle(big)),
                    if (channelName != null) Text(channelName.toUpperCase(), style: osdStyle(small)),
                  ],
                ),
              ),
            if (ch != null && showTitle != null)
              Positioned(
                left: h * 0.07,
                right: h * 0.07,
                bottom: h * 0.07,
                child: Text(
                  showTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: osdStyle(small),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// "VOLUME ▮▮▮▮▮▯▯▯" bar along the bottom.
class VolumeOsd extends StatelessWidget {
  const VolumeOsd({super.key, required this.volume, required this.muted});

  final double volume;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight;
        final size = max(11.0, h * 0.045);
        const blocks = 20;
        final lit = muted ? 0 : (volume / 100 * blocks).round();
        return Align(
          alignment: const Alignment(0, 0.78),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(muted ? 'MUTE  ' : 'VOLUME  ', style: osdStyle(size)),
              for (var i = 0; i < blocks; i++)
                Container(
                  width: size * 0.42,
                  height: size * 0.9,
                  margin: EdgeInsets.only(right: size * 0.14),
                  decoration: BoxDecoration(
                    color: i < lit
                        ? const Color(0xFF5CFF3A)
                        : const Color(0xFF5CFF3A).withValues(alpha: 0.18),
                    boxShadow: i < lit
                        ? [BoxShadow(color: const Color(0xFF2BFF00).withValues(alpha: 0.6), blurRadius: size * 0.3)]
                        : null,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
