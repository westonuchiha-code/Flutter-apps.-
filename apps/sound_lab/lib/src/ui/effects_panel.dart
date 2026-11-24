import 'package:audio_kit/audio_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';

/// Sound Lab's effect chain (the shared editor from audio_kit).
class EffectsPanel extends StatelessWidget {
  const EffectsPanel({super.key, required this.c});

  final LabController c;

  @override
  Widget build(BuildContext context) => EffectChainEditor(
    effects: c.fx,
    onAdd: c.addEffect,
    onChanged: c.updateEffect,
    onRemove: c.removeEffect,
    onMove: c.moveEffect,
  );
}
