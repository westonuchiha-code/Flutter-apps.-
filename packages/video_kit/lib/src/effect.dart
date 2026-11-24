import 'frame.dart';

/// One adjustable setting of an effect.
class Knob {
  const Knob(
    this.id,
    this.label, {
    this.min = 0,
    this.max = 1,
    this.value = 0.5,
    this.choices,
  });

  final String id, label;
  final double min, max, value;

  /// Discrete options; the value is the index.
  final List<String>? choices;
}

/// A piece of old video hardware or a signal process, applied to live frames.
abstract class VideoEffect {
  /// Stable id (saved in settings).
  String get id;
  String get name;

  /// What real thing it reproduces.
  String get about;

  /// The machine's own resolution for a camera of [inW]×[inH]: the input is
  /// resized to this before [process].
  (int, int) inputSize(int inW, int inH);

  List<Knob> get knobs => const [];

  /// Current knob values (defaults until changed).
  late final Map<String, double> values = {
    for (final k in knobs) k.id: k.value,
  };

  double knob(String id) =>
      values[id] ?? knobs.firstWhere((k) => k.id == id).value;

  /// Turns one input frame (already at [inputSize]) into the output picture.
  /// [time] is seconds since the effect started (for animated faults).
  VideoFrame process(VideoFrame input, double time);

  /// Forgets remembered frames (feedback, datamosh, ...).
  void reset() {}
}

/// Keeps the camera's aspect ratio at a given width.
(int, int) byWidth(int inW, int inH, int width) =>
    (width, (width * inH / inW).round().clamp(1, 4096));
