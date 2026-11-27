/// Controller buttons by position, so they mean the same on every brand:
/// [south] is ✕ on PlayStation and A on Xbox, [east] is ○ / B, [west] is
/// □ / X and [north] is △ / Y.
enum PadButton {
  up,
  down,
  left,
  right,
  south,
  east,
  west,
  north,
  l1,
  r1,
  l2,
  r2,
  select,
  start,
  l3,
  r3;

  /// One of the four d-pad / stick directions (these repeat while held).
  bool get isDirection =>
      this == up || this == down || this == left || this == right;
}

/// Which symbols are printed on the controller in use.
enum PadKind { playstation, xbox }

/// The kind of controller to show symbols for, going only by what's plugged
/// in. Null when that doesn't settle it (nothing, or both kinds at once).
PadKind? kindFromConnected({required int sony, required int others}) {
  if (sony > 0 && others == 0) return PadKind.playstation;
  if (sony == 0 && others > 0) return PadKind.xbox;
  return null;
}

/// What's printed on [button] on that kind of controller.
String padLabel(PadButton button, PadKind kind) {
  final ps = kind == PadKind.playstation;
  return switch (button) {
    PadButton.up => 'D-pad ↑',
    PadButton.down => 'D-pad ↓',
    PadButton.left => 'D-pad ←',
    PadButton.right => 'D-pad →',
    PadButton.south => ps ? '✕' : 'A',
    PadButton.east => ps ? '○' : 'B',
    PadButton.west => ps ? '□' : 'X',
    PadButton.north => ps ? '△' : 'Y',
    PadButton.l1 => ps ? 'L1' : 'LB',
    PadButton.r1 => ps ? 'R1' : 'RB',
    PadButton.l2 => ps ? 'L2' : 'LT',
    PadButton.r2 => ps ? 'R2' : 'RT',
    PadButton.select => ps ? 'Share' : 'Back',
    PadButton.start => ps ? 'Options' : 'Start',
    PadButton.l3 => ps ? 'L3' : 'LS',
    PadButton.r3 => ps ? 'R3' : 'RS',
  };
}
