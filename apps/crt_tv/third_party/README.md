# third_party

## media_kit_video

A copy of `media_kit_video` 2.0.1 from pub.dev (MIT licence, see its
LICENSE), used through `dependency_overrides` in `pubspec.yaml`, with three
changes to its Linux code. Each is marked in the source with
`CRT TV change`. The `example/` folder was left out.

1. **No waiting inside the player when drawing a frame**
   (`MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME` = 0, in `texture_gl.cc` and
   `video_output.cc`). mpv hands frames over up to 50 ms early and by
   default makes the drawing call wait until the frame is due. That call
   runs on Flutter's drawing thread (hardware) or the GTK main thread
   (software), so every video frame froze the whole interface for up to
   50 ms and the picture topped out near 20 frames a second.
   `CRT_TV_VIDEO_BLOCK=1` restores the old behaviour.

2. **`glFinish` instead of `glFlush` after mpv draws** (`texture_gl.cc`).
   The frame is drawn in mpv's own context and read by Flutter's through an
   EGLImage. With only a flush, Flutter could read it half-drawn: strips of
   two frames on screen.

3. **Software video is copied under the lock** (`texture_sw.cc`). Flutter
   was handed the player's own buffer, which the player could be redrawing
   while Flutter read it: the same strips of two frames.

Plus troubleshooting counters (`CRT_TV_DIAG=1`): every ten seconds,
`CRT_TV_DIAG video frames: N offered by the player, M drawn ...`.

To update to a newer media_kit_video: copy the new version here and reapply
the changes above (search for `CRT TV change`).
