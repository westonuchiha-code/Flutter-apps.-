import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lofi_video/src/media.dart';
import 'package:lofi_video/src/project.dart';
import 'package:lofi_video/src/render.dart';
import 'package:lofi_video/src/title.dart';
import 'package:lofi_video/src/transitions.dart';
import 'package:video_kit/video_kit.dart';

import 'support.dart';

/// Share of pixels close to [color] (transitions may dim slightly).
double share(VideoFrame f, int color) =>
    f.pixels.where((p) {
      int d(int s) => (((p >> s) & 255) - ((color >> s) & 255)).abs();
      return d(16) < 40 && d(8) < 40 && d(0) < 40;
    }).length /
    f.pixels.length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const red = 0xFFFF0000, blue = 0xFF0000FF;
  final a = solid(320, 240, red), b = solid(320, 240, blue);

  test('every transition goes from the old picture to the new one', () {
    for (final t in Transition.values) {
      final start = applyTransition(t, a, b, 0.02, 0);
      final end = applyTransition(t, a, b, 0.995, 1);
      expect(start.width, 320, reason: t.name);
      if (t != Transition.cut) {
        expect(share(start, blue), lessThan(0.2), reason: '${t.name} start');
      }
      expect(share(end, blue), greaterThan(0.8), reason: '${t.name} end');
    }
    expect(
      share(applyTransition(Transition.dither, a, b, 0.5, 0), blue),
      closeTo(0.5, 0.02),
    );
  });

  test(
    'renderer: transitions, overlays through and above the effect',
    () async {
      final sprite = decodeMedia('json', makeSprite()) as AnimMedia;
      // See-through sprite pixels stay see-through.
      expect(
        sprite.frames.first.pixels.contains(0),
        isFalse,
      ); // background filled
      final text = SceneOverlay(
        kind: OverlayKind.text,
        text: 'HI',
        color: 0xFFFFEC27,
        y: 0.5,
        scale: 4,
      );
      final above = SceneOverlay(
        kind: OverlayKind.sprite,
        asset: {'id': 'sprite'},
        x: 0.1,
        y: 0.1,
        scale: 2,
        aboveEffect: true,
      );
      final p = Project(
        scenes: [
          Scene(
            kind: SceneKind.title,
            text: 'A',
            textColor: red,
            background: red,
            duration: 1,
          ),
          Scene(
            kind: SceneKind.bars,
            duration: 2,
            transition: Transition.dither,
            transitionLength: 0.5,
            overlays: [text, above],
            effectId: 'gbcam',
          ),
        ],
      );
      final pics = {
        p.scenes[0].id: await renderTitle(p.scenes[0]),
        text.id: await renderTextOverlay(text),
      };
      final overlayPic = pics[text.id]!;
      expect(
        overlayPic.pixels.contains(0),
        isTrue,
      ); // see-through around the text
      expect(overlayPic.pixels.toSet(), {0, 0xFFFFEC27, 0xFF000000});

      final r = Renderer(p, {'sprite': sprite}, pics);
      final mid = r.frameAt(1.25); // half way through the dissolve
      final gb = r.frameAt(1.9);
      // Game Boy Camera: 4 greens only, except the clean sprite above it.
      final colors = gb.pixels.toSet();
      expect(colors.contains(0xFFFF004D), isTrue); // sprite above the effect
      expect(colors.length, lessThanOrEqualTo(4 + 2));
      expect(
        mid.pixels.any((c) => c == red),
        isTrue,
      ); // old scene still showing
    },
  );

  test('snapping to the beat', () {
    final p = Project(bpm: 120, snap: true);
    expect(p.beat, 0.5);
    expect(p.snapped(1.3), 1.5);
    expect(p.snapped(0.1), 0.5);
    p.snap = false;
    expect(p.snapped(1.3), 1.3);
  });

  test('transitions and overlays survive saving', () {
    final s = Scene(
      kind: SceneKind.bars,
      transition: Transition.mosh,
      transitionLength: 0.8,
      overlays: [
        SceneOverlay(
          kind: OverlayKind.text,
          text: 'X',
          from: 0.5,
          to: 1.5,
          aboveEffect: true,
        ),
      ],
    );
    final p = Project(scenes: [s], bpm: 97, snap: true);
    final q = Project.fromJson(jsonDecode(jsonEncode(p.toJson())));
    expect(q.bpm, 97);
    expect(q.snap, isTrue);
    expect(q.scenes.single.transition, Transition.mosh);
    final o = q.scenes.single.overlays.single;
    expect(o.text, 'X');
    expect(o.visibleAt(0.4), isFalse);
    expect(o.visibleAt(1), isTrue);
    expect(o.visibleAt(1.5), isFalse);
    expect(o.aboveEffect, isTrue);
    // Duplicating gives the overlays new ids.
    final dup = s.copy(newId: true);
    expect(dup.overlays.single.id, isNot(s.overlays.single.id));
  });
}
