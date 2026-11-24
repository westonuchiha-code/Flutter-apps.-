import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:light_capture/light_capture.dart';
import 'package:video_kit/video_kit.dart';

/// Something that produces frames: a camera or the test card.
class SourceOption {
  const SourceOption(this.label, this.kind, [this.data]);
  final String label;
  final String kind; // 'android', 'desktop', 'test'
  final Object? data;
}

/// Delivers upright colour frames about 320 pixels wide.
class FrameSource {
  StreamSubscription<Object?>? _sub;
  CameraController? _android;
  Timer? _testTimer;
  bool _busy = false;
  final _watch = Stopwatch()..start();

  Future<List<SourceOption>> list() async {
    final out = <SourceOption>[];
    try {
      if (Platform.isAndroid) {
        for (final c in await availableCameras()) {
          out.add(
            SourceOption(
              switch (c.lensDirection) {
                CameraLensDirection.front => 'Front camera',
                CameraLensDirection.back => 'Back camera',
                CameraLensDirection.external => 'External camera',
              },
              'android',
              c,
            ),
          );
        }
        // Back camera first: Chip Cam films the world.
        out.sort(
          (a, b) => a.label == 'Back camera'
              ? -1
              : (b.label == 'Back camera' ? 1 : 0),
        );
      } else if (LightCapture.isSupported) {
        for (final c in await LightCapture.listCameras()) {
          out.add(SourceOption(c.name, 'desktop', c));
        }
      }
    } catch (_) {
      // No cameras: the test card still works.
    }
    out.add(const SourceOption('Test card', 'test'));
    return out;
  }

  Future<void> start(
    SourceOption o,
    void Function(VideoFrame f) onFrame,
    void Function(String e) onError,
  ) async {
    await stop();
    switch (o.kind) {
      case 'android':
        final desc = o.data! as CameraDescription;
        final c = CameraController(
          desc,
          ResolutionPreset.low,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        _android = c;
        try {
          await c.initialize();
        } on CameraException catch (e) {
          _android = null;
          await c.dispose();
          throw Exception(
            e.code.startsWith('CameraAccess')
                ? 'Camera permission was denied. Allow camera access for Chip Cam in Android Settings > Apps.'
                : 'Could not open the camera: ${e.description ?? e.code}',
          );
        }
        final turns = desc.sensorOrientation ~/ 90;
        final front = desc.lensDirection == CameraLensDirection.front;
        await c.startImageStream((img) {
          if (_busy || img.planes.length < 3) return;
          _busy = true;
          try {
            final step = img.width > 480 ? 2 : 1;
            var f = yuv420ToFrame(
              width: img.width,
              height: img.height,
              y: img.planes[0].bytes,
              u: img.planes[1].bytes,
              v: img.planes[2].bytes,
              yRowStride: img.planes[0].bytesPerRow,
              uvRowStride: img.planes[1].bytesPerRow,
              uvPixelStride: img.planes[1].bytesPerPixel ?? 1,
              step: step,
            ).rotated(turns);
            if (front) f = f.mirrored();
            onFrame(f);
          } catch (e) {
            onError('Camera frame error: $e');
          } finally {
            _busy = false;
          }
        });
      case 'desktop':
        _sub = LightCapture.frames.listen(
          (frame) => onFrame(
            frame.isColor
                ? VideoFrame.fromBgra(frame.pixels, frame.width, frame.height)
                : VideoFrame.fromLuma(frame.pixels, frame.width, frame.height),
          ),
          onError: (Object e) => onError('$e'),
        );
        await LightCapture.start(
          o.data! as LightCaptureCamera,
          color: true,
          width: 320,
        );
      default:
        _testTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
          onFrame(testCard(_watch.elapsedMilliseconds / 1000));
        });
    }
  }

  Future<void> stop() async {
    _testTimer?.cancel();
    _testTimer = null;
    await _sub?.cancel();
    _sub = null;
    if (Platform.isWindows || Platform.isLinux) {
      try {
        await LightCapture.stop();
      } catch (_) {}
    }
    final c = _android;
    _android = null;
    if (c != null) {
      if (c.value.isStreamingImages) await c.stopImageStream();
      await c.dispose();
    }
  }
}
