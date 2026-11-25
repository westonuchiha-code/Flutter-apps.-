# engine3d

Lightweight 3D for the apps (pure Dart + Flutter's `Canvas.drawVertices`).

- Materials are `Surface` (colour, texture, lit, doubleSided, fogged); meshes
  can carry per-vertex colours. `Scene.skyHorizon` gives a gradient sky.
  Cameras include `FlyRig`.
- Scene graph (`Node`: position, rotation, scale, mesh, material, children,
  `layer`), `Scene` (sky, ambient, sun, point lights, fog).
- Meshes: box, subdivided plane, sphere, cylinder, height-map terrain (with
  holes); `MeshBuilder`; glTF 2.0 (`loadGltf`: .glb or embedded .gltf —
  meshes, base colours, textures, node transforms; `loadGltfModel` also
  returns skins and animations)
  and OBJ (`loadObj`). `fitModel` scales a model to a height.
- Cameras: `OrbitRig`, `WalkRig` (walls as `Box`es, ground height).
- `Renderer`: per-vertex lighting, near-plane clipping, back-face culling,
  triangles sorted far to near (no depth buffer, like the PS1's ordering
  table — use `Node.layer = -1` for floors), textured batches, fog.
- `RenderOptions()` is the PS1 look (240-line picture, vertex snapping,
  sharp texels, fog); `RenderOptions.clean` is full resolution and smooth.
- Animation: `AnimationClip` (translation/rotation/scale channels, step /
  linear / cubic), `retarget`, `blend`; `Animator` plays clips with
  crossfades; `Skin` does CPU skinning (glTF JOINTS_0/WEIGHTS_0).
- `Node.depthBias`: metres a node counts as nearer when sorted, for things
  worn flat on a bigger surface (glasses on a face) so they don't sink in.
- `groundPoint` turns a screen tap into a spot on the floor.
- `Viewport3D` widget: frame loop, touch joystick, drag/pinch, keys,
  `onTap`, stats overlay.

Speed is measured on devices with 3D Lab's fps counter.
