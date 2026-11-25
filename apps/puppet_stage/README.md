# Puppet Stage

Windows, Android, Linux. Little 3D movies without skill (roadmap #19,
"3D Choreographer"). Built on `engine3d` and `video_encoder`.

- **Cast:** man, woman, boy, girl, old man, old woman, big guy, teen,
  toddler, robot: PS1-style segmented figures made in code (17 joints).
  Each is a template to change: colours, body sliders (height, build,
  head, arms, legs), things to wear (hat, cap, glasses, dress, jacket,
  backpack, beard). "Save as a template" keeps one in the Asset Locker
  (Presets, kind `puppet_template`) to add again in any movie.
- **Animals** (`animals.dart`): dog, cat, cow, horse, pig (four legs) and
  chicken, bird, in the same blocky style, each with its own moves: stand,
  walk, run, sit, lie down, sleep, eat, jump, look around, wag, shake off
  and its call (bark, meow, moo, neigh, oink); birds peck, flap, hop, sit,
  fly and cluck/tweet. Sitting is worked out from each body's shape.
- **Plants and props** (`props.dart`): trees (round, pine, palm), bush,
  flowers, cactus, potted plant, rock; table, chair, bench, bed, sofa,
  lamp; car, fence, lamp post, mailbox; box, ball, cup, sign; turntables
  (the records spin), speaker stack, mic stand, boombox, microphone;
  katana, candle, lantern, chess king/knight/rook. Colours and
  size per item; plants sway, the car's wheels turn and the ball rolls
  when they move along.
- **Actions:** each person has a list: 27 moves (wave, dance, jump, sit,
  clap, bow, point, cheer, kick, fall over, think, talk, shrug, nod, shake
  head, punch, crouch, stand; rap ×3, head-nod bounce, B-boy stance, DJ
  scratch, sword stance, sword cut, kneel; music loops are timed to 86 BPM), walk to / run to (tap the floor), turn,
  wait. Moves crossfade.
- **Holds:** a person can hold a prop in the right hand (mic, katana,
  candle, lantern, cup, ball, boombox). Imported models can't yet.
- **Sets:** studio, street, park, room, rooftop at night, dojo (chess
  floor), dark stage with one light.
- **Places** (`places.dart`): a movie can have more places than its main
  set: other sets or **Vista landscapes** (presets, or a landscape saved
  from Vista; `packages/landscape`). Each actor stands in one place (on
  the landscape's ground); each shot says which place it films.
- **Camera:** save the current view as a shot at the current time;
  playback cuts between shots. A shot can drift to a second view (eased,
  until the next cut) and have its own film look.
- **Film looks** (`look.dart`): black & white, noir, sepia film, night
  blue, 90s video, fisheye: grain, flicker, vignette, letterbox, barrel
  distortion. One for the movie, any shot can override it.
- **Music:** a WAV from the Asset Locker plays with the preview and goes
  into the video (fading out in the last second).
- **Pose (stop motion):** bend / twist / tilt any joint, add the pose as a
  frame, change it, add again.
- **Video:** MP4 854×480 30 fps (AVI fallback) to the Asset Locker
  (Videos) or share. Movies save as JSON to Presets (kind `puppet_movie`).
- PS1 look by default; clean look in the menu.

Pure-Dart core (tested): `cast.dart`, `moves.dart`, `movie.dart`,
`sets.dart`, `export.dart`, `look.dart`, `places.dart`, `staging.dart`.

`tool/liquid_logic.dart` is the music video for "Liquid Logic"
(`tool/album`), written as a movie; `tool/liquid_logic_test.dart` saves it
as JSON, renders a contact sheet of its shots, or the whole video.

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
