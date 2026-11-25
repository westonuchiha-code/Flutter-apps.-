import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';

const red = 0xFFFF0000, blue = 0xFF0000FF, sky = 0xFF000000;

/// Renders [scene] from [camera] at w×h and returns RGBA bytes.
Future<(Uint8List, int, int)> shot(
  Scene scene,
  Camera camera, {
  RenderOptions o = const RenderOptions(lowRes: 0, wobble: false, fog: false),
  int w = 64,
  int h = 48,
}) async {
  final r = Renderer();
  final rec = ui.PictureRecorder();
  r.paint(
    ui.Canvas(rec),
    ui.Size(w.toDouble(), h.toDouble()),
    scene,
    camera,
    o,
  );
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData();
  return (data!.buffer.asUint8List(), w, h);
}

int px((Uint8List, int, int) s, int x, int y) {
  final (b, w, _) = s;
  final o = (y * w + x) * 4;
  return 0xFF000000 | (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
}

Scene flatScene(List<Node> nodes) {
  final s = Scene(sky: sky, ambient: 0xFFFFFFFF, sunColor: 0xFF000000);
  for (final n in nodes) {
    s.root.add(n);
  }
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  animationTests();

  test('camera looks down -Z by default and turns with yaw', () {
    final c = Camera(position: Vector3.zero());
    expect(c.forward.z, closeTo(-1, 1e-9));
    c.yaw = 1.5707963;
    expect(c.forward.x, closeTo(-1, 1e-6));
    final v = Vector3(0, 0, -5);
    Camera(position: Vector3(0, 0, 0)).view.transform3(v);
    expect(v.z, -5);
  });

  test(
    'a box in front shows its front face; behind the camera nothing',
    () async {
      final box = Node(
        mesh: boxMesh(2, 2, 2),
        material: Surface(color: red),
        position: Vector3(0, 0, -5),
      );
      final s = await shot(flatScene([box]), Camera(position: Vector3.zero()));
      expect(px(s, 32, 24), red);
      expect(px(s, 1, 1), sky);
      final behind = await shot(
        flatScene([box]),
        Camera(position: Vector3.zero(), yaw: 3.14159),
      );
      expect(px(behind, 32, 24), sky);
    },
  );

  test('back faces are culled unless double-sided', () async {
    // A plane facing up, seen from below.
    Node plane(bool two) => Node(
      mesh: planeMesh(4, 4, split: 2),
      material: Surface(color: red, doubleSided: two),
      position: Vector3(0, 1, -4),
    );
    final cam = Camera(position: Vector3.zero(), pitch: 0.4);
    expect(px(await shot(flatScene([plane(false)]), cam), 32, 24), sky);
    expect(px(await shot(flatScene([plane(true)]), cam), 32, 24), red);
  });

  test('near things cover far things (sorted far to near)', () async {
    final far = Node(
      mesh: boxMesh(4, 4, 1),
      material: Surface(color: blue),
      position: Vector3(0, 0, -10),
    );
    final near = Node(
      mesh: boxMesh(1, 1, 1),
      material: Surface(color: red),
      position: Vector3(0, 0, -4),
    );
    final s = await shot(
      flatScene([near, far]),
      Camera(position: Vector3.zero()),
    );
    expect(px(s, 32, 24), red);
    expect(px(s, 32 + 6, 24), blue);
  });

  test('depth bias puts worn things over the surface they sit on', () async {
    Future<int> centre(double redBias, double blueBias) async {
      // Two boxes in the same place: only the bias decides.
      final r = Node(
        mesh: boxMesh(1, 1, 0.1),
        material: Surface(color: red),
        position: Vector3(0, 0, -4),
        depthBias: redBias,
      );
      final b = Node(
        mesh: boxMesh(1, 1, 0.1),
        material: Surface(color: blue),
        position: Vector3(0, 0, -4),
        depthBias: blueBias,
      );
      return px(
        await shot(flatScene([r, b]), Camera(position: Vector3.zero())),
        32,
        24,
      );
    }

    expect(await centre(0.05, 0), red);
    expect(await centre(0, 0.05), blue);
    // A small bias never pulls something through a much nearer surface.
    final behind = Node(
      mesh: boxMesh(0.5, 0.5, 0.1),
      material: Surface(color: red),
      position: Vector3(0, 0, -6),
      depthBias: 0.05,
    );
    final front = Node(
      mesh: boxMesh(2, 2, 0.1),
      material: Surface(color: blue),
      position: Vector3(0, 0, -4),
    );
    expect(
      px(
        await shot(
          flatScene([behind, front]),
          Camera(position: Vector3.zero()),
        ),
        32,
        24,
      ),
      blue,
    );
  });

  test('triangles crossing the near plane are clipped, not dropped', () async {
    // A long floor running under and behind the camera.
    final floor = Node(
      mesh: planeMesh(4, 40, split: 1),
      material: Surface(color: red, doubleSided: true),
      position: Vector3(0, -1, 0),
    );
    final s = await shot(flatScene([floor]), Camera(position: Vector3.zero()));
    expect(px(s, 32, 46), red); // bottom of the picture: floor right under us
  });

  test('fog fades distant things to the fog colour', () async {
    final scene =
        flatScene([
            Node(
              mesh: boxMesh(20, 20, 1),
              material: Surface(color: red),
              position: Vector3(0, 0, -30),
            ),
          ])
          ..fogColor = 0xFF00FF00
          ..fogNear = 5
          ..fogFar = 25;
    final s = await shot(
      scene,
      Camera(position: Vector3.zero()),
      o: const RenderOptions(lowRes: 0, wobble: false),
    );
    expect(px(s, 32, 24), 0xFF00FF00);
  });

  test('PS1 mode renders at low resolution', () async {
    final r = Renderer();
    final rec = ui.PictureRecorder();
    r.paint(
      ui.Canvas(rec),
      const ui.Size(640, 480),
      flatScene([Node(mesh: boxMesh(1, 1, 1), position: Vector3(0, 0, -3))]),
      Camera(position: Vector3.zero()),
      const RenderOptions(),
    );
    expect(r.stats.height, 240);
    expect(r.stats.width, 320);
    expect(r.stats.drawn, greaterThan(0));
  });

  test('OBJ: faces of any size, negative indices, missing normals', () {
    final n = loadObj(
      'v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nvt 0 0\nf 1/1 2/1 3/1 4/1\nf -4 -2 -1\n',
    );
    final mesh = n.children.single.mesh!;
    expect(mesh.triangleCount, 3);
    expect(mesh.normals[2], closeTo(1, 1e-6)); // faces +z
    final b = boundsOf(fitModel(n, height: 2))!;
    expect(b[1], closeTo(0, 1e-6));
    expect(b[4], closeTo(2, 1e-6));
  });

  test(
    'glTF: a .glb with one triangle, a colour and a node transform',
    () async {
      // Positions (3 × vec3 float) then indices (3 × ushort).
      final bin = ByteData(36 + 8);
      final pts = [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0];
      for (var i = 0; i < 9; i++) {
        bin.setFloat32(i * 4, pts[i], Endian.little);
      }
      for (var i = 0; i < 3; i++) {
        bin.setUint16(36 + i * 2, i, Endian.little);
      }
      final json = utf8.encode(
        jsonEncode({
          'asset': {'version': '2.0'},
          'scene': 0,
          'scenes': [
            {
              'nodes': [0],
            },
          ],
          'nodes': [
            {
              'mesh': 0,
              'translation': [0, 2, 0],
            },
          ],
          'meshes': [
            {
              'primitives': [
                {
                  'attributes': {'POSITION': 0},
                  'indices': 1,
                  'material': 0,
                },
              ],
            },
          ],
          'materials': [
            {
              'pbrMetallicRoughness': {
                'baseColorFactor': [1, 0, 0, 1],
              },
            },
          ],
          'accessors': [
            {
              'bufferView': 0,
              'componentType': 5126,
              'count': 3,
              'type': 'VEC3',
            },
            {
              'bufferView': 1,
              'componentType': 5123,
              'count': 3,
              'type': 'SCALAR',
            },
          ],
          'bufferViews': [
            {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
            {'buffer': 0, 'byteOffset': 36, 'byteLength': 6},
          ],
          'buffers': [
            {'byteLength': 44},
          ],
        }),
      );
      final jsonPad = (4 - json.length % 4) % 4;
      final out = BytesBuilder()
        ..add(ascii.encode('glTF'))
        ..add(_u32(2))
        ..add(_u32(12 + 8 + json.length + jsonPad + 8 + 44))
        ..add(_u32(json.length + jsonPad))
        ..add(_u32(0x4E4F534A))
        ..add(json)
        ..add(List.filled(jsonPad, 0x20))
        ..add(_u32(44))
        ..add(_u32(0x004E4942))
        ..add(bin.buffer.asUint8List());
      final model = await loadGltf(out.toBytes());
      final mesh = model.children.single.children.single;
      expect(mesh.mesh!.triangleCount, 1);
      expect(mesh.material!.color, red);
      expect(mesh.mesh!.normals[2].abs(), closeTo(1, 1e-6)); // computed
      final b = boundsOf(model)!;
      expect(b[1], 2); // translated up
    },
  );

  test('walking slides along walls and follows the ground', () {
    final rig = WalkRig(
      start: Vector3(0, 1.6, 0),
      walls: [const Box(-5, -2, 5, -1)],
      ground: (x, z) => z > 3 ? 1 : 0,
    );
    for (var i = 0; i < 60; i++) {
      rig.move(1, 0, 1 / 30); // straight into the wall for 2 s
    }
    expect(rig.camera.position.z, greaterThan(-1));
    for (var i = 0; i < 90; i++) {
      rig.move(-1, 0, 1 / 30); // back 9 m → onto the step
    }
    for (var i = 0; i < 60; i++) {
      rig.update(1 / 30);
    }
    expect(rig.camera.position.y, closeTo(2.6, 0.05));
  });
}

Uint8List _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

void animationTests() {
  test('clips move nodes, crossfade, and skins follow their joints', () {
    final root = Node(name: 'root');
    final arm = root.add(Node(name: 'arm', position: Vector3(0, 1, 0)));
    final quarter = Quaternion.axisAngle(Vector3(0, 0, 1), 1.5707963);
    final clip = AnimationClip('raise', [
      Channel(
        arm,
        AnimPath.rotation,
        Float32List.fromList([0, 1]),
        Float32List.fromList([
          0,
          0,
          0,
          1,
          quarter.x,
          quarter.y,
          quarter.z,
          quarter.w,
        ]),
      ),
    ], loop: false);
    clip.apply(0.5);
    expect(arm.rotation.radians, closeTo(1.5707963 / 2, 1e-3));
    clip.apply(5);
    expect(arm.rotation.radians, closeTo(1.5707963, 1e-3));
    // Retargeting by name drives another skeleton built the same way.
    final other = Node(name: 'root')..add(Node(name: 'arm'));
    clip.retarget(other.byName()).apply(1);
    expect(other.find('arm')!.rotation.radians, closeTo(1.5707963, 1e-3));
    // Animator crossfades from one clip to another.
    final idle = AnimationClip('idle', [
      Channel(
        arm,
        AnimPath.rotation,
        Float32List.fromList([0]),
        Float32List.fromList([0, 0, 0, 1]),
      ),
    ]);
    final a = Animator({'raise': clip, 'idle': idle})..play('raise');
    a.update(1);
    a.play('idle', fade: 0.5);
    a.update(0.25);
    expect(arm.rotation.radians, inExclusiveRange(0.2, 1.4)); // half way
    a.update(0.5);
    expect(arm.rotation.radians, closeTo(0, 1e-3));

    // A one-vertex "mesh" bound fully to the arm: rotating the arm by 90°
    // about Z moves the vertex from (1, 1, 0) to (0, 2, 0).
    final mesh = Mesh(
      positions: Float32List.fromList([1, 1, 0]),
      normals: Float32List.fromList([1, 0, 0]),
      uvs: Float32List(2),
      indices: Uint32List(0),
    );
    final body = root.add(Node(name: 'body', mesh: mesh));
    body.skin = Skin(
      joints: [arm],
      inverseBind: [Matrix4.translation(Vector3(0, -1, 0))],
      jointIndices: Uint16List.fromList([0, 0, 0, 0]),
      weights: Float32List.fromList([1, 0, 0, 0]),
      mesh: mesh,
    );
    arm.rotation = quarter;
    updateSkins(root);
    expect(mesh.positions[0], closeTo(0, 1e-5));
    expect(mesh.positions[1], closeTo(2, 1e-5));
    expect(mesh.normals[1], closeTo(1, 1e-5));
  });

  test('a tap finds the floor under it', () {
    final c = Camera(position: Vector3(0, 2, 0), pitch: -0.7853981);
    final p = groundPoint(c, 200, 100, 100, 50)!; // centre: 45° down
    expect(p.y, closeTo(0, 1e-9));
    expect(p.z, closeTo(-2, 1e-6));
    expect(
      groundPoint(
        Camera(position: Vector3(0, 2, 0), pitch: 0.5),
        200,
        100,
        100,
        50,
      ),
      isNull,
    );
  });
}
