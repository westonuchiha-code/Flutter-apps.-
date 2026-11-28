import 'controls.dart';

/// Where controllers come from: SDL3 (Windows, Linux), Android's input
/// devices, or plain key events (the fallback when neither is there).
abstract class PadBackend {
  /// Shown in the status line ("SDL 3.4.20", "Android input").
  String get title;

  /// Why this backend isn't working (null when it is).
  String? get problem;

  /// Extra lines about how it's set up (SDL hints, drivers).
  List<String> get details => const [];

  /// Starts it; false (and [problem] says why) when it can't run here.
  bool start();

  /// Reads the controllers (called about 60 times a second). True when
  /// the list of controllers (or what one of them is) changed.
  bool poll();

  List<PadDevice> get devices;

  bool get canRumble => false;

  /// A short rumble on [id]; false if it has none.
  bool rumble(int id, {double low = 0.6, double high = 0.6, int ms = 400}) =>
      false;

  void dispose();
}
