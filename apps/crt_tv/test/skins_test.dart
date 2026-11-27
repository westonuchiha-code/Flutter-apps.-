import 'dart:ui' as ui;

import 'package:crt_tv/src/models.dart';
import 'package:crt_tv/src/ui/controls.dart';
import 'package:crt_tv/src/ui/skins.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A whole cabinet: the painted body plus its controls.
Widget cabinet(SkinStyle skin, Size size, Key key) {
  final layout = CabinetLayout.of(size, skin);
  return RepaintBoundary(
    key: key,
    child: SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: SkinPainter(
                style: skin,
                screenRect: layout.screenRect,
                bezel: layout.bezel,
                speaker: layout.decorate,
                chin: layout.chin,
              ),
            ),
          ),
          if (layout.clock != null) Positioned.fromRect(rect: layout.clock!, child: const VcrClock()),
          if (layout.decorate)
            Positioned(
              left: layout.screenRect.right + layout.bezel,
              top: 0,
              bottom: 0,
              width: layout.pillar,
              child: SidePanel(state: PanelState(skin: skin, channelNumber: 4, volume: 70), width: layout.pillar),
            ),
        ],
      ),
    ),
  );
}

void main() {
  final skins = SkinStyle.values.where((s) => s != SkinStyle.none).toList();

  testWidgets('every cabinet lays out at any window size', (tester) async {
    tester.view.devicePixelRatio = 1;
    // Wide, small, nearly square (pillars too thin to dress) and tall.
    for (final size in const [Size(1920, 1080), Size(640, 360), Size(820, 600), Size(400, 700)]) {
      tester.view.physicalSize = size;
      for (final skin in skins) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: cabinet(skin, size, UniqueKey()))));
        expect(tester.takeException(), isNull, reason: '${skin.name} at $size');
      }
    }
  });

  testWidgets('no cabinet is a flat slab of colour', (tester) async {
    const size = Size(1280, 720);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    for (final skin in skins) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: cabinet(skin, size, key))));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final pixels = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      // Count the different colours (to 16 levels a channel) down the left
      // pillar, where a cabinet's material and decoration show.
      final pillar = CabinetLayout.of(size, skin).pillar.floor();
      final seen = <int>{};
      for (var y = 0; y < size.height; y += 4) {
        for (var x = 0; x < pillar; x += 4) {
          final i = (y * size.width.toInt() + x) * 4;
          seen.add((pixels!.getUint8(i) >> 4) << 8 | (pixels.getUint8(i + 1) >> 4) << 4 | pixels.getUint8(i + 2) >> 4);
        }
      }
      // ignore: avoid_print
      print('${skin.name}: ${seen.length} colours');
      // "Black plastic" is one of the original plain cabinets: a bare
      // gradient on purpose. Everything else has to show some material.
      if (skin == SkinStyle.black) continue;
      expect(seen.length, greaterThan(12), reason: '${skin.name} looks flat: only ${seen.length} colours');
    }
  });

  test('every cabinet has a name, a description and menu colours', () {
    for (final skin in SkinStyle.values) {
      expect(skin.label, isNotEmpty);
      expect(skin.blurb, isNotEmpty);
      final palette = OsdPalette.of(skin);
      expect(palette.ink, isNot(palette.panel));
      expect(palette.barInk, isNot(palette.bar));
    }
  });
}
