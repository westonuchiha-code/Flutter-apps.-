import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixel_kit/pixel_kit.dart' as pk;
import 'package:window_manager/window_manager.dart';

import '../art/render.dart';
import '../art/species.dart';
import '../controller.dart';
import '../frames.dart';
import '../mood.dart';
import '../store.dart';
import '../weather.dart';
import '../widget_sync.dart';
import 'pet_view.dart';

bool get _desktop => Platform.isWindows || Platform.isLinux;

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});

  /// For tests.
  final PetController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  PetController? _c;
  PetController get c => _c!;
  bool _started = false;
  bool _mini = false;
  Size? _bigSize;
  Offset? _bigPos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c = widget.controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || _started) {
      return;
    }
    _started = true;
    unawaited(_start(Shell.of(context).locker));
  }

  Future<void> _start(AssetLocker locker) async {
    final store = await PetStore.open();
    final c = PetController(
      store: store,
      lockerItems: () => _lockerItems(locker),
    );
    await c.init();
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(() => _c = c);
  }

  static Future<Map<String, (String, String)>?> _lockerItems(
    AssetLocker locker,
  ) async {
    if (!locker.ready) {
      return null;
    }
    try {
      return {
        for (final a in await locker.list()) a.id: (a.type.label, a.name),
      };
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (state == AppLifecycleState.resumed && c != null && c.loaded) {
      unawaited(c.refresh(full: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) {
      _c?.dispose();
    }
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  // ---- Settings ----

  Future<void> _pickSpecies() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SpeciesSheet(current: c.data.pet.species),
    );
    if (pick == null) {
      return;
    }
    if (pick == 'custom') {
      await _pickSprite();
    } else {
      await c.setSpecies(pick);
    }
  }

  Future<void> _pickSprite() async {
    final locker = Shell.of(context).locker;
    if (!locker.ready && !await locker.connect()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final info = await pickFromLocker(
      context,
      locker,
      types: const [AssetType.sprite],
    );
    if (info == null) {
      return;
    }
    try {
      final bytes = await locker.read(info);
      if (bytes == null || info.extension != 'json') {
        throw const FormatException('Pick a Pixel Forge sprite');
      }
      final s = pk.Sprite.fromJson(jsonDecode(utf8.decode(bytes)));
      if (s.width > 128 || s.height > 128) {
        throw const FormatException('Sprites up to 128×128 only');
      }
      await c.setSpecies(
        'custom',
        custom: CustomSprite(info.name, s.width, s.height, [
          for (var f = 0; f < s.frames.length && f < 8; f++) s.flatten(f),
        ]),
      );
    } catch (e) {
      _snack('Could not use that sprite: $e');
    }
  }

  Future<void> _rename() async {
    final field = TextEditingController(text: c.data.pet.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name'),
        content: TextField(
          controller: field,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await c.rename(name.trim());
    }
  }

  Future<void> _place() async {
    final place = await showDialog<Place>(
      context: context,
      builder: (_) => const _PlaceDialog(),
    );
    if (place != null) {
      await c.setPlace(place);
    }
  }

  Future<void> _time(bool bed) async {
    final m = bed ? c.data.pet.bedMinutes : c.data.pet.wakeMinutes;
    final t = await showTimePicker(
      context: context,
      helpText: bed ? 'Bedtime' : 'Wake time',
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) {
      return;
    }
    final v = t.hour * 60 + t.minute;
    await c.setTimes(bed: bed ? v : null, wake: bed ? null : v);
  }

  Future<void> _addWidget() async {
    try {
      if (await HomeWidget.isRequestPinWidgetSupported() == true) {
        await HomeWidget.requestPinWidget(qualifiedAndroidName: widgetProvider);
        return;
      }
    } catch (_) {}
    _snack('Long-press your home screen, choose Widgets, and find Sprite Pet.');
  }

  Future<void> _saveToLocker() async {
    final locker = Shell.of(context).locker;
    if (!locker.ready && !await locker.connect()) {
      return;
    }
    final s = petToSprite(c.species);
    await locker.save(
      type: AssetType.sprite,
      name: '${c.data.pet.name} (${c.species.name})',
      bytes: utf8.encode(jsonEncode(s.toJson())),
      extension: 'json',
      thumbnail: framePng(renderPet(c.species, Mood.idle, 0), scale: 4),
      tags: const ['sprite pet'],
      extra: {
        'kind': pk.Sprite.kind,
        'moods': [for (final m in Mood.values) m.name],
        'framesPerMood': framesPerMood,
      },
    );
    _snack(
      'Saved to Sprites: every mood, 4 frames each. Open it in Pixel Forge to change it.',
    );
  }

  // ---- Desktop mini pet ----

  Future<void> _setMini(bool on) async {
    if (!_desktop) {
      return;
    }
    try {
      await windowManager.ensureInitialized();
      if (on) {
        _bigSize = await windowManager.getSize();
        _bigPos = await windowManager.getPosition();
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        await windowManager.setMinimumSize(const Size(160, 190));
        await windowManager.setSize(const Size(180, 220));
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setAlignment(Alignment.bottomRight);
      } else {
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setMinimumSize(const Size(400, 400));
        if (_bigSize != null) {
          await windowManager.setSize(_bigSize!);
        }
        if (_bigPos != null) {
          await windowManager.setPosition(_bigPos!);
        }
      }
      setState(() => _mini = on);
    } catch (e) {
      _snack('Mini pet is not available here: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => _mini ? _miniView() : _full(context),
    );
  }

  Widget _miniView() => Scaffold(
    body: Column(
      children: [
        Expanded(
          child: DragToMoveArea(
            child: PetStage(frames: c.frames, mood: c.mood, look: c.look),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: 'Feed',
              icon: const Icon(Icons.restaurant),
              onPressed: c.feed,
            ),
            IconButton(
              tooltip: 'Pet',
              icon: const Icon(Icons.favorite_border),
              onPressed: c.pet,
            ),
            IconButton(
              tooltip: 'Back to the full app',
              icon: const Icon(Icons.open_in_full),
              onPressed: () => _setMini(false),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _full(BuildContext context) {
    final p = c.data.pet;
    final w = c.data.weather;
    final status = [
      c.mood.label,
      if (w != null && c.look != WeatherLook.none) w.describe(),
      if (p.charging) 'charging',
    ].join(' · ');
    final stage = PetStage(
      frames: c.frames,
      mood: c.mood,
      look: c.look,
      child: Positioned(
        left: 12,
        bottom: 6,
        child: Text(
          status,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 3)],
          ),
        ),
      ),
    );
    final panel = _Panel(
      c: c,
      onSpecies: _pickSpecies,
      onName: _rename,
      onPlace: _place,
      onTime: _time,
      onWidget: Platform.isAndroid ? _addWidget : null,
      onSave: _saveToLocker,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          if (_desktop)
            IconButton(
              tooltip: 'Mini pet (stays on top)',
              icon: const Icon(Icons.picture_in_picture_alt_outlined),
              onPressed: () => _setMini(true),
            ),
          ...shellActions(context),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= 800) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: stage),
                  SizedBox(width: 380, child: panel),
                ],
              );
            }
            return Column(
              children: [
                SizedBox(
                  height: (box.maxHeight * 0.42).clamp(180.0, 420.0),
                  child: stage,
                ),
                Expanded(child: panel),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.c,
    required this.onSpecies,
    required this.onName,
    required this.onPlace,
    required this.onTime,
    required this.onWidget,
    required this.onSave,
  });

  final PetController c;
  final VoidCallback onSpecies, onName, onPlace, onSave;
  final void Function(bool bed) onTime;
  final VoidCallback? onWidget;

  String _hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = c.data.pet;
    final t = Theme.of(context).textTheme;
    final asleep = c.mood == Mood.asleep;
    Widget bar(String label, double v, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 10,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        bar('Food', p.food, Colors.orange),
        bar('Energy', p.energy, Colors.lightBlue),
        bar('Fun', p.fun, Colors.pinkAccent),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: c.feed,
              icon: const Icon(Icons.restaurant),
              label: const Text('Feed'),
            ),
            FilledButton.tonalIcon(
              onPressed: c.pet,
              icon: const Icon(Icons.favorite_border),
              label: const Text('Pet'),
            ),
            FilledButton.tonalIcon(
              onPressed: asleep ? null : c.play,
              icon: const Icon(Icons.sports_esports_outlined),
              label: const Text('Play'),
            ),
            FilledButton.tonalIcon(
              onPressed: asleep ? c.wakeUp : c.toBed,
              icon: Icon(
                asleep ? Icons.wb_sunny_outlined : Icons.bedtime_outlined,
              ),
              label: Text(asleep ? 'Wake up' : 'Bed'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text('Diary', style: t.titleSmall),
        if (p.log.isEmpty)
          Text(
            'Nothing yet. Things you save to the Asset Locker count as treats.',
            style: t.bodySmall,
          ),
        for (final line in p.log.take(6)) Text(line, style: t.bodySmall),
        const Divider(height: 28),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.pets),
          title: Text(c.species.name),
          subtitle: Text(c.species.about),
          onTap: onSpecies,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined),
          title: Text('Name: ${p.name}'),
          onTap: onName,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_outlined),
          title: Text(
            c.data.place == null
                ? 'Weather: off'
                : 'Weather: ${c.data.place!.label}',
          ),
          subtitle: Text(
            c.weatherError ??
                (c.data.weather?.describe() ??
                    'Pick a town for rain, snow, sun and storms'),
          ),
          onTap: onPlace,
          trailing: c.data.place == null
              ? null
              : IconButton(
                  tooltip: 'Weather off',
                  icon: const Icon(Icons.clear),
                  onPressed: () => c.setPlace(null),
                ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bedtime_outlined),
          title: Text(
            'Bedtime ${_hm(p.bedMinutes)} · wakes ${_hm(p.wakeMinutes)}',
          ),
          subtitle: const Text('An hour longer at weekends'),
          onTap: () => onTime(true),
          trailing: IconButton(
            tooltip: 'Wake time',
            icon: const Icon(Icons.alarm),
            onPressed: () => onTime(false),
          ),
        ),
        if (onWidget != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('Add to home screen'),
            subtitle: const Text(
              'The pet lives on a widget with Feed, Pet and Play buttons',
            ),
            onTap: onWidget,
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.save_alt),
          title: const Text('Save pet to Asset Locker'),
          subtitle: const Text('All moods as a Pixel Forge sprite'),
          onTap: onSave,
        ),
        Text('Age: ${p.ageDays} days', style: t.bodySmall),
      ],
    );
  }
}

class _SpeciesSheet extends StatefulWidget {
  const _SpeciesSheet({required this.current});
  final String current;

  @override
  State<_SpeciesSheet> createState() => _SpeciesSheetState();
}

class _SpeciesSheetState extends State<_SpeciesSheet> {
  final _images = <String, ui.Image>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    for (final s in builtInSpecies) {
      final img = await petImage(renderPet(s, Mood.happy, 1));
      if (!mounted) {
        return;
      }
      setState(() => _images[s.id] = img);
    }
  }

  @override
  void dispose() {
    for (final i in _images.values) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in builtInSpecies)
            _Choice(
              label: s.name,
              selected: s.id == widget.current,
              onTap: () => Navigator.pop(context, s.id),
              child: _images[s.id] == null
                  ? const SizedBox()
                  : RawImage(
                      image: _images[s.id],
                      filterQuality: FilterQuality.none,
                      fit: BoxFit.contain,
                    ),
            ),
          _Choice(
            label: 'From Pixel Forge…',
            selected: widget.current == 'custom',
            onTap: () => Navigator.pop(context, 'custom'),
            child: const Icon(Icons.brush_outlined, size: 40),
          ),
        ],
      ),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            SizedBox(width: 80, height: 80, child: child),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceDialog extends StatefulWidget {
  const _PlaceDialog();

  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  final _q = TextEditingController();
  List<Place> _found = const [];
  bool _busy = false;
  String? _error;

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await searchPlaces(_q.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _found = r;
        if (r.isEmpty) {
          _error = 'No places found.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not search: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Weather for'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _q,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Town or city',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _busy ? null : _search,
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in _found)
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text(p.region),
                    onTap: () => Navigator.pop(context, p),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Weather from Open-Meteo (free, no account).',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
