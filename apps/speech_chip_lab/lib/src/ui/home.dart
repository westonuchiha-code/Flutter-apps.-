import 'dart:typed_data';
import 'dart:async';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:chip_synth/chip_synth.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import '../output.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});

  /// For tests; normally created here with real audio.
  final SpeechController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SpeechController? _c;
  String? _error;
  final _text = TextEditingController(text: exampleText);
  bool _busy = false;
  bool _sing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      var c = widget.controller;
      if (c == null) {
        c = SpeechController(SoLoudSpeechOutput());
        await c.init();
      }
      _text.text = c.text;
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start audio: $e');
    }
  }

  @override
  void dispose() {
    _text.dispose();
    if (widget.controller == null) _c?.dispose();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _fixWord(SpokenWord w) async {
    final c = _c!;
    final ctl = TextEditingController(text: w.phonemes.join(' '));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sounds for "${w.text}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                helperText: 'Sound names separated by spaces',
              ),
            ),
            TextButton(
              onPressed: () => _showSounds(context),
              child: const Text('List of sounds'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Undo fix'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (result == null) return;
    if (result.isEmpty) {
      c.clearFix(w.text);
      return;
    }
    final sounds = result
        .toUpperCase()
        .split(RegExp(r'[\s,]+'))
        .where(phonemes.containsKey)
        .toList();
    if (sounds.isEmpty) {
      _snack('None of those are sound names. Tap "List of sounds".');
      return;
    }
    c.fixWord(w.text, sounds);
  }

  void _showSounds(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('Sounds', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              'Type these in [brackets] in the text, or tap a word to fix it.',
            ),
            const SizedBox(height: 8),
            for (final p in phonemes.values)
              ListTile(
                dense: true,
                leading: SizedBox(
                  width: 40,
                  child: Text(
                    p.code,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(p.example),
                subtitle: Text(p.kind.name),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _menu(String action) async {
    final c = _c!;
    final shell = Shell.of(context);
    final words = c.words;
    if (words.isEmpty) {
      _snack('Type something to say first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final settings = c.settings;
      final wav = await runInBackground(_speechWav, (words, settings));
      final name = c.text.trim().split(RegExp(r'\s+')).take(5).join(' ');
      if (action == 'share') {
        await shell.exporter.exportFile(
          '$name.wav',
          wav,
          mimeType: 'audio/wav',
        );
      } else {
        final locker = shell.locker;
        if (!locker.ready && !await locker.connect()) {
          _snack('Connect the Asset Locker first.');
          return;
        }
        final mono = decodeWavMono(wav, targetRate: speechRate);
        await locker.save(
          type: AssetType.sample,
          name: name,
          bytes: wav,
          extension: 'wav',
          thumbnail: await waveformPng(floatPeaks(mono, speechRate ~/ 100)),
          tags: ['speech', settings.chip.name, 'speech chip lab'],
          extra: {
            'seconds': mono.length / speechRate,
            'text': c.text,
            'speech': settings.toJson(),
          },
        );
        _snack('Saved "$name" to Samples');
      }
    } catch (e) {
      _snack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Speech Chip Lab')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Text(_error!),
        ),
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Speech Chip Lab'),
          actions: [
            IconButton(
              tooltip: 'List of sounds',
              icon: const Icon(Icons.record_voice_over_outlined),
              onPressed: () => _showSounds(context),
            ),
            PopupMenuButton<String>(
              tooltip: 'Save',
              icon: const Icon(Icons.save_outlined),
              onSelected: _menu,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'locker',
                  child: Text('Save to Asset Locker (Samples)'),
                ),
                PopupMenuItem(value: 'share', child: Text('Export WAV…')),
              ],
            ),
            ...shellActions(context),
          ],
        ),
        body: SafeArea(child: _body(context, c)),
      ),
    );
  }

  Widget _body(BuildContext context, SpeechController c) {
    final theme = Theme.of(context);
    final s = c.settings;
    final words = c.words;
    final editor = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (_busy) const LinearProgressIndicator(),
        TextField(
          controller: _text,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Text to say',
            helperText: 'Use [HH EH L OW] for exact sounds. Tap a word below to fix it.',
            border: OutlineInputBorder(),
          ),
          onChanged: c.setText,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < words.length; i++)
              ActionChip(
                backgroundColor: i == c.wordIndex && (c.speaking || _sing)
                    ? theme.colorScheme.primaryContainer
                    : null,
                side: c.overrides.containsKey(words[i].text.toLowerCase())
                    ? BorderSide(color: theme.colorScheme.tertiary, width: 2)
                    : null,
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(words[i].text),
                    Text(
                      words[i].phonemes.join(' '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                onPressed: () => _fixWord(words[i]),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedButton<SpeechChip>(
          segments: const [
            ButtonSegment(value: SpeechChip.tms5220, label: Text('TMS5220')),
            ButtonSegment(value: SpeechChip.sp0256, label: Text('SP0256')),
            ButtonSegment(value: SpeechChip.votrax, label: Text('Votrax')),
          ],
          selected: {s.chip},
          showSelectedIcon: false,
          onSelectionChanged: (v) => c.setSettings(s.copyWith(chip: v.first)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${s.chip.label}: ${s.chip.about}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        _Knob(
          s.chip == SpeechChip.votrax
              ? 'Clock (pitch, size and speed)'
              : 'Pitch',
          '${s.pitch.round()} Hz',
          s.pitch,
          50,
          300,
          (v) => c.setSettings(s.copyWith(pitch: v)),
        ),
        _Knob(
          'Speed',
          '${(s.speed * 100).round()}%',
          s.speed,
          0.5,
          2,
          (v) => c.setSettings(s.copyWith(speed: v)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SegmentedButton<Contour>(
            segments: [
              for (final k in Contour.values)
                ButtonSegment(value: k, label: Text(k.label)),
            ],
            selected: {s.contour},
            showSelectedIcon: false,
            onSelectionChanged: (v) =>
                c.setSettings(s.copyWith(contour: v.first)),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Whisper'),
          value: s.whisper,
          onChanged: (v) => c.setSettings(s.copyWith(whisper: v)),
        ),
      ],
    );
    final speakRow = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: Icon(
                c.speaking && !_sing ? Icons.stop : Icons.record_voice_over,
              ),
              label: Text(c.speaking && !_sing ? 'Stop' : 'Speak'),
              onPressed: c.speaking && !_sing ? c.stop : c.speak,
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            avatar: const Icon(Icons.piano_outlined, size: 18),
            label: const Text('Sing'),
            selected: _sing,
            onSelected: (v) => setState(() => _sing = v),
          ),
        ],
      ),
    );
    final singPanel = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Octave down',
                icon: const Icon(Icons.chevron_left),
                onPressed: c.octave > 1
                    ? () => c.setOctave(c.octave - 1)
                    : null,
              ),
              Text('C${c.octave}'),
              IconButton(
                tooltip: 'Octave up',
                icon: const Icon(Icons.chevron_right),
                onPressed: c.octave < 6
                    ? () => c.setOctave(c.octave + 1)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  words.isEmpty
                      ? ''
                      : 'Next: "${words[c.singNext % words.length].text}"',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: c.restartLyrics,
                child: const Text('From the start'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: SizedBox(
            height: 120,
            child: PianoKeyboard(
              baseNote: (c.octave + 1) * 12,
              isDown: c.isDown,
              onNoteOn: c.noteOn,
              onNoteOff: c.noteOff,
              repaint: c,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'Each key sings the next word; hold it to hold the vowel.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
    return Column(
      children: [
        Expanded(child: editor),
        speakRow,
        if (_sing) singPanel,
      ],
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob(
    this.label,
    this.value,
    this.v,
    this.min,
    this.max,
    this.onChanged,
  );

  final String label, value;
  final double v, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value),
          ],
        ),
        Slider(
          value: v.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

Uint8List _speechWav((List<SpokenWord>, SpeechSettings) a) =>
    encodeWavMono16(renderSpeech(a.$1, a.$2), speechRate);
