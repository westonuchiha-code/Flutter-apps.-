import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../model/controls.dart';
import '../model/session.dart';
import 'layout.dart';
import 'paint_kit.dart';

/// What a button is called on a pad of [type] (SDL's [labels] for the
/// face buttons when it has them). The start of "each console's own
/// names"; later parts add per-console tables.
String buttonName(
  GButton b,
  GamepadType type, [
  Map<GButton, ButtonLabel> labels = const {},
]) {
  final ps =
      type == GamepadType.ps3 ||
      type == GamepadType.ps4 ||
      type == GamepadType.ps5;
  final nintendo =
      type == GamepadType.switchPro ||
      type == GamepadType.joyConPair ||
      type == GamepadType.gameCube;
  final xbox = type == GamepadType.xbox360 || type == GamepadType.xboxOne;
  String face(ButtonLabel? l, String fallback) => switch (l) {
    ButtonLabel.a => 'A',
    ButtonLabel.b => 'B',
    ButtonLabel.x => 'X',
    ButtonLabel.y => 'Y',
    ButtonLabel.cross => '✕',
    ButtonLabel.circle => '○',
    ButtonLabel.square => '□',
    ButtonLabel.triangle => '△',
    _ => fallback,
  };
  return switch (b) {
    GButton.south => face(labels[b], ps ? '✕' : (nintendo ? 'B' : 'A')),
    GButton.east => face(labels[b], ps ? '○' : (nintendo ? 'A' : 'B')),
    GButton.west => face(labels[b], ps ? '□' : (nintendo ? 'Y' : 'X')),
    GButton.north => face(labels[b], ps ? '△' : (nintendo ? 'X' : 'Y')),
    GButton.back => switch (type) {
      GamepadType.ps3 => 'Select',
      GamepadType.ps4 => 'Share',
      GamepadType.ps5 => 'Create',
      GamepadType.xboxOne => 'View',
      _ when nintendo => '−',
      _ => 'Back',
    },
    GButton.start => switch (type) {
      GamepadType.ps4 || GamepadType.ps5 => 'Options',
      GamepadType.xboxOne => 'Menu',
      _ when nintendo => '+',
      _ => 'Start',
    },
    GButton.guide =>
      ps
          ? 'PS'
          : nintendo
          ? 'HOME'
          : xbox
          ? 'Xbox'
          : 'Guide',
    GButton.leftStick => ps ? 'L3' : 'LS click',
    GButton.rightStick => ps ? 'R3' : 'RS click',
    GButton.leftShoulder =>
      ps
          ? 'L1'
          : nintendo
          ? 'L'
          : 'LB',
    GButton.rightShoulder =>
      ps
          ? 'R1'
          : nintendo
          ? 'R'
          : 'RB',
    GButton.dpadUp => 'D-pad ↑',
    GButton.dpadDown => 'D-pad ↓',
    GButton.dpadLeft => 'D-pad ←',
    GButton.dpadRight => 'D-pad →',
    GButton.misc1 => switch (type) {
      GamepadType.ps5 => 'Mic',
      GamepadType.xboxOne => 'Share',
      _ when nintendo => 'Capture',
      _ => 'Misc 1',
    },
    GButton.touchpad => 'Touchpad',
    GButton.rightPaddle1 => 'Paddle R1',
    GButton.leftPaddle1 => 'Paddle L1',
    GButton.rightPaddle2 => 'Paddle R2',
    GButton.leftPaddle2 => 'Paddle L2',
    GButton.misc2 => 'Misc 2',
    GButton.misc3 => 'Misc 3',
    GButton.misc4 => 'Misc 4',
    GButton.misc5 => 'Misc 5',
    GButton.misc6 => 'Misc 6',
  };
}

String triggerName(GAxis a, GamepadType type) {
  final ps =
      type == GamepadType.ps3 ||
      type == GamepadType.ps4 ||
      type == GamepadType.ps5;
  final nintendo =
      type == GamepadType.switchPro ||
      type == GamepadType.joyConPair ||
      type == GamepadType.gameCube;
  final left = a == GAxis.leftTrigger;
  if (ps) return left ? 'L2' : 'R2';
  if (nintendo) return left ? 'ZL' : 'ZR';
  return left ? 'LT' : 'RT';
}

/// Any pad SDL has a mapping for, drawn as a generic modern pad (offset
/// sticks), with the button names of its type. Only what the mapping has
/// is drawn and tested.
class StandardPadLayout extends ControllerLayout {
  const StandardPadLayout();

  @override
  String get id => 'standard';

  @override
  String get title => 'Gamepad (SDL mapping)';

  @override
  bool matches(ControllerInfo info) => info.isGamepad;

  @override
  List<LayoutPart> parts(ControllerInfo info) {
    final t = info.gamepadType;
    final has = info.hasButtons;
    final out = <LayoutPart>[
      for (final b in GButton.values)
        if (has.contains(b) &&
            b != GButton.leftStick &&
            b != GButton.rightStick)
          LayoutPart.button(b.name, buttonName(b, t, info.labels), b),
      if (info.hasAxes.contains(GAxis.leftTrigger))
        LayoutPart.trigger(
          'lt',
          triggerName(GAxis.leftTrigger, t),
          GAxis.leftTrigger,
        ),
      if (info.hasAxes.contains(GAxis.rightTrigger))
        LayoutPart.trigger(
          'rt',
          triggerName(GAxis.rightTrigger, t),
          GAxis.rightTrigger,
        ),
      if (info.hasAxes.contains(GAxis.leftX))
        const LayoutPart.stick('ls', 'Left stick', GAxis.leftX, GAxis.leftY),
      if (has.contains(GButton.leftStick))
        LayoutPart.button(
          'leftStick',
          buttonName(GButton.leftStick, t),
          GButton.leftStick,
        ),
      if (info.hasAxes.contains(GAxis.rightX))
        const LayoutPart.stick('rs', 'Right stick', GAxis.rightX, GAxis.rightY),
      if (has.contains(GButton.rightStick))
        LayoutPart.button(
          'rightStick',
          buttonName(GButton.rightStick, t),
          GButton.rightStick,
        ),
    ];
    return out;
  }

  @override
  Size designSize(ControllerInfo info) => const Size(1000, 640);

  @override
  void paint(
    Canvas canvas,
    ControllerInfo info,
    PadState state,
    TestSession session,
    PadPalette palette,
  ) {
    const bodyFill = Color(0xFF3A3D48);
    const edge = Color(0xFF22242B);
    const btn = Color(0xFF555967);
    const ink = Color(0xFFE6E8EE);
    final pp = PadPainter(canvas, state, session, palette);
    final t = info.gamepadType;
    String name(GButton b) => buttonName(b, t, info.labels);

    RRect pill(double l, double t, double r, double b) =>
        RRect.fromLTRBR(l, t, r, b, const Radius.circular(22));
    pp.shapePart(
      'lt',
      Path()..addRRect(pill(180, 40, 350, 110)),
      fill: const Color(0xFF2C2E37),
      label: triggerName(GAxis.leftTrigger, t),
      labelAt: const Offset(265, 62),
      labelColor: ink,
      tickAt: const Offset(180, 46),
    );
    pp.shapePart(
      'rt',
      Path()..addRRect(pill(650, 40, 820, 110)),
      fill: const Color(0xFF2C2E37),
      label: triggerName(GAxis.rightTrigger, t),
      labelAt: const Offset(735, 62),
      labelColor: ink,
      tickAt: const Offset(820, 46),
    );
    pp.triggerBar('lt', const Rect.fromLTWH(190, 20, 150, 10));
    pp.triggerBar('rt', const Rect.fromLTWH(660, 20, 150, 10));
    pp.shapePart(
      'leftShoulder',
      Path()..addRRect(pill(150, 80, 380, 134)),
      fill: btn,
      label: name(GButton.leftShoulder),
      labelAt: const Offset(265, 98),
      labelColor: ink,
      tickAt: const Offset(150, 92),
    );
    pp.shapePart(
      'rightShoulder',
      Path()..addRRect(pill(620, 80, 850, 134)),
      fill: btn,
      label: name(GButton.rightShoulder),
      labelAt: const Offset(735, 98),
      labelColor: ink,
      tickAt: const Offset(850, 92),
    );

    final body = Path.combine(
      PathOperation.union,
      Path()..addRRect(
        RRect.fromLTRBR(120, 110, 880, 410, const Radius.circular(140)),
      ),
      Path.combine(
        PathOperation.union,
        _grip(const Offset(236, 400), 0.42),
        _grip(const Offset(764, 400), -0.42),
      ),
    );
    canvas.drawShadow(body, const Color(0xFF000000), 10, false);
    canvas.drawPath(body, Paint()..color = bodyFill);
    canvas.drawPath(
      body,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    pp.stick(
      'ls',
      'leftStick',
      const Offset(270, 230),
      well: 66,
      cap: 44,
      wellColor: const Color(0xFF23252D),
      capColor: btn,
    );
    pp.stick(
      'rs',
      'rightStick',
      const Offset(620, 360),
      well: 66,
      cap: 44,
      wellColor: const Color(0xFF23252D),
      capColor: btn,
    );
    pp.dpad(
      const Offset(380, 360),
      110,
      fill: btn,
      up: 'dpadUp',
      down: 'dpadDown',
      left: 'dpadLeft',
      right: 'dpadRight',
    );
    const face = Offset(730, 230);
    for (final (b, dx, dy) in [
      (GButton.north, 0.0, -1.0),
      (GButton.east, 1.0, 0.0),
      (GButton.south, 0.0, 1.0),
      (GButton.west, -1.0, 0.0),
    ]) {
      pp.roundButton(
        b.name,
        face + Offset(dx, dy) * 46,
        25,
        fill: btn,
        label: name(b),
        labelColor: ink,
        labelSize: 22,
      );
    }
    pp.roundButton(
      'back',
      const Offset(430, 230),
      16,
      fill: btn,
      label: name(GButton.back),
      labelColor: ink,
      labelSize: 9,
    );
    pp.roundButton(
      'start',
      const Offset(570, 230),
      16,
      fill: btn,
      label: name(GButton.start),
      labelColor: ink,
      labelSize: 9,
    );
    pp.roundButton(
      'guide',
      const Offset(500, 175),
      24,
      fill: btn,
      label: name(GButton.guide),
      labelColor: ink,
      labelSize: 13,
    );
    // Extra buttons (misc, paddles, touchpad) in a row under the pad.
    final extras = [
      for (final b in GButton.values.skip(GButton.misc1.index))
        if (info.hasButtons.contains(b)) b,
    ];
    for (var i = 0; i < extras.length; i++) {
      final b = extras[i];
      final x = 500 + (i - (extras.length - 1) / 2) * 64;
      pp.roundButton(
        b.name,
        Offset(x, 600),
        22,
        fill: btn,
        label: name(b),
        labelColor: ink,
        labelSize: 9,
      );
    }
  }

  static Path _grip(Offset c, double angle) {
    final cos = math.cos(angle), sin = math.sin(angle);
    return (Path()..addOval(
          Rect.fromCenter(center: Offset.zero, width: 220, height: 290),
        ))
        .transform(
          Float64List.fromList([
            cos, sin, 0, 0, //
            -sin, cos, 0, 0,
            0, 0, 1, 0,
            c.dx, c.dy, 0, 1,
          ]),
        );
  }
}
