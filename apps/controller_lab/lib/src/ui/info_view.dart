import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../layouts/layout.dart';
import '../model/controls.dart';

/// Everything the backend says about a controller: how the software sees
/// it (the same as RetroArch / PCSX2 / the PC XMB see it through SDL).
class InfoView extends StatelessWidget {
  const InfoView({
    super.key,
    required this.info,
    required this.layout,
    this.details = const [],
  });

  final ControllerInfo info;
  final ControllerLayout layout;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final battery = info.batteryPercent >= 0
        ? '${info.batteryPercent}% (${info.power.label})'
        : info.power.label;
    final rows = <(String, String)>[
      ('Name', info.name),
      if (info.gamepadName.isNotEmpty && info.gamepadName != info.name)
        ('Gamepad name', info.gamepadName),
      ('Read through', info.source),
      ('Vendor:product', info.vidPid),
      if (info.productVersion != 0)
        ('Product version', ControllerInfo.hex4(info.productVersion)),
      if (info.guid.isNotEmpty) ('GUID', info.guid),
      if (info.path.isNotEmpty) ('Path', info.path),
      if (info.serial.isNotEmpty) ('Serial', info.serial),
      ('Joystick type', info.joystickTypeName),
      ('Gamepad type', info.isGamepad ? info.gamepadType.sdlName : '—'),
      if (info.isGamepad && info.realGamepadType != info.gamepadType)
        ('Real type', info.realGamepadType.sdlName),
      ('Connection', info.connection.label),
      ('Battery', battery),
      ('Mapped', info.isGamepad ? 'Yes: SDL has a gamepad mapping' : 'No'),
      (
        'Raw controls',
        '${info.buttonCount} buttons, ${info.axisCount} axes, '
            '${info.hatCount} hats',
      ),
      ('Drawing', layout.title),
      for (final n in info.notes) ('Note', n),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    k,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                Expanded(child: SelectableText(v)),
              ],
            ),
          ),
        if (info.mapping.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Mapping', style: theme.textTheme.titleSmall),
              ),
              TextButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: info.mapping)),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              info.mapping,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
        if (details.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Backend settings', style: theme.textTheme.titleSmall),
          for (final d in details)
            Text(
              d,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
        ],
      ],
    );
  }
}
