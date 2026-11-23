import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../model/creature.dart';
import '../model/game_state.dart';
import '../render/monster_art.dart';
import 'creature_sheet.dart';

/// Builds the camera view; calls [onCode] for each barcode seen.
typedef ScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.game,
    required this.onKept,
    this.scanner,
  });

  final GameState game;
  final VoidCallback onKept;
  final ScannerBuilder? scanner;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  MobileScannerController? _controller;
  bool _busy = false;
  String? _lastCode;
  DateTime _lastAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    if (widget.scanner == null) {
      _controller = MobileScannerController(
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.code93,
          BarcodeFormat.itf14,
          BarcodeFormat.codabar,
          BarcodeFormat.qrCode,
        ],
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onCode(String raw) async {
    if (_busy || raw.trim().isEmpty) return;
    final now = DateTime.now();
    if (raw == _lastCode &&
        now.difference(_lastAt) < const Duration(seconds: 4)) {
      return;
    }
    _lastCode = raw;
    _lastAt = now;
    _busy = true;
    HapticFeedback.mediumImpact();
    await _controller?.stop();
    if (!mounted) return;
    final result = widget.game.scan(raw);
    switch (result) {
      case CreatureFound():
        final kept = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => FoundScreen(game: widget.game, found: result),
          ),
        );
        if (kept ?? false) {
          widget.onKept();
          _busy = false;
          return;
        }
      case ItemFound(:final kind, :final count):
        await _notice(
          'Item barcode!',
          'You found $count× ${kind.name}. Drop it on the ranch to feed your monsters.',
        );
      case ItemAlreadyClaimed(:final kind):
        await _notice(
          'Already scanned today',
          'This barcode held ${kind.name}. Try again tomorrow.',
        );
    }
    _busy = false;
    if (mounted) await _controller?.start();
  }

  Future<void> _notice(String title, String body) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<void> _typeCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Type a barcode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'e.g. 036000291452'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Scan'),
          ),
        ],
      ),
    );
    if (code != null && code.trim().isNotEmpty) {
      _lastCode = null; // typed codes are never ignored as duplicates
      await _onCode(code.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera =
        widget.scanner?.call(context, _onCode) ??
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null) {
                _onCode(v);
                break;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Camera unavailable (${error.errorCode.name}). Allow camera access in Settings, or type a barcode below.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
    return Stack(
      children: [
        Positioned.fill(child: camera),
        // Scan window frame.
        Center(
          child: Container(
            width: 280,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF8CFF5A), width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xCC0B0C10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'SCAN ANY BARCODE',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _typeCode,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Type a code'),
                ),
              ),
              if (_controller != null) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Torch',
                  onPressed: () => _controller!.toggleTorch(),
                  icon: const Icon(Icons.flashlight_on),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "A monster appeared!" — name it and keep it, or let it go.
class FoundScreen extends StatelessWidget {
  const FoundScreen({super.key, required this.game, required this.found});

  final GameState game;
  final CreatureFound found;

  @override
  Widget build(BuildContext context) {
    final c = found.creature, g = c.genome;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan result')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SizedBox(
            height: 240,
            child: MonsterPortrait(
              silhouette: g.silhouette,
              palette: paletteFor(g, c.individual),
            ),
          ),
          Text(
            '${g.speciesName} appeared!',
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '${'★' * g.rarity.stars} ${g.rarity.label} · ${g.tribe.label} tribe · ${g.element.label} · ${c.individual.nature}',
            textAlign: TextAlign.center,
          ),
          if (c.individual.shiny)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '✦ A rare shiny colouring!',
                textAlign: TextAlign.center,
              ),
            ),
          if (found.alreadyOwned > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'You already have ${found.alreadyOwned} of this species.',
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'HP ${g.baseStats.hp} · ATK ${g.baseStats.attack} · DEF ${g.baseStats.defense} · SPD ${g.baseStats.speed}',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text(
              game.ranchFull
                  ? 'Keep (goes to the Box)'
                  : 'Keep (goes to the Ranch)',
            ),
            onPressed: () async {
              final name = await askNickname(context, g.speciesName, null);
              if (name == null) return;
              game.keep(c, nickname: name.trim().isEmpty ? null : name.trim());
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${c.name} went to the ${c.home == Home.ranch ? 'Ranch' : 'Box'}.',
                    ),
                  ),
                );
                Navigator.pop(context, true);
              }
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Let it go'),
          ),
        ],
      ),
    );
  }
}
