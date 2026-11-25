import 'package:vector_math/vector_math_64.dart';

import 'mesh.dart';

/// Something in the world: a transform, maybe a mesh, and children.
class Node {
  Node({
    this.name = '',
    this.mesh,
    this.material,
    Vector3? position,
    Quaternion? rotation,
    Vector3? scale,
    List<Node>? children,
    this.visible = true,
    this.layer = 0,
  }) : position = position ?? Vector3.zero(),
       rotation = rotation ?? Quaternion.identity(),
       scale = scale ?? Vector3.all(1),
       children = children ?? [];

  String name;
  Mesh? mesh;
  Surface? material;
  Vector3 position;
  Quaternion rotation;
  Vector3 scale;
  final List<Node> children;
  bool visible;

  /// Draw order group: lower layers are drawn first, whatever their
  /// distance. Put floors and terrain on -1 so things standing on them are
  /// never covered (the PS1's ordering table had the same trick).
  int layer;

  /// Mesh materials by triangle range, for models with several (glTF).
  List<(int start, int count, Surface material)>? parts;

  Matrix4 get local => Matrix4.compose(position, rotation, scale);

  Node add(Node child) {
    children.add(child);
    return child;
  }

  /// Calls [f] for this node and every descendant with its world matrix.
  void visit(Matrix4 parent, void Function(Node n, Matrix4 world) f) {
    if (!visible) return;
    final world = parent * local;
    f(this, world);
    for (final c in children) {
      c.visit(world, f);
    }
  }

  /// Turns around the Y axis by [radians].
  void spinY(double radians) =>
      rotation = Quaternion.axisAngle(Vector3(0, 1, 0), radians) * rotation;
}

/// A light that fades with distance.
class PointLight {
  PointLight({
    required this.position,
    this.color = 0xFFFFE0B0,
    this.range = 6,
    this.intensity = 1,
  });
  Vector3 position;
  int color;
  double range;
  double intensity;
}

/// Everything to draw, and how it is lit.
class Scene {
  Scene({
    Node? root,
    this.sky = 0xFF2A3550,
    this.skyHorizon,
    this.ambient = 0xFF505868,
    Vector3? sunDirection,
    this.sunColor = 0xFFE8E0D0,
    this.fogColor = 0xFF2A3550,
    this.fogNear = 12,
    this.fogFar = 40,
    List<PointLight>? lights,
  }) : root = root ?? Node(name: 'root'),
       sunDirection = (sunDirection ?? Vector3(-0.4, -1, -0.3))..normalize(),
       lights = lights ?? [];

  final Node root;
  int sky, ambient;

  /// If set, the sky fades from [sky] overhead to this at the horizon.
  int? skyHorizon;

  /// Direction the sunlight travels.
  Vector3 sunDirection;
  int sunColor;
  int fogColor;

  /// Fog starts at [fogNear] and hides everything by [fogFar].
  double fogNear, fogFar;
  final List<PointLight> lights;
}
