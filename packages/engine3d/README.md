# engine3d

Lightweight 3D for the apps (pure Dart + Flutter's `Canvas.drawVertices`).

- Materials are `Surface` (colour, texture, lit, doubleSided, fogged); meshes
  can carry per-vertex colours. `Scene.skyHorizon` gives a gradient sky.
  Cameras include `FlyRig`.
- Scene graph (`Node`: position, rotation, scale, mesh, material, children,
  `layer`), `Scene` (sky, ambient, sun, point lights, fog).
- Meshes: box, subdivided plane, sphere, cylinder, height-map terrain (with
  holes); `MeshBuilder`; glTF 2.0 (`loadGltf`: .glb or embedded .gltf —
  meshes, base colours, textures, node transforms; no skins/animation yet)
  and OBJ (`loadObj`). `fitModel` scales a model to a height.
- Cameras: `OrbitRig`, `WalkRig` (walls as `Box`es, ground height).
- `Renderer`: per-vertex lighting, near-plane clipping, back-face culling,
  triangles sorted far to near (no depth buffer, like the PS1's ordering
  table — use `Node.layer = -1` for floors), textured batches, fog.
- `RenderOptions()` is the PS1 look (240-line picture, vertex snapping,
  sharp texels, fog); `RenderOptions.clean` is full resolution and smooth.
- `Viewport3D` widget: frame loop, touch joystick, drag/pinch, keys,
  stats overlay.

Speed is measured on devices with 3D Lab's fps counter.
