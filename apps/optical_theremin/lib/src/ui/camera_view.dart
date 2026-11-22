import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../core/luma_image.dart';

/// Shows a [LumaImage] (grayscale camera thumbnail), scaled to fill.
class CameraView extends StatefulWidget {
  const CameraView({super.key, required this.frame});

  final LumaImage? frame;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  ui.Image? _image;
  bool _decoding = false;
  LumaImage? _pending;

  @override
  void initState() {
    super.initState();
    _queue(widget.frame);
  }

  @override
  void didUpdateWidget(CameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.frame, oldWidget.frame)) _queue(widget.frame);
  }

  void _queue(LumaImage? frame) {
    if (frame == null) return;
    _pending = frame;
    if (!_decoding) _decodeNext();
  }

  void _decodeNext() {
    final frame = _pending;
    _pending = null;
    if (frame == null) return;
    _decoding = true;
    final rgba = Uint8List(frame.width * frame.height * 4);
    for (var i = 0, j = 0; i < frame.width * frame.height; i++, j += 4) {
      final v = frame.pixels[i];
      rgba[j] = v;
      rgba[j + 1] = v;
      rgba[j + 2] = v;
      rgba[j + 3] = 255;
    }
    ui.decodeImageFromPixels(
      rgba,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (image) {
        _decoding = false;
        if (!mounted) {
          image.dispose();
          return;
        }
        final old = _image;
        setState(() => _image = image);
        old?.dispose();
        _decodeNext();
      },
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return RawImage(
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }
}
