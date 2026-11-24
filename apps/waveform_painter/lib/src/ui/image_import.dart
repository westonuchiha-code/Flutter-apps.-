import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../shape.dart';

/// A decoded picture, kept small.
class Picture {
  const Picture(this.image, this.rgba, this.width, this.height);
  final ui.Image image;
  final Uint8List rgba;
  final int width, height;

  static Future<Picture> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Picture(img, data!.buffer.asUint8List(), img.width, img.height);
  }
}

const _imageExts = ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'];

/// Lets the user pick a picture and turns it into a wave.
Future<Float32List?> importWaveFromImage(BuildContext context) async {
  final shell = Shell.of(context);
  final source = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Picture from this device'),
            onTap: () => Navigator.pop(context, 'file'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_shared_outlined),
            title: const Text('Picture from the Asset Locker'),
            onTap: () => Navigator.pop(context, 'locker'),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  Uint8List? bytes;
  if (source == 'file') {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Pictures',
          extensions: _imageExts,
          mimeTypes: ['image/*'],
        ),
      ],
    );
    bytes = await file?.readAsBytes();
  } else {
    final locker = shell.locker;
    if (!locker.ready && !await locker.connect()) return null;
    if (!context.mounted) return null;
    final info = await pickFromLocker(context, locker);
    if (info == null) return null;
    if (!_imageExts.contains(info.extension)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${info.name}" is not a picture.')),
        );
      }
      return null;
    }
    bytes = await locker.read(info);
  }
  if (bytes == null || !context.mounted) return null;
  final Picture pic;
  try {
    pic = await Picture.decode(bytes);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That picture could not be opened.')),
      );
    }
    return null;
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<Float32List>(
    MaterialPageRoute(builder: (_) => ImageToWavePage(picture: pic)),
  );
}

enum _Mode { row, outline }

class ImageToWavePage extends StatefulWidget {
  const ImageToWavePage({super.key, required this.picture});

  final Picture picture;

  @override
  State<ImageToWavePage> createState() => _ImageToWavePageState();
}

class _ImageToWavePageState extends State<ImageToWavePage> {
  _Mode _mode = _Mode.row;
  double _row = 0.5;
  double _threshold = 0.18;

  Float32List get _wave {
    final p = widget.picture;
    final w = _mode == _Mode.row
        ? waveFromRow(p.rgba, p.width, p.height, _row)
        : waveFromOutline(p.rgba, p.width, p.height, threshold: _threshold);
    return normalize(w);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.picture;
    final scheme = Theme.of(context).colorScheme;
    final wave = _wave;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wave from picture'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, wave),
            child: const Text('Use'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(
                value: _Mode.row,
                label: Text('Brightness of a row'),
              ),
              ButtonSegment(value: _Mode.outline, label: Text('Outline')),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: p.width / p.height,
            child: CustomPaint(
              foregroundPainter: _mode == _Mode.row
                  ? _RowLine(_row, scheme.primary)
                  : null,
              child: RawImage(image: p.image, fit: BoxFit.fill),
            ),
          ),
          if (_mode == _Mode.row) ...[
            const Text('Row'),
            Slider(value: _row, onChanged: (v) => setState(() => _row = v)),
          ] else ...[
            const Text('Sensitivity'),
            Slider(
              value: _threshold,
              min: 0.03,
              max: 0.6,
              onChanged: (v) => setState(() => _threshold = v),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(height: 120, child: WavePreview(wave: wave)),
        ],
      ),
    );
  }
}

class _RowLine extends CustomPainter {
  _RowLine(this.row, this.color);
  final double row;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = row * size.height;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_RowLine old) => old.row != row;
}

/// Small read-only wave drawing.
class WavePreview extends StatelessWidget {
  const WavePreview({super.key, required this.wave});
  final Float32List wave;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PreviewPainter(wave, Theme.of(context).colorScheme),
    size: Size.infinite,
  );
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.wave, this.scheme);
  final Float32List wave;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = scheme.surfaceContainer,
    );
    final path = Path();
    for (var i = 0; i < wave.length; i++) {
      final x = (i + 0.5) / wave.length * size.width;
      final y = (1 - wave[i]) / 2 * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = scheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
