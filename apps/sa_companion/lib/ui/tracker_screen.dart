import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_state.dart';
import '../data/game_data.dart';
import '../data/models.dart';
import '../data/progress.dart';
import 'theme.dart';
import 'widgets.dart';

class TrackerScreen extends StatelessWidget {
  const TrackerScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = state.progress;
    final sd = p.storyDone;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Text(
          'Everything the game counts toward 100%. Your real figure is under '
          'Stats in the pause menu.',
          style: TextStyle(color: SaColors.dim, fontSize: 15),
        ),
        SectionHeader('Story', count: '$sd / $missionCount'),
        SaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Story missions', style: _nameStyle),
              const Text(
                "Ticked on the Missions tab. Includes Zero's jobs and the "
                'casino heist.',
                style: _detailStyle,
              ),
              const SizedBox(height: 10),
              Meter(sd / missionCount),
            ],
          ),
        ),
        for (final section in trackSections) ...[
          SectionHeader(section.name),
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: item.max != null
                  ? _CounterCard(state: state, item: item)
                  : _CheckCard(state: state, item: item),
            ),
        ],
        SectionHeader(
          'Import / Export',
          count: '${p.exportsDone} / $exportCount',
        ),
        const Text(
          'Deliver to the crane at Easter Basin, San Fierro. Each list unlocks '
          'after the one before.',
          style: TextStyle(color: SaColors.dim, fontSize: 15),
        ),
        for (final list in exportLists) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(list.name.toUpperCase(), style: condensed(size: 14)),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final columns = (c.maxWidth / 150).floor().clamp(2, 4);
              final width = (c.maxWidth - 6 * (columns - 1)) / columns;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final car in list.cars)
                    SizedBox(
                      width: width,
                      child: _ExportCar(
                        name: car,
                        delivered: p.checked(Progress.exportId(car)),
                        onTap: () => state.toggleCheck(Progress.exportId(car)),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 14),
        const NoteBox(
          gold: true,
          bold: 'Reward at 100%:',
          text:
              '\$1,000,000, infinite ammo, double-strength vehicles, a Hydra '
              "on Sweet's roof and a Rhino under the bridge by Grove Street.",
        ),
        const NoteBox(gold: true, bold: 'Not required:', text: _notRequired),
        const SectionHeader('Backup'),
        _BackupCard(state: state),
      ],
    );
  }
}

const _notRequired =
    'girlfriends, gang territory, unique stunt jumps, gold medals, extra '
    'burglary and lowrider jobs, gambling, pool, basketball, triathlons, '
    'two-player icons';

const _nameStyle = TextStyle(
  fontWeight: FontWeight.w600,
  fontSize: 16.5,
  height: 1.2,
);
const _detailStyle = TextStyle(color: SaColors.dim, fontSize: 14);

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.state, required this.item});

  final AppState state;
  final TrackItem item;

  @override
  Widget build(BuildContext context) {
    final done = state.progress.checked(item.id);
    return SaCard(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      onTap: () => state.toggleCheck(item.id),
      child: Row(
        children: [
          TickBox(
            checked: done,
            onTap: () => state.toggleCheck(item.id),
            label: 'Mark ${item.name} done',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: _nameStyle),
                if (item.detail.isNotEmpty)
                  Text(item.detail, style: _detailStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({required this.state, required this.item});

  final AppState state;
  final TrackItem item;

  @override
  Widget build(BuildContext context) {
    final max = item.max!;
    final v = state.progress.count(item.id);
    Widget step(String label, int by, String semantics) => Expanded(
      child: Semantics(
        label: semantics,
        button: true,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            state.step(item, by);
          },
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF232B27), Color(0xFF1A201D)],
              ),
              border: Border.all(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(9),
              boxShadow: const [
                BoxShadow(color: SaColors.line, spreadRadius: 1),
              ],
            ),
            child: Text(label, style: condensed(size: 18, color: SaColors.ink)),
          ),
        ),
      ),
    );
    return SaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: _nameStyle),
          if (item.detail.isNotEmpty) Text(item.detail, style: _detailStyle),
          const SizedBox(height: 10),
          Row(
            children: [
              step('−', -1, 'One fewer'),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => _editCount(context),
                  child: Text(
                    '$v / $max',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: SaFonts.display,
                      fontSize: 20,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              step('+1', 1, 'One more'),
              if (max >= 50) ...[
                const SizedBox(width: 8),
                step('+5', 5, 'Five more'),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Meter(v / max, style: MeterStyle.green),
        ],
      ),
    );
  }

  /// Tap the number to type an exact count.
  Future<void> _editCount(BuildContext context) async {
    final controller = TextEditingController(
      text: '${state.progress.count(item.id)}',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SaColors.p1,
        title: Text(item.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(helperText: '0 to ${item.max}'),
          onSubmitted: (t) => Navigator.pop(context, int.tryParse(t)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) state.setCount(item, value);
  }
}

class _ExportCar extends StatelessWidget {
  const _ExportCar({
    required this.name,
    required this.delivered,
    required this.onTap,
  });

  final String name;
  final bool delivered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: delivered,
      button: true,
      label: name,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [SaColors.p1, SaColors.p2],
            ),
            border: Border.all(color: SaColors.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: delivered ? SaColors.money : null,
                  border: Border.all(
                    color: delivered ? SaColors.money : const Color(0xFF56696E),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: delivered ? SaColors.dim : SaColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupCard extends StatefulWidget {
  const _BackupCard({required this.state});

  final AppState state;

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  final _text = TextEditingController();
  String _message = '';
  bool _armed = false;
  Timer? _disarm;

  @override
  void dispose() {
    _text.dispose();
    _disarm?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final backup = widget.state.backup;
    _text.text = backup;
    await Clipboard.setData(ClipboardData(text: backup));
    setState(() => _message = 'Backup copied. Paste it somewhere safe.');
  }

  Future<void> _share() async {
    final backup = widget.state.backup;
    _text.text = backup;
    await SharePlus.instance.share(
      ShareParams(text: backup, subject: 'SA Companion backup'),
    );
  }

  Future<void> _restore() async {
    var text = _text.text;
    if (text.trim().isEmpty) {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      _text.text = text;
    }
    final ok = widget.state.restore(text);
    setState(
      () => _message = ok
          ? 'Progress restored.'
          : "That doesn't look like a backup. Paste the full text and try "
                'again.',
    );
  }

  void _reset() {
    if (!_armed) {
      setState(() => _armed = true);
      _disarm = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    _disarm?.cancel();
    widget.state.resetAll();
    setState(() {
      _armed = false;
      _message = 'Progress erased.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Progress lives only on this phone. Copy or share a backup to keep '
            'it safe or move it to another phone. Backups from the web version '
            'work here too.',
            style: TextStyle(color: SaColors.dim, fontSize: 15),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: SaColors.dim,
            ),
            decoration: InputDecoration(
              hintText: 'Backup text appears here. Paste a backup here to restore it.',
              hintStyle: const TextStyle(color: Color(0xFF6D7A74)),
              filled: true,
              fillColor: const Color(0xFF0B0E0D),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: SaColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: SaColors.line),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SaButton('Copy backup', small: true, onPressed: _copy),
              SaButton(
                'Share',
                small: true,
                kind: SaButtonKind.ghost,
                onPressed: _share,
              ),
              SaButton(
                'Restore',
                small: true,
                kind: SaButtonKind.ghost,
                onPressed: _restore,
              ),
              SaButton(
                _armed ? 'Tap again to erase' : 'Reset all',
                small: true,
                kind: SaButtonKind.danger,
                onPressed: _reset,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _message,
              style: const TextStyle(color: SaColors.dim, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
