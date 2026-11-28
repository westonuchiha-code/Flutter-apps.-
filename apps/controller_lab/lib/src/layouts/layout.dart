import 'dart:math' as math;
import 'dart:ui';

import '../model/controls.dart';
import '../model/guess.dart';
import '../model/session.dart';
import 'raw.dart';
import 'standard.dart';
import 'wii_u_pro.dart';

enum PartKind {
  /// Pressed or not.
  button,

  /// 0..1 (an analog trigger, or a digital one SDL reports as an axis).
  trigger,

  /// Two axes, -1..1 each.
  stick,

  /// One raw joystick axis, -1..1.
  axis,
}

/// One thing on a controller to test: a button, trigger, stick or raw
/// axis, and where its value comes from (SDL's named gamepad controls, or
/// the raw joystick's numbered ones).
class LayoutPart {
  const LayoutPart.button(this.id, this.label, GButton this.button)
    : kind = PartKind.button,
      axis = null,
      axisY = null,
      raw = null,
      hatBit = null;

  const LayoutPart.trigger(this.id, this.label, GAxis this.axis)
    : kind = PartKind.trigger,
      button = null,
      axisY = null,
      raw = null,
      hatBit = null;

  const LayoutPart.stick(this.id, this.label, GAxis this.axis, GAxis this.axisY)
    : kind = PartKind.stick,
      button = null,
      raw = null,
      hatBit = null;

  /// Raw joystick button [raw].
  const LayoutPart.rawButton(this.id, this.label, int this.raw)
    : kind = PartKind.button,
      button = null,
      axis = null,
      axisY = null,
      hatBit = null;

  /// Raw joystick axis [raw].
  const LayoutPart.rawAxis(this.id, this.label, int this.raw)
    : kind = PartKind.axis,
      button = null,
      axis = null,
      axisY = null,
      hatBit = null;

  /// One direction ([hatBit]: 1 up, 2 right, 4 down, 8 left) of raw hat
  /// [raw].
  const LayoutPart.hat(this.id, this.label, int this.raw, int this.hatBit)
    : kind = PartKind.button,
      button = null,
      axis = null,
      axisY = null;

  /// Stable within a layout (the checklist is keyed by it).
  final String id;

  /// What's printed on the controller (or how the owner would call it).
  final String label;
  final PartKind kind;
  final GButton? button;
  final GAxis? axis, axisY;
  final int? raw, hatBit;

  /// Buttons: 0/1. Triggers: 0..1. Raw axes: -1..1. Sticks: how far
  /// from centre (0..1).
  double value(PadState s) {
    switch (kind) {
      case PartKind.button:
        if (button != null) return s.button(button!) ? 1 : 0;
        if (hatBit != null) {
          return raw! < s.hats.length && s.hats[raw!] & hatBit! != 0 ? 1 : 0;
        }
        return raw! < s.buttons.length && s.buttons[raw!] ? 1 : 0;
      case PartKind.trigger:
        return s.axisValue(axis!).clamp(0.0, 1.0);
      case PartKind.axis:
        return raw! < s.axes.length
            ? (s.axes[raw!] / 32767).clamp(-1.0, 1.0)
            : 0;
      case PartKind.stick:
        final (x, y) = stick(s);
        return math.min(1, math.sqrt(x * x + y * y));
    }
  }

  /// A stick's position, -1..1 (down and right positive).
  (double, double) stick(PadState s) =>
      (s.axisValue(axis!), s.axisValue(axisY!));

  /// Lit on the drawing.
  bool active(PadState s, {double deadzone = 0.15}) => switch (kind) {
    PartKind.button => value(s) > 0.5,
    PartKind.trigger => value(s) > 0.1,
    PartKind.axis => value(s).abs() > 0.5,
    PartKind.stick => value(s) > deadzone,
  };
}

/// Colours a drawing uses.
class PadPalette {
  const PadPalette({
    required this.lit,
    required this.checked,
    required this.ink,
    required this.background,
    this.variant = '',
    this.fontFamily,
  });

  /// The app's font, for labels drawn on the controller.
  final String? fontFamily;

  /// The controller's colour where it came in more than one ('white',
  /// 'black').
  final String variant;

  /// A part being pressed right now.
  final Color lit;

  /// The mark on a part that has been tested.
  final Color checked;

  /// Labels on the page around the controller.
  final Color ink;
  final Color background;
}

/// A drawing of one kind of controller, and the parts it tests. New
/// controllers (DualShock 3, DualSense, N64, Saturn...) are a subclass
/// each, added to [layouts].
abstract class ControllerLayout {
  const ControllerLayout();

  /// Stable id ("wii_u_pro").
  String get id;

  /// "Wii U Pro Controller".
  String get title;

  /// Whether this drawing is for [info].
  bool matches(ControllerInfo info);

  /// The parts of [info] this drawing tests.
  List<LayoutPart> parts(ControllerInfo info);

  /// The drawing's own size (it's scaled to fit, keeping this shape).
  Size designSize(ControllerInfo info);

  /// Paints the controller at [designSize] (the canvas is already scaled).
  void paint(
    Canvas canvas,
    ControllerInfo info,
    PadState state,
    TestSession session,
    PadPalette palette,
  );
}

/// Every drawing, most specific first; the last ones take anything.
final List<ControllerLayout> layouts = [
  const WiiUProLayout(),
  const StandardPadLayout(),
  const RawLayout(),
];

ControllerLayout layoutFor(ControllerInfo info) =>
    layouts.firstWhere((l) => l.matches(info));

/// Helper for [WiiUProLayout.matches] and friends.
bool mappedWiiUPro(ControllerInfo i) => i.isGamepad && isWiiUPro(i);
