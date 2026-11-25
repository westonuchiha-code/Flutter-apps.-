import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Action;

import '../movie.dart';
import '../mv/check.dart';
import '../mv/director.dart';
import '../mv/song_map.dart';
import '../mv/styles.dart';
import '../staging.dart';

/// "Auto music video": a song from the Locker, its tempo (typed or
/// tapped), a style → a directed movie (cuts on the bar, cast, places,
/// looks), checked for dark shots. It opens in the editor like any movie.
class AutoVideoPage extends StatefulWidget {
  const AutoVideoPage({super.key, required this.chooseMusic});

  final Future<(MusicRef, Int16List)?> Function() chooseMusic;

  @override
  State<AutoVideoPage> createState() => _AutoVideoPageState();
}

class _AutoVideoPageState extends State<AutoVideoPage> {
  MusicRef? _music;
  Int16List? _pcm;
  final _bpm = TextEditingController(text: '90');
  double _offset = 0;
  String _style = styles.first.id;
  int _seed = 1;
  final _taps = <double>[];
  final _clock = Stopwatch()..start();
  String? _busy;

  void _tap() {
    final t = _clock.elapsedMilliseconds / 1000;
    if (_taps.isNotEmpty && t - _taps.last > 2) _taps.clear();
    _taps.add(t);
    final bpm = tempoFromTaps(_taps);
    if (bpm != null) setState(() => _bpm.text = '$bpm');
  }

  Future<void> _make() async {
    final pcm = _pcm, music = _music;
    final bpm = double.tryParse(_bpm.text.trim());
    if (pcm == null || music == null || bpm == null || bpm < 40 || bpm > 240) {
      return;
    }
    setState(() => _busy = 'Directing…');
    try {
      final map = SongMap.fromAudio(pcm, bpm, offset: _offset);
      final style = styleById(_style);
      final movie = Director(
        map,
        style,
        seed: _seed,
      ).direct(music: music, name: '${music.name} (${style.name})');
      setState(() => _busy = 'Building the places and checking every shot…');
      final staging = await Staging.build(movie);
      await fixDarkShots(staging);
      if (!mounted) return;
      Navigator.pop(context, movie);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not make it: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _pcm != null && double.tryParse(_bpm.text.trim()) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Auto music video')),
      body: _busy != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_busy!),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('1. The song', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  icon: const Icon(Icons.music_note_outlined),
                  label: Text(_music?.name ?? 'Choose a WAV from the Locker'),
                  onPressed: () async {
                    final got = await widget.chooseMusic();
                    if (got != null) {
                      setState(() {
                        _music = got.$1;
                        _pcm = got.$2;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text('2. Its tempo', style: theme.textTheme.titleMedium),
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _bpm,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(suffixText: 'BPM'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: _tap,
                      child: const Text('Tap along'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('First beat at'),
                    Expanded(
                      child: Slider(
                        value: _offset,
                        max: 4,
                        divisions: 80,
                        onChanged: (v) => setState(() => _offset = v),
                      ),
                    ),
                    Text('${_offset.toStringAsFixed(2)} s'),
                  ],
                ),
                const SizedBox(height: 12),
                Text('3. A style', style: theme.textTheme.titleMedium),
                RadioGroup<String>(
                  groupValue: _style,
                  onChanged: (v) => setState(() => _style = v ?? _style),
                  child: Column(
                    children: [
                      for (final st in styles)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: st.id,
                          title: Text('${st.name}  ·  after ${st.inspiredBy}'),
                          subtitle: Text(st.about),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Take $_seed'),
                    TextButton(
                      onPressed: () => setState(() => _seed++),
                      child: const Text('Another take'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: ready ? _make : null,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Make it'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Cuts land on the bar; louder stretches cut faster. The movie '
                  'opens in the editor: change anything, then make the video.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
