import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import '../flyover.dart';

import 'package:landscape/landscape.dart';

import '../raytrace.dart';

Uint8List _png((Uint32List, int, int) a) {
  final (px, w, h) = a;
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    final c = px[p.y * w + p.x];
    p
      ..r = (c >> 16) & 255
      ..g = (c >> 8) & 255
      ..b = c & 255;
  }
  return img.encodePng(image);
}

/// Ray traces a still, sharper pass by pass, then saves or shares it.
class StillPage extends StatefulWidget {
  const StillPage({
    super.key,
    required this.settings,
    required this.field,
    required this.shot,
    required this.width,
    required this.height,
    required this.name,
  });

  final LandSettings settings;
  final HeightField field;
  final Shot shot;
  final int width, height;
  final String name;

  @override
  State<StillPage> createState() => _StillPageState();
}

class _StillPageState extends State<StillPage> {
  late final Uint32List _px = Uint32List(widget.width * widget.height);
  ui.Image? _image;
  double _progress = 0;
  bool _done = false, _stopped = false;
  final _watch = Stopwatch();

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _stopped = true;
    _image?.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    _watch.start();
    final job = TraceJob(
      widget.settings,
      widget.field,
      widget.shot,
      widget.width,
      widget.height,
    );
    final n = traceWorkers;
    const steps = [8, 4, 2, 1];
    for (var p = 0; p < steps.length; p++) {
      final step = steps[p];
      final parts = await Future.wait([
        for (var k = 0; k < n; k++)
          runInBackground(tracePass, (job, k, n, step)),
      ]);
      if (_stopped) {
        return;
      }
      for (var k = 0; k < n; k++) {
        placePass(_px, widget.width, widget.height, parts[k], k, n, step);
      }
      await _show();
      // Each pass has 4× the pixels of the one before.
      setState(() => _progress = [1, 5, 21, 85][p] / 85);
    }
    _watch.stop();
    if (mounted) {
      setState(() => _done = true);
    }
  }

  Future<void> _show() async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _px.buffer.asUint8List(),
      widget.width,
      widget.height,
      ui.PixelFormat.bgra8888,
      c.complete,
    );
    final image = await c.future;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }

  Future<void> _save(bool locker) async {
    final shell = Shell.of(context);
    final png = await runInBackground(_png, (_px, widget.width, widget.height));
    try {
      if (locker) {
        if (!shell.locker.ready && !await shell.locker.connect()) {
          return;
        }
        await shell.locker.save(
          type: AssetType.picture,
          name: widget.name,
          bytes: png,
          extension: 'png',
          tags: const ['vista'],
          extra: {'landscape': widget.settings.toJson()},
        );
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Saved to Pictures')));
        }
      } else {
        await shell.exporter.exportFile(
          'vista.png',
          png,
          mimeType: 'image/png',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(
        _done
            ? 'Done in ${(_watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s'
            : 'Rendering… ${(_progress * 100).round()}%',
      ),
      actions: [
        if (_done) ...[
          IconButton(
            tooltip: 'Save to Asset Locker',
            icon: const Icon(Icons.save_alt),
            onPressed: () => _save(true),
          ),
          IconButton(
            tooltip: 'Export / share',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _save(false),
          ),
        ],
      ],
      bottom: _done
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearProgressIndicator(value: _progress),
            ),
    ),
    body: Center(
      child: _image == null
          ? const Text(
              'Tracing light…',
              style: TextStyle(color: Colors.white70),
            )
          : InteractiveViewer(
              maxScale: 6,
              child: RawImage(
                image: _image,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
    ),
  );
}
