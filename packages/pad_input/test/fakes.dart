import 'package:pad_input/pad_input.dart';

/// A controller source with no hardware: tests set what is held.
class FakeSource implements PadSource {
  FakeSource({this.available = true, this.kind = PadKind.xbox});

  /// Whether [open] succeeds (a library could be loaded).
  final bool available;

  /// The kind of pad that holds [held].
  PadKind kind;
  Set<PadButton> held = {};
  int sony = 0, others = 0;
  bool opened = false, closed = false;
  int rescans = 0;

  @override
  bool open() => opened = available;

  @override
  PadKind? read(bool rescan, Set<PadButton> pressed) {
    if (rescan) rescans++;
    if (held.isEmpty) return null;
    pressed.addAll(held);
    return kind;
  }

  @override
  ({int sony, int others}) count() => (sony: sony, others: others);

  @override
  void close() => closed = true;
}

/// A clock that tests move by hand.
class FakeClock {
  DateTime now = DateTime(2026);

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}
