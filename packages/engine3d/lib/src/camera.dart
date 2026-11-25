import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// Where we look from: position, yaw (left/right), pitch (up/down).
class Camera {
  Camera({
    Vector3? position,
    this.yaw = 0,
    this.pitch = 0,
    this.fov = 60,
    this.near = 0.1,
  }) : position = position ?? Vector3(0, 1.6, 5);

  Vector3 position;

  /// Radians; 0 looks along -Z.
  double yaw, pitch;

  /// Vertical field of view in degrees.
  double fov;
  double near;

  Vector3 get forward => Vector3(
    -math.sin(yaw) * math.cos(pitch),
    math.sin(pitch),
    -math.cos(yaw) * math.cos(pitch),
  );

  /// World → camera (camera looks down -Z).
  Matrix4 get view {
    final m = Matrix4.identity()
      ..rotateX(-pitch)
      ..rotateY(-yaw)
      ..translateByVector3(-position);
    return m;
  }
}

/// Where a tap at [p] on a [width]×[height] view meets the floor
/// (y = [floorY]), or null if the ray points away from it.
Vector3? groundPoint(
  Camera c,
  double width,
  double height,
  double px,
  double py, {
  double floorY = 0,
}) {
  final t = math.tan(c.fov * math.pi / 360);
  final x = (px - width / 2) / (height / 2) * t,
      y = -(py - height / 2) / (height / 2) * t;
  final f = c.forward;
  final right = Vector3(math.cos(c.yaw), 0, -math.sin(c.yaw));
  final up = right.cross(f);
  final d = f + right * x + up * y;
  if (d.y.abs() < 1e-6) return null;
  final k = (floorY - c.position.y) / d.y;
  if (k <= 0) return null;
  return c.position + d * k;
}

/// A box that blocks walking.
class Box {
  const Box(this.minX, this.minZ, this.maxX, this.maxZ, {this.height = 100});
  final double minX, minZ, maxX, maxZ, height;
}

/// Moves a camera from user input.
abstract class CameraRig {
  Camera get camera;

  /// Drag (pixels) to turn.
  void drag(double dx, double dy);

  /// Pinch or wheel: >1 closer.
  void zoom(double factor);

  /// Joystick or keys: forward/back and sideways (-1..1), for [dt] seconds.
  void move(double forward, double strafe, double dt);
  void update(double dt) {}
}

/// Circles a target: drag to orbit, pinch/wheel to zoom.
class OrbitRig extends CameraRig {
  OrbitRig({
    Vector3? target,
    this.distance = 6,
    this.yaw = 0.6,
    this.pitch = -0.35,
    this.autoSpin = 0,
  }) : target = target ?? Vector3(0, 0.8, 0);

  @override
  final camera = Camera();
  Vector3 target;
  double distance, yaw, pitch;

  /// Radians per second to keep turning by itself (0: off).
  double autoSpin;

  @override
  void drag(double dx, double dy) {
    yaw -= dx * 0.008;
    pitch = (pitch - dy * 0.006).clamp(-1.4, 0.3);
  }

  @override
  void zoom(double factor) => distance = (distance / factor).clamp(1.0, 80.0);

  @override
  void move(double forward, double strafe, double dt) {
    final s = distance * dt;
    target +=
        Vector3(-math.sin(yaw), 0, -math.cos(yaw)) * (forward * s) +
        Vector3(math.cos(yaw), 0, -math.sin(yaw)) * (strafe * s);
  }

  @override
  void update(double dt) {
    yaw += autoSpin * dt;
    camera
      ..yaw = yaw
      ..pitch = pitch
      ..position = target - camera.forward * distance;
  }
}

/// Walks on the ground at eye height, sliding along walls.
class WalkRig extends CameraRig {
  WalkRig({
    Vector3? start,
    double yaw = 0,
    this.speed = 3,
    this.eyeHeight = 1.6,
    this.radius = 0.3,
    List<Box>? walls,
    this.ground,
  }) : walls = walls ?? [] {
    camera
      ..position = start ?? Vector3(0, eyeHeight, 5)
      ..yaw = yaw;
  }

  @override
  final camera = Camera();
  double speed, eyeHeight, radius;
  final List<Box> walls;

  /// Ground height at (x, z) (null: flat at 0).
  double Function(double x, double z)? ground;

  @override
  void drag(double dx, double dy) {
    camera
      ..yaw -= dx * 0.006
      ..pitch = (camera.pitch - dy * 0.005).clamp(-1.3, 1.3);
  }

  @override
  void zoom(double factor) =>
      camera.fov = (camera.fov / factor).clamp(30.0, 90.0);

  @override
  void move(double forward, double strafe, double dt) {
    final y = camera.yaw;
    final dx = (-math.sin(y) * forward + math.cos(y) * strafe) * speed * dt;
    final dz = (-math.cos(y) * forward - math.sin(y) * strafe) * speed * dt;
    final p = camera.position;
    // One axis at a time, so walls are slid along rather than stuck to.
    if (!_blocked(p.x + dx, p.z)) {
      p.x += dx;
    }
    if (!_blocked(p.x, p.z + dz)) {
      p.z += dz;
    }
  }

  bool _blocked(double x, double z) {
    final floor = ground?.call(x, z) ?? 0;
    for (final w in walls) {
      if (w.height <= floor + 0.4) {
        continue;
      }
      if (x > w.minX - radius &&
          x < w.maxX + radius &&
          z > w.minZ - radius &&
          z < w.maxZ + radius) {
        return true;
      }
    }
    return false;
  }

  @override
  void update(double dt) {
    final p = camera.position;
    final target = (ground?.call(p.x, p.z) ?? 0) + eyeHeight;
    // Ease onto slopes and steps.
    p.y += (target - p.y) * math.min(1, dt * 12);
  }
}

/// Flies freely: drag to look, move along where you look, never below the
/// ground (plus a margin).
class FlyRig extends CameraRig {
  FlyRig({
    Vector3? start,
    double yaw = 0,
    double pitch = -0.2,
    this.speed = 12,
    this.ground,
    this.clearance = 1.5,
  }) {
    camera
      ..position = start ?? Vector3(0, 20, 60)
      ..yaw = yaw
      ..pitch = pitch;
  }

  @override
  final camera = Camera();
  double speed, clearance;
  double Function(double x, double z)? ground;

  @override
  void drag(double dx, double dy) {
    camera
      ..yaw -= dx * 0.005
      ..pitch = (camera.pitch - dy * 0.004).clamp(-1.4, 1.4);
  }

  @override
  void zoom(double factor) => speed = (speed * factor).clamp(1.0, 200.0);

  @override
  void move(double forward, double strafe, double dt) {
    final f = camera.forward;
    final right = Vector3(math.cos(camera.yaw), 0, -math.sin(camera.yaw));
    camera.position += (f * forward + right * strafe) * (speed * dt);
  }

  @override
  void update(double dt) {
    final p = camera.position;
    final floor = (ground?.call(p.x, p.z) ?? -double.infinity) + clearance;
    if (p.y < floor) p.y = floor;
  }
}
