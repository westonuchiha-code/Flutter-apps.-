import 'dart:convert';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:material_ui/material_ui.dart';

import '../time.dart';

/// Browse everything in the Asset Locker.
class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final locker = Shell.of(context).locker;
    return ListenableBuilder(
      listenable: locker,
      builder: (context, _) => LockerBrowser(
        locker: locker,
        onTap: (info) => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => AssetPreviewPage(info: info)),
        ),
      ),
    );
  }
}

const _imageExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
const _audioExt = {'wav', 'mp3', 'flac'};
const _textExt = {'json', 'txt', 'csv', 'md', 'xml', 'gpl', 'pal', 'hex'};

enum PreviewKind { image, audio, text, none }

PreviewKind previewKind(String ext) => _imageExt.contains(ext)
    ? PreviewKind.image
    : _audioExt.contains(ext)
    ? PreviewKind.audio
    : _textExt.contains(ext)
    ? PreviewKind.text
    : PreviewKind.none;

class AssetPreviewPage extends StatefulWidget {
  const AssetPreviewPage({super.key, required this.info});

  final AssetInfo info;

  @override
  State<AssetPreviewPage> createState() => _AssetPreviewPageState();
}

class _AssetPreviewPageState extends State<AssetPreviewPage> {
  Future<Uint8List?>? _bytes;
  AudioSource? _source;
  SoundHandle? _handle;
  String? _audioError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= Shell.of(context).locker.read(widget.info);
  }

  @override
  void dispose() {
    final s = _source;
    if (s != null) SoLoud.instance.disposeSource(s);
    super.dispose();
  }

  Future<void> _togglePlay(Uint8List bytes) async {
    final soloud = SoLoud.instance;
    try {
      if (_handle != null) {
        await soloud.stop(_handle!);
        setState(() => _handle = null);
        return;
      }
      if (!soloud.isInitialized) await soloud.init();
      _source ??= await soloud.loadMem(
        'preview.${widget.info.extension}',
        bytes,
      );
      final h = soloud.play(_source!);
      setState(() => _handle = h);
      final length = soloud.getLength(_source!);
      Future<void>.delayed(length, () {
        if (mounted && _handle == h) setState(() => _handle = null);
      });
    } catch (e) {
      setState(() => _audioError = 'Could not play this file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final shell = Shell.of(context);
    final kind = previewKind(info.extension);
    return Scaffold(
      appBar: AppBar(
        title: Text(info.name),
        actions: [
          IconButton(
            tooltip: 'Export / share',
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              final b = await _bytes;
              if (b != null) {
                await shell.exporter.exportFile(
                  '${info.name}.${info.extension}',
                  b,
                );
              }
            },
          ),
        ],
      ),
      body: FutureBuilder(
        future: _bytes,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final bytes = snap.data;
          final details = ListTile(
            title: Text('${info.type.label} · ${info.extension.toUpperCase()}'),
            subtitle: Text(
              [
                'Made by ${info.app}',
                timeAgo(info.created),
                sizeLabel(bytes?.length ?? info.size),
                if (info.tags.isNotEmpty) 'Tags: ${info.tags.join(', ')}',
              ].join(' · '),
            ),
          );
          if (bytes == null) {
            return Column(
              children: [details, const Text('The file is missing.')],
            );
          }
          final Widget body = switch (kind) {
            PreviewKind.image => InteractiveViewer(
              maxScale: 16,
              child: Center(
                child: Image.memory(
                  bytes,
                  filterQuality: FilterQuality.none,
                  errorBuilder: (_, _, _) =>
                      const Text('This image could not be shown.'),
                ),
              ),
            ),
            PreviewKind.audio => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    icon: Icon(_handle == null ? Icons.play_arrow : Icons.stop),
                    label: Text(_handle == null ? 'Play' : 'Stop'),
                    onPressed: () => _togglePlay(bytes),
                  ),
                  if (_audioError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_audioError!),
                    ),
                ],
              ),
            ),
            PreviewKind.text => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                utf8.decode(
                  bytes.length > 200000 ? bytes.sublist(0, 200000) : bytes,
                  allowMalformed: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            PreviewKind.none => const Center(
              child: Text('No preview for this kind of file yet.'),
            ),
          };
          return Column(
            children: [
              details,
              const Divider(height: 1),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}
