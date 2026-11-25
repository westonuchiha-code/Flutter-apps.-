# Puppet Stage

Windows, Android, Linux. Little 3D movies without skill (roadmap #19,
"3D Choreographer"). Built on `engine3d` and `video_encoder`.

- **Cast:** man, woman, boy, girl, old man, old woman: PS1-style segmented
  figures made in code (17 joints), with skin / hair / top / bottom
  colours, names, place and facing.
- **Animals** (`animals.dart`): dog, cat, cow, horse, pig (four legs) and
  chicken, bird, in the same blocky style, each with its own moves: stand,
  walk, run, sit, lie down, sleep, eat, jump, look around, wag, shake off
  and its call (bark, meow, moo, neigh, oink); birds peck, flap, hop, sit,
  fly and cluck/tweet. Sitting is worked out from each body's shape.
- **Plants and props** (`props.dart`): trees (round, pine, palm), bush,
  flowers, cactus, potted plant, rock; table, chair, bench, bed, sofa,
  lamp; car, fence, lamp post, mailbox; box, ball, cup, sign. Colours and
  size per item; plants sway, the car's wheels turn and the ball rolls
  when they move along.
- **Actions:** each person has a list: 18 moves (wave, dance, jump, sit,
  clap, bow, point, cheer, kick, fall over, think, talk, shrug, nod, shake
  head, punch, crouch, stand), walk to / run to (tap the floor), turn,
  wait. Moves crossfade.
- **Sets:** studio, street, park, room.
- **Camera:** save the current view as a shot at the current time;
  playback cuts between shots.
- **Pose (stop motion):** bend / twist / tilt any joint, add the pose as a
  frame, change it, add again.
- **Video:** MP4 854×480 30 fps (AVI fallback) to the Asset Locker
  (Videos) or share. Movies save as JSON to Presets (kind `puppet_movie`).
- PS1 look by default; clean look in the menu.

Pure-Dart core (tested): `cast.dart`, `moves.dart`, `movie.dart`,
`sets.dart`, `export.dart`.

- **Import 3D models** (.glb / .gltf / .obj) from the Asset Locker or a
  file (files are kept in Models so movies find them again). People with
  a skeleton (Mixamo, Rigify, Quaternius, VRoid-style names) do every
  built-in move and can be posed (`retarget.dart`: a hidden blocky
  stand-in does the move and the skeleton copies it); models that face
  away are turned automatically. Animated models bring their own moves
  (and their own walk/run if wanted); anything else slides along.
  Height and "faces the wrong way" per model.

Local checks with real models (not in CI): `tool/model_check_test.dart`
and `tool/import_shot_test.dart` (`--dart-define=MODELS=<folder of .glb>`).
