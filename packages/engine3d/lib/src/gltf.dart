import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math_64.dart';

import 'animation.dart';
import 'mesh.dart';
import 'scene.dart';
import 'textures.dart';

/// Reads a glTF 2.0 model (.glb, or .gltf with embedded data) into nodes:
/// meshes (triangles), base colours and textures, node transforms.
Future<Node> loadGltf(Uint8List bytes, {String name = 'model'}) async =>
    (await loadGltfModel(bytes, name: name)).node;

/// A glTF model with its animations (by name), skins attached.
class GltfModel {
  GltfModel(this.node, this.animations);
  final Node node;
  final Map<String, AnimationClip> animations;
}

/// Like [loadGltf], also reading skins (skinned characters) and animations.
Future<GltfModel> loadGltfModel(
  Uint8List bytes, {
  String name = 'model',
}) async {
  Map<String, Object?> json;
  Uint8List? bin;
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'glTF') {
    final bd = ByteData.sublistView(bytes);
    var o = 12;
    Map<String, Object?>? j;
    while (o + 8 <= bytes.length) {
      final len = bd.getUint32(o, Endian.little),
          type = bd.getUint32(o + 4, Endian.little);
      final chunk = Uint8List.sublistView(bytes, o + 8, o + 8 + len);
      if (type == 0x4E4F534A) {
        j = jsonDecode(utf8.decode(chunk)) as Map<String, Object?>;
      }
      if (type == 0x004E4942) {
        bin = chunk;
      }
      o += 8 + len;
    }
    if (j == null) {
      throw const FormatException('No JSON in this .glb');
    }
    json = j;
  } else {
    json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
  }
  final g = _Gltf(json, bin);
  final node = await g.load(name);
  return GltfModel(node, g.animations());
}

List _list(Object? v) => v is List ? v : const [];
Map _map(Object? v) => v is Map ? v : const {};
int _int(Object? v, [int def = 0]) => v is num ? v.toInt() : def;

class _Gltf {
  _Gltf(this.j, this.bin);
  final Map<String, Object?> j;
  final Uint8List? bin;
  final _buffers = <int, Uint8List>{};
  final _images = <int, ui.Image?>{};
  final _materials = <int, Surface>{};
  final _nodes = <int, Node>{};
  final _skinData = <Node, (List<int>, List<double>)>{};
  final _pendingSkins = <(Node, int)>[];

  Uint8List _buffer(int i) => _buffers[i] ??= () {
    final b = _map(_list(j['buffers'])[i]);
    final uri = b['uri'];
    if (uri == null) {
      if (bin == null) {
        throw const FormatException('Missing binary data');
      }
      return bin!;
    }
    if (uri is String && uri.startsWith('data:')) {
      return base64Decode(uri.substring(uri.indexOf(',') + 1));
    }
    throw const FormatException(
      'This .gltf uses separate files; use a .glb instead',
    );
  }();

  Uint8List _view(int i) {
    final v = _map(_list(j['bufferViews'])[i]);
    final buf = _buffer(_int(v['buffer']));
    final off = _int(v['byteOffset']);
    return Uint8List.sublistView(buf, off, off + _int(v['byteLength']));
  }

  static const _size = {
    'SCALAR': 1,
    'VEC2': 2,
    'VEC3': 3,
    'VEC4': 4,
    'MAT4': 16,
  };

  /// An accessor as numbers (normalised integers become 0..1).
  List<double> _read(int i) {
    final a = _map(_list(j['accessors'])[i]);
    final count = _int(a['count']),
        comps = _size[a['type']] ?? 1,
        type = _int(a['componentType']);
    final out = List<double>.filled(count * comps, 0);
    if (a['bufferView'] == null) {
      return out;
    }
    final viewInfo = _map(_list(j['bufferViews'])[_int(a['bufferView'])]);
    final data = ByteData.sublistView(_view(_int(a['bufferView'])));
    final csize = switch (type) {
      5120 || 5121 => 1,
      5122 || 5123 => 2,
      _ => 4,
    };
    final stride = _int(viewInfo['byteStride'], comps * csize);
    final base = _int(a['byteOffset']);
    final norm = a['normalized'] == true;
    for (var e = 0; e < count; e++) {
      for (var c = 0; c < comps; c++) {
        final o = base + e * stride + c * csize;
        out[e * comps + c] = switch (type) {
          5126 => data.getFloat32(o, Endian.little),
          5125 => data.getUint32(o, Endian.little).toDouble(),
          5123 =>
            norm
                ? data.getUint16(o, Endian.little) / 65535
                : data.getUint16(o, Endian.little).toDouble(),
          5122 =>
            norm
                ? math.max(-1.0, data.getInt16(o, Endian.little) / 32767)
                : data.getInt16(o, Endian.little).toDouble(),
          5121 => norm ? data.getUint8(o) / 255 : data.getUint8(o).toDouble(),
          _ =>
            norm
                ? math.max(-1.0, data.getInt8(o) / 127)
                : data.getInt8(o).toDouble(),
        };
      }
    }
    return out;
  }

  Future<ui.Image?> _image(int i) async {
    if (_images.containsKey(i)) {
      return _images[i];
    }
    final img = _map(_list(j['images'])[i]);
    Uint8List? bytes;
    if (img['bufferView'] != null) {
      bytes = _view(_int(img['bufferView']));
    } else if (img['uri'] is String &&
        (img['uri'] as String).startsWith('data:')) {
      final uri = img['uri'] as String;
      bytes = base64Decode(uri.substring(uri.indexOf(',') + 1));
    }
    ui.Image? out;
    try {
      if (bytes != null) {
        out = await imageFromBytes(Uint8List.fromList(bytes));
      }
    } catch (_) {
      out = null;
    }
    return _images[i] = out;
  }

  Future<Surface> _material(int? i) async {
    if (i == null) {
      return Surface(color: 0xFFCCCCCC);
    }
    if (_materials.containsKey(i)) {
      return _materials[i]!;
    }
    final m = _map(_list(j['materials'])[i]);
    final pbr = _map(m['pbrMetallicRoughness']);
    final f = _list(pbr['baseColorFactor']);
    int c(int k) => ((f.length > k ? (f[k] as num).toDouble() : 1.0) * 255)
        .round()
        .clamp(0, 255);
    final mat = Surface(
      name: (m['name'] as String?) ?? '',
      color: (c(3) << 24) | (c(0) << 16) | (c(1) << 8) | c(2),
      doubleSided: m['doubleSided'] == true,
      lit: !_map(m['extensions']).containsKey('KHR_materials_unlit'),
    );
    final tex = _map(pbr['baseColorTexture']);
    if (tex['index'] != null) {
      final t = _map(_list(j['textures'])[_int(tex['index'])]);
      if (t['source'] != null) {
        mat.texture = await _image(_int(t['source']));
      }
    }
    return _materials[i] = mat;
  }

  Future<Node?> _mesh(int i) async {
    final mesh = _map(_list(j['meshes'])[i]);
    final pos = <double>[], nor = <double>[], uv = <double>[];
    final idx = <int>[];
    final parts = <(int, int, Surface)>[];
    final joints = <int>[], weights = <double>[];
    var skinned = false;
    for (final prim in _list(mesh['primitives'])) {
      final p = _map(prim);
      if (_int(p['mode'], 4) != 4) continue; // triangles only
      final attrs = _map(p['attributes']);
      if (attrs['POSITION'] == null) {
        continue;
      }
      final ps = _read(_int(attrs['POSITION']));
      final n = ps.length ~/ 3;
      if (attrs['JOINTS_0'] != null && attrs['WEIGHTS_0'] != null) {
        final js = _read(_int(attrs['JOINTS_0'])),
            ws = _read(_int(attrs['WEIGHTS_0']));
        if (js.length == n * 4 && ws.length == n * 4) {
          skinned = true;
          joints.addAll(js.map((e) => e.toInt()));
          weights.addAll(ws);
        } else {
          joints.addAll(List.filled(n * 4, 0));
          weights.addAll(List.filled(n * 4, 0.0));
        }
      } else {
        joints.addAll(List.filled(n * 4, 0));
        weights.addAll(List.filled(n * 4, 0.0));
      }
      final ns = attrs['NORMAL'] != null ? _read(_int(attrs['NORMAL'])) : null;
      final ts = attrs['TEXCOORD_0'] != null
          ? _read(_int(attrs['TEXCOORD_0']))
          : null;
      final ids = p['indices'] != null
          ? _read(_int(p['indices'])).map((e) => e.toInt()).toList()
          : List.generate(n, (k) => k);
      final base = pos.length ~/ 3, start = idx.length ~/ 3;
      pos.addAll(ps);
      if (ns != null && ns.length == n * 3) {
        nor.addAll(ns);
      } else {
        // No normals: average the faces around each vertex.
        final acc = List<double>.filled(n * 3, 0);
        for (var t = 0; t + 2 < ids.length; t += 3) {
          final a = ids[t], b = ids[t + 1], c = ids[t + 2];
          final e1 = Vector3(
            ps[b * 3] - ps[a * 3],
            ps[b * 3 + 1] - ps[a * 3 + 1],
            ps[b * 3 + 2] - ps[a * 3 + 2],
          );
          final e2 = Vector3(
            ps[c * 3] - ps[a * 3],
            ps[c * 3 + 1] - ps[a * 3 + 1],
            ps[c * 3 + 2] - ps[a * 3 + 2],
          );
          final fn = e1.cross(e2);
          for (final v in [a, b, c]) {
            acc[v * 3] += fn.x;
            acc[v * 3 + 1] += fn.y;
            acc[v * 3 + 2] += fn.z;
          }
        }
        for (var v = 0; v < n; v++) {
          final l = math.sqrt(
            acc[v * 3] * acc[v * 3] +
                acc[v * 3 + 1] * acc[v * 3 + 1] +
                acc[v * 3 + 2] * acc[v * 3 + 2],
          );
          nor.addAll(
            l == 0
                ? [0, 1, 0]
                : [acc[v * 3] / l, acc[v * 3 + 1] / l, acc[v * 3 + 2] / l],
          );
        }
      }
      uv.addAll(
        ts != null && ts.length == n * 2 ? ts : List.filled(n * 2, 0.0),
      );
      idx.addAll([for (final k in ids) k + base]);
      parts.add((
        start,
        ids.length ~/ 3,
        await _material(p['material'] == null ? null : _int(p['material'])),
      ));
    }
    if (parts.isEmpty) {
      return null;
    }
    final node = Node(
      name: (mesh['name'] as String?) ?? 'mesh',
      mesh: Mesh(
        positions: Float32List.fromList(pos),
        normals: Float32List.fromList(nor),
        uvs: Float32List.fromList(uv),
        indices: Uint32List.fromList(idx),
      ),
      material: parts.first.$3,
    );
    if (parts.length > 1) {
      node.parts = parts;
    }
    if (skinned) {
      _skinData[node] = (joints, weights);
    }
    return node;
  }

  Future<Node> _node(int i, int depth) async {
    final n = _map(_list(j['nodes'])[i]);
    final node = Node(name: (n['name'] as String?) ?? 'node');
    _nodes[i] = node;
    final m = _list(n['matrix']);
    if (m.length == 16) {
      final mat = Matrix4.fromList([for (final v in m) (v as num).toDouble()]);
      mat.decompose(node.position, node.rotation, node.scale);
    } else {
      final t = _list(n['translation']),
          r = _list(n['rotation']),
          s = _list(n['scale']);
      double d(Object? v) => (v as num).toDouble();
      if (t.length == 3) {
        node.position = Vector3(d(t[0]), d(t[1]), d(t[2]));
      }
      if (r.length == 4) {
        node.rotation = Quaternion(d(r[0]), d(r[1]), d(r[2]), d(r[3]));
      }
      if (s.length == 3) {
        node.scale = Vector3(d(s[0]), d(s[1]), d(s[2]));
      }
    }
    if (n['mesh'] != null) {
      final mesh = await _mesh(_int(n['mesh']));
      if (mesh != null) {
        node.add(mesh);
        if (n['skin'] != null && _skinData.containsKey(mesh)) {
          _pendingSkins.add((mesh, _int(n['skin'])));
        }
      }
    }
    if (depth < 64) {
      for (final c in _list(n['children'])) {
        node.add(await _node(_int(c), depth + 1));
      }
    }
    return node;
  }

  Future<Node> load(String name) async {
    final root = Node(name: name);
    final scenes = _list(j['scenes']);
    final List roots;
    if (scenes.isNotEmpty) {
      roots = _list(_map(scenes[_int(j['scene'])])['nodes']);
    } else {
      // No scene list: every node that is nobody's child.
      final nodes = _list(j['nodes']);
      final children = {
        for (final n in nodes)
          ..._list(_map(n)['children']).map((e) => _int(e)),
      };
      roots = [
        for (var k = 0; k < nodes.length; k++)
          if (!children.contains(k)) k,
      ];
    }
    for (final r in roots) {
      root.add(await _node(_int(r), 0));
    }
    for (final (meshNode, k) in _pendingSkins) {
      final skin = _map(_list(j['skins'])[k]);
      final jointNodes = [
        for (final ji in _list(skin['joints']))
          _nodes[_int(ji)] ?? Node(name: 'missing'),
      ];
      final ibm = skin['inverseBindMatrices'] != null
          ? _read(_int(skin['inverseBindMatrices']))
          : null;
      final inverse = [
        for (var b = 0; b < jointNodes.length; b++)
          ibm != null && ibm.length >= (b + 1) * 16
              ? Matrix4.fromList(ibm.sublist(b * 16, b * 16 + 16))
              : Matrix4.identity(),
      ];
      final (js, ws) = _skinData[meshNode]!;
      meshNode.skin = Skin(
        joints: jointNodes,
        inverseBind: inverse,
        jointIndices: Uint16List.fromList([
          for (final x in js) x.clamp(0, math.max(0, jointNodes.length - 1)),
        ]),
        weights: Float32List.fromList(ws),
        mesh: meshNode.mesh!,
      );
    }
    return root;
  }

  /// The model's animations (call after [load]).
  Map<String, AnimationClip> animations() {
    final out = <String, AnimationClip>{};
    final anims = _list(j['animations']);
    for (var a = 0; a < anims.length; a++) {
      final anim = _map(anims[a]);
      final samplers = _list(anim['samplers']);
      final channels = <Channel>[];
      for (final ch in _list(anim['channels'])) {
        final c = _map(ch), target = _map(c['target']);
        final node = _nodes[_int(target['node'], -1)];
        final path = switch (target['path']) {
          'translation' => AnimPath.translation,
          'rotation' => AnimPath.rotation,
          'scale' => AnimPath.scale,
          _ => null,
        };
        if (node == null || path == null) {
          continue;
        }
        final smp = _map(samplers[_int(c['sampler'])]);
        final times = _read(_int(smp['input']));
        var values = _read(_int(smp['output']));
        final w = path == AnimPath.rotation ? 4 : 3;
        final interp = smp['interpolation'] as String? ?? 'LINEAR';
        if (interp == 'CUBICSPLINE') {
          // In-tangent, value, out-tangent per key: keep the values.
          values = [
            for (var k = 0; k < times.length; k++)
              ...values.sublist((k * 3 + 1) * w, (k * 3 + 2) * w),
          ];
        }
        if (values.length < times.length * w) {
          continue;
        }
        channels.add(
          Channel(
            node,
            path,
            Float32List.fromList(times),
            Float32List.fromList(values),
            step: interp == 'STEP',
          ),
        );
      }
      if (channels.isEmpty) {
        continue;
      }
      var name = (anim['name'] as String?) ?? 'animation ${a + 1}';
      while (out.containsKey(name)) {
        name = '$name+';
      }
      out[name] = AnimationClip(name, channels);
    }
    return out;
  }
}
