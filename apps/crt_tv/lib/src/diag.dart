import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';

/// Troubleshooting notes for machines nobody can attach a debugger to (a
/// games console, say). Off unless the launcher sets CRT_TV_DIAG=1; the
/// notes go to standard output, which the launcher keeps in its log.
final bool diagOn = Platform.environment['CRT_TV_DIAG'] == '1';

void diag(String message) {
  // ignore: avoid_print
  if (diagOn) print('CRT_TV_DIAG $message');
}

/// Every ten seconds, notes how many frames were drawn and how long they
/// took: "build" is this program working out what to draw, "raster" is the
/// graphics card drawing it. A 60 Hz screen leaves 16.7 ms for both.
void startFrameReport() {
  if (!diagOn) return;
  var frames = 0;
  var buildTotal = 0, buildWorst = 0, rasterTotal = 0, rasterWorst = 0, slow = 0;
  var since = DateTime.now();
  WidgetsBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds;
      final raster = t.rasterDuration.inMicroseconds;
      frames++;
      buildTotal += build;
      rasterTotal += raster;
      if (build > buildWorst) buildWorst = build;
      if (raster > rasterWorst) rasterWorst = raster;
      if (t.totalSpan.inMicroseconds > 17000) slow++;
    }
  });
  // Only frames where the interface itself changed are counted here; a
  // video playing under a still interface adds none (see "video:" lines).
  Timer.periodic(const Duration(seconds: 10), (_) {
    final now = DateTime.now();
    final seconds = now.difference(since).inMilliseconds / 1000;
    since = now;
    if (frames == 0) {
      diag('interface frames: none in the last ${seconds.toStringAsFixed(0)}s (nothing on screen changed)');
      return;
    }
    String ms(num micros) => (micros / 1000).toStringAsFixed(1);
    diag('interface frames: $frames in ${seconds.toStringAsFixed(0)}s; '
        'build avg ${ms(buildTotal / frames)} worst ${ms(buildWorst)} ms; '
        'raster avg ${ms(rasterTotal / frames)} worst ${ms(rasterWorst)} ms; '
        '$slow took longer than one screen refresh');
    frames = 0;
    buildTotal = buildWorst = rasterTotal = rasterWorst = slow = 0;
  });
}
