# light_capture

Live webcam frames for Flutter on **Windows** and **Linux**: small
**brightness** thumbnails (default) or **colour** frames (`color: true`).

Flutter's official `camera` plugin cannot stream frames on Windows, so this
plugin captures natively (Media Foundation on Windows, V4L2 on Linux), shrinks
each frame to a 160-pixel-wide 8-bit luminance thumbnail and streams it to Dart.
Android apps should use the `camera` plugin's `startImageStream` instead.

```dart
final sub = LightCapture.frames.listen((frame) { /* frame.pixels */ });
final cameras = await LightCapture.listCameras();
await LightCapture.start(cameras.first);            // brightness, 160 wide
// await LightCapture.start(cam, color: true, width: 320); // BGRA colour
await LightCapture.setAutoExposure(false); // lock exposure
...
await LightCapture.stop();
```

Native code shared by both platforms is in `common/luma_downscale.h`
(test: `c++ -std=c++17 -I common test_native/luma_downscale_test.cc && ./a.out`).
