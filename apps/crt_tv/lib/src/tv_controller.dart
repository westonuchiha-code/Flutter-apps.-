import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:app_shell/app_shell.dart' show runInBackground;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetBuilder;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'android_storage.dart';
import 'app_store.dart';
import 'bindings.dart';
import 'diag.dart';
import 'gamepad.dart';
import 'languages.dart';
import 'channel_engine.dart';
import 'duration_prober.dart';
import 'library_scanner.dart';
import 'loudness.dart';
import 'loudness_prober.dart';
import 'season.dart';
import 'models.dart';
import 'static_sound.dart';

/// What's on a channel right now, for the guide.
typedef NowOn = ({String? title, bool commercial, Duration? remaining});

/// The TV itself: which channel is on, what it's playing, and every button
/// on the remote. The UI listens to it and redraws when it changes.
class TvController extends ChangeNotifier {
  TvController._(
    this.store, {
    required this.android,
    this._storage = const AndroidStorage(),
    this._testPlayer,
    this.pictureStandIn,
  });

  final AppStore store;

  /// Running on Android: the TV folder lives in shared storage and needs
  /// "All files" access, and folders are shown the way My Files shows them.
  final bool android;
  final AndroidStorage _storage;

  /// Tests: a stand-in for the video player (media_kit can't play there).
  final PlatformPlayer Function()? _testPlayer;

  /// Tests: drawn where the video would be, as there's no video output.
  final WidgetBuilder? pictureStandIn;
  AppSettings get settings => store.settings;

  /// Which key and controller button does what.
  late final Bindings bindings = Bindings(settings);

  /// The kind of controller in use, for showing the right symbols, and how
  /// many are plugged in.
  PadKind padKind = PadKind.xbox;
  int padCount = 0;

  void setControllers(PadKind kind, int count) {
    if (kind == padKind && count == padCount) return;
    padKind = kind;
    padCount = count;
    if (!_disposed) notifyListeners();
  }

  /// "XBOX STYLE", "PLAYSTATION", "NONE FOUND".
  String get padStatus {
    if (padCount == 0) return 'NONE FOUND';
    final name = padKind == PadKind.playstation ? 'PLAYSTATION' : 'XBOX STYLE';
    return padCount == 1 ? name : '$name ($padCount CONNECTED)';
  }

  late final Player player;

  /// The picture; null in tests (see [pictureStandIn]).
  VideoController? video;
  Player? _sfx;
  String? _staticSoundPath;
  final DurationProber _prober = DurationProber();
  final Set<String> _unprobeable = {};
  final Random _random = Random();

  TvLibrary? library;
  final Map<String, ChannelEngine> _engines = {};

  /// The channel the TV is tuned to.
  Channel? channel;

  /// What that channel is playing.
  QueueItem? nowPlaying;

  bool scanning = false;
  bool powerOn = true;

  /// True between pressing a channel button and the new video opening.
  bool get switching => _switching;
  bool paused = false;

  /// Snow on screen: during a channel change, or on an empty channel.
  bool staticVisible = false;

  /// Channel-number display (top right), e.g. "CH 03".
  String? osdChannel;
  String? osdName;
  String? osdTitle;
  Timer? _osdTimer;

  bool volumeOsdVisible = false;
  Timer? _volumeTimer;

  String digitBuffer = '';
  Timer? _digitTimer;

  int? _previousChannel;
  String? permissionProblem;

  /// Android: internal storage first, then SD cards.
  List<String> storageRoots = const [];

  /// Android: whether "All files" access has been given.
  bool allFilesAccess = true;

  /// Background length-check progress, shown in Settings.
  int probedCount = 0;
  int probeTotal = 0;

  int _tuneGeneration = 0;
  int _probeGeneration = 0;
  bool _switching = false;
  bool _advancing = false;
  bool _disposed = false;
  int _consecutiveFailures = 0;
  DateTime _openedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _openedFrom = Duration.zero;
  Duration _position = Duration.zero;
  Timer? _progressTimer;
  final List<StreamSubscription<Object?>> _subs = [];
  final Map<String, Future<void>> _catchUps = {};

  static Future<TvController> create() async {
    final store = await AppStore.open();
    final controller = TvController._(store, android: Platform.isAndroid);
    await controller._init();
    return controller;
  }

  /// A TV whose player is [player] and which has no video output, for
  /// tests and screenshots. [storage] answers the Android questions when
  /// [android] is true. Not for the app itself.
  static Future<TvController> forTesting({
    required AppStore store,
    required PlatformPlayer Function() player,
    bool android = false,
    AndroidStorage storage = const AndroidStorage(),
    WidgetBuilder? pictureStandIn,
  }) async {
    final controller = TvController._(
      store,
      android: android,
      storage: storage,
      testPlayer: player,
      pictureStandIn: pictureStandIn,
    );
    await controller._init();
    return controller;
  }

  /// [path] as the user knows it: on Android the way My Files shows it
  /// ("Internal storage › XMB Frontend › TV").
  String folderLabel(String path) =>
      android ? myFilesPath(path, roots: storageRoots) : path;

  Player _newPlayer(PlayerConfiguration configuration) {
    final fake = _testPlayer;
    return fake == null
        ? Player(configuration: configuration)
        : Player(platformPlayer: fake());
  }

  Future<void> _init() async {
    // ignore: prefer_const_constructors
    player = _newPlayer(PlayerConfiguration(libass: drawsOwnSubtitles));
    // CRT_TV_SOFTWARE_VIDEO=1 draws video without the graphics card's help:
    // slower, but it can't trip over a graphics driver. Launchers for
    // unfamiliar hardware set it.
    final softwareVideo = Platform.environment['CRT_TV_SOFTWARE_VIDEO'] == '1';
    if (_testPlayer == null) {
      video = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: !softwareVideo,
        ),
      );
    }
    // Awaiting here deadlocks: the player waits for its video surface, which needs the first frame.
    unawaited(player.setVolume(settings.muted ? 0.0 : settings.volume));
    _subs.add(player.stream.completed.listen(_onCompleted));
    _subs.add(player.stream.position.listen(_onPosition));
    _subs.add(player.stream.error.listen(_onError));
    if (diagOn) {
      diag(
        'video drawn by: ${softwareVideo ? 'the processor (software)' : 'the graphics card (hardware)'}',
      );
      _subs.add(
        player.stream.videoParams.listen((p) {
          if (p.w != null) {
            diag(
              'video: ${p.w}x${p.h}, format ${p.pixelformat}, shown at ${p.dw}x${p.dh}',
            );
          }
        }),
      );
      // How the player itself thinks playback is going.
      final native = player.platform;
      if (native is NativePlayer) {
        Timer.periodic(const Duration(seconds: 10), (_) async {
          try {
            final values = <String>[];
            for (final name in const [
              'estimated-vf-fps',
              'container-fps',
              'frame-drop-count',
              'decoder-frame-drop-count',
              'mistimed-frame-count',
              'avsync',
              'hwdec-current',
              'video-codec',
            ]) {
              values.add('$name=${await native.getProperty(name)}');
            }
            diag('video playback: ${values.join(', ')}');
          } catch (error) {
            diag('video playback: could not ask the player ($error)');
          }
        });
      }
    }
    _subs.add(player.stream.tracks.listen(_onTracks));
    _subs.add(
      player.stream.track.listen((_) {
        if (!_disposed) notifyListeners();
      }),
    );
    _progressTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _recordProgress(save: true),
    );
    unawaited(_initStaticSound());
    if (android) await _checkAndroidStorage();
    final path = settings.libraryPath;
    if (path != null) unawaited(loadLibrary(path));
  }

  /// Short: the menu cuts off long lines.
  static const _noAccess = 'NEEDS "ALL FILES" ACCESS';

  /// Android: storage roots and access; with access and no TV folder yet,
  /// starts using (and makes) `Internal storage › XMB Frontend › TV`.
  Future<void> _checkAndroidStorage() async {
    storageRoots = await _storage.storageRoots();
    allFilesAccess = await _storage.hasAllFiles();
    permissionProblem = allFilesAccess ? null : _noAccess;
    final start = startFolder(
      chosen: settings.libraryPath,
      access: allFilesAccess,
      roots: storageRoots,
    );
    if (start != null) {
      settings.libraryPath = start;
      store.scheduleSave();
    } else if (allFilesAccess && isDefaultFolder(settings.libraryPath)) {
      // Put it (and its guide) back if it was deleted.
      prepareTvFolder(settings.libraryPath!);
    }
  }

  /// Whether [path] is the TV's own folder in `XMB Frontend`.
  bool isDefaultFolder(String? path) =>
      path != null &&
      storageRoots.isNotEmpty &&
      path == defaultTvFolder(storageRoots.first);

  /// The TV's own folder, `Internal storage › XMB Frontend › TV` (Android).
  String? get defaultFolder =>
      storageRoots.isEmpty ? null : defaultTvFolder(storageRoots.first);

  /// Back in front (Android): access may have been given in Settings.
  Future<void> onResumed() async {
    if (!android || _disposed) return;
    final had = allFilesAccess;
    final before = settings.libraryPath;
    await _checkAndroidStorage();
    if (_disposed) return;
    final path = settings.libraryPath;
    if (!had && allFilesAccess && path != null) {
      await loadLibrary(path, retune: before != path || channel == null);
    } else {
      notifyListeners();
    }
  }

  /// Android: starts using the TV's own folder (making it if needed).
  Future<void> useDefaultFolder() async {
    final dir = defaultFolder;
    if (dir == null) return;
    prepareTvFolder(dir);
    await loadLibrary(dir);
  }

  Future<void> _initStaticSound() async {
    _staticSoundPath = await ensureStaticSound(store.dataDir);
    if (_staticSoundPath != null && !_disposed) {
      _sfx = _newPlayer(const PlayerConfiguration());
    }
  }

  // ---------------------------------------------------------------------------
  // Library

  /// The channels on the dial right now: seasonal ones only in their
  /// months, unless they've been set to show all year.
  List<Channel> get channels {
    final all = library?.channels ?? const <Channel>[];
    if (settings.seasonalAlways) return all;
    final today = DateTime.now();
    return [
      for (final c in all)
        if (inSeason(c.months, today)) c,
    ];
  }

  Channel? _onDial(int number) {
    for (final c in channels) {
      if (c.number == number) return c;
    }
    return null;
  }

  bool get hasLibrary => settings.libraryPath != null;

  List<String> commercialsFor(Channel c) => c.commercials.isNotEmpty
      ? c.commercials
      : (library?.globalCommercials ?? const []);

  /// Scanned in a static method so the background isolate only gets the path.
  static Future<TvLibrary> _scanInBackground(String path) =>
      runInBackground(scanLibrarySync, path);

  /// Reads (or re-reads) the TV folder and builds the channels.
  Future<void> loadLibrary(String path, {bool retune = true}) async {
    scanning = true;
    notifyListeners();
    if (android) {
      allFilesAccess = await _storage.hasAllFiles();
      permissionProblem = allFilesAccess ? null : _noAccess;
    }

    TvLibrary lib;
    try {
      lib = await _scanInBackground(path);
    } catch (e) {
      lib = TvLibrary(
        rootPath: path,
        channels: const [],
        globalCommercials: const [],
        warnings: ['Could not read the folder: $e'],
      );
    }
    if (_disposed) return;

    final changedFolder = settings.libraryPath != path;
    settings.libraryPath = path;
    library = lib;
    _configureEngines();
    scanning = false;
    store.scheduleSave();
    notifyListeners();
    _startBackgroundProbing();

    if (!retune) return;
    Channel? target;
    final current = channel;
    if (!changedFolder && current != null) target = _onDial(current.number);
    final last = settings.lastChannel;
    target ??= last == null ? null : _onDial(last);
    target ??= channels.isEmpty ? null : channels.first;
    if (target != null) {
      await tuneTo(target.number, withStatic: false);
    } else {
      channel = null;
      nowPlaying = null;
      staticVisible = false;
      await player.stop();
      notifyListeners();
    }
  }

  Future<void> rescan() async {
    final path = settings.libraryPath;
    if (path != null) await loadLibrary(path);
  }

  /// Android: opens the "All files access" page in Android's Settings.
  /// Coming back to the TV checks again ([onResumed]) and reads the folder.
  Future<void> requestAllFilesAccess() => _storage.requestAllFiles();

  void _configureEngines() {
    final lib = library;
    if (lib == null) return;
    for (final ch in lib.channels) {
      final engine = _engines.putIfAbsent(
        ch.folderName,
        () => ChannelEngine(store.stateFor(ch.folderName), random: _random),
      );
      engine.configure(
        programs: ch.programs,
        commercialPool: commercialsFor(ch),
        shuffle: settings.shuffleFor(ch.folderName),
        perBreak: settings.perBreakFor(ch.folderName),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Video lengths

  Future<Duration> durationOf(QueueItem item) async {
    final known = store.durations[item.path];
    if (known != null) return Duration(milliseconds: known);
    if (!_unprobeable.contains(item.path)) {
      final probed = await _prober.probe(item.path);
      if (probed != null) {
        store.durations[item.path] = probed.inMilliseconds;
        store.scheduleSave();
        return probed;
      }
      _unprobeable.add(item.path);
    }
    // Couldn't tell; assume a typical length.
    return item.isCommercial
        ? const Duration(seconds: 30)
        : const Duration(minutes: 22);
  }

  /// Checks every video's length in the background so live channels can
  /// work out what's on without a delay later.
  void _startBackgroundProbing() {
    final lib = library;
    if (lib == null) return;
    final generation = ++_probeGeneration;
    final all = <String>{
      ...lib.globalCommercials,
      for (final c in lib.channels) ...c.commercials,
      for (final c in lib.channels) ...c.programs,
    };
    final missing = all.where((p) => !store.durations.containsKey(p)).toList();
    probeTotal = all.length;
    probedCount = all.length - missing.length;
    notifyListeners();
    if (missing.isEmpty) return;

    unawaited(() async {
      var sinceSave = 0;
      for (final path in missing) {
        if (_disposed || generation != _probeGeneration) return;
        if (!store.durations.containsKey(path) &&
            !_unprobeable.contains(path)) {
          final d = await _prober.probe(path);
          if (_disposed) return;
          if (d != null) {
            store.durations[path] = d.inMilliseconds;
          } else {
            _unprobeable.add(path);
          }
        }
        probedCount++;
        if (++sinceSave >= 10) {
          sinceSave = 0;
          store.scheduleSave();
          notifyListeners();
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      store.scheduleSave();
      notifyListeners();
    }());
  }

  // ---------------------------------------------------------------------------
  // Tuning

  static String channelText(int number) =>
      'CH ${number.toString().padLeft(2, '0')}';

  /// Brings a channel's schedule up to the present moment.
  Future<void> _bringUpToDate(ChannelEngine engine, String key) {
    final running = _catchUps[key];
    if (running != null) return running;
    // A block body: returning the removed future would make it wait on itself.
    final future = _doBringUpToDate(engine).whenComplete(() {
      _catchUps.remove(key);
    });
    _catchUps[key] = future;
    return future;
  }

  Future<void> _doBringUpToDate(ChannelEngine engine) async {
    final state = engine.state;
    if (state.neverWatched) {
      if (state.current == null) engine.advance();
      final item = state.current;
      // A shuffled live channel you've never watched starts somewhere in the
      // middle of a show, like flipping to it on a real TV.
      if (item != null &&
          settings.liveMode &&
          engine.shuffle &&
          !item.isCommercial) {
        final length = await durationOf(item);
        state.positionMs = (length.inMilliseconds * _random.nextDouble() * 0.6)
            .round();
      }
    } else if (settings.liveMode) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - state.updatedAtMs;
      await engine.catchUp(Duration(milliseconds: max(0, elapsed)), durationOf);
    } else if (state.current == null) {
      engine.advance();
    }
    state.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> tuneTo(int number, {bool withStatic = true}) async {
    final lib = library;
    if (lib == null || !powerOn) return;
    final target = _onDial(number);
    if (target == null) {
      _showOsd(channelText(number), 'No channel', null);
      return;
    }

    final generation = ++_tuneGeneration;
    _troubleTimer?.cancel();
    troubleVisible = false;
    final current = channel;
    if (current != null && current.number != number) {
      _previousChannel = current.number;
    }
    _recordProgress();
    // The old channel goes quiet the moment the dial moves, as on a real
    // set. Working out what the new channel is showing can take a while
    // (seconds, the first time, on a slow drive), and until then the old
    // video would carry on being heard behind the static. Queued, not
    // awaited: nothing may hold up the open() that follows.
    if (current != null && current.number != number) _quietly(player.pause());
    _switching = true;
    _consecutiveFailures = 0;
    channel = target;
    nowPlaying = null;
    paused = false;
    settings.lastChannel = number;
    store.scheduleSave();

    final staticStarted = DateTime.now();
    final showStatic = withStatic && settings.staticOnChange;
    staticVisible = showStatic;
    if (showStatic) _playStaticSound();
    _showOsd(
      channelText(number),
      target.name.isEmpty ? null : target.name,
      null,
    );
    notifyListeners();

    final engine = _engines[target.folderName];
    if (engine == null || !engine.hasContent) {
      // An empty channel is just snow, like a real one.
      await player.stop();
      if (generation != _tuneGeneration) return;
      _stopStaticSound();
      staticVisible = true;
      _switching = false;
      notifyListeners();
      return;
    }

    await _bringUpToDate(engine, target.folderName);
    if (generation != _tuneGeneration) return;

    final item = engine.state.current;
    if (item == null) {
      await player.stop();
      if (generation != _tuneGeneration) return;
      staticVisible = true;
      _switching = false;
      notifyListeners();
      return;
    }

    await _openItem(
      item,
      Duration(milliseconds: engine.state.positionMs),
      generation,
    );
    if (generation != _tuneGeneration) return;

    if (showStatic) {
      const minimum = Duration(milliseconds: 450);
      final spent = DateTime.now().difference(staticStarted);
      if (spent < minimum) await Future<void>.delayed(minimum - spent);
      if (generation != _tuneGeneration) return;
      _stopStaticSound();
    }
    staticVisible = false;
    _switching = false;
    _showOsd(
      channelText(number),
      target.name.isEmpty ? null : target.name,
      item.isCommercial ? null : titleFromPath(item.path),
    );
  }

  Future<void> _openItem(QueueItem item, Duration from, int generation) async {
    // A saved position past the end of the video would open onto nothing.
    final length = store.durations[item.path];
    final start = length != null && from.inMilliseconds > length - 2000
        ? Duration.zero
        : from;
    nowPlaying = item;
    _openedAt = DateTime.now();
    _openedFrom = start;
    _position = start;
    try {
      // Nothing may be waited for before open(): until it's called the old
      // video keeps playing, its sound carries over, and its position gets
      // recorded against this one. These three are queued, not awaited.
      _prepareLevel(item);
      _tracksPending = true;
      if (player.state.track.audio.id != 'auto') {
        _quietly(player.setAudioTrack(AudioTrack.auto()));
      }
      if (player.state.track.subtitle.id != 'auto') {
        _quietly(player.setSubtitleTrack(SubtitleTrack.auto()));
      }
      await player.open(
        Media(item.path, start: start > Duration.zero ? start : null),
        play: powerOn && !paused,
      );
    } catch (_) {
      // The stall check below moves on if the file won't play.
    }
    if (generation != _tuneGeneration) return;
    // A video that failed earlier gets less patience the next time round.
    final knownBad = _unplayable.contains(item.path);
    _watchForTrouble(
      item,
      generation,
      Duration(milliseconds: knownBad ? 400 : 2500),
    );
    _checkForStall(
      item,
      generation,
      after: Duration(seconds: knownBad ? 3 : 6),
    );
    notifyListeners();
  }

  /// True while a video that won't play is "on": the screen shows a
  /// technical-difficulties card instead of going black.
  bool troubleVisible = false;
  Timer? _troubleTimer;
  final Set<String> _unplayable = {};

  /// Puts the card up if [item] still hasn't started after [after]. It
  /// comes down by itself as soon as a picture is moving again.
  void _watchForTrouble(QueueItem item, int generation, Duration after) {
    _troubleTimer?.cancel();
    _troubleTimer = Timer(after, () {
      if (_disposed ||
          generation != _tuneGeneration ||
          !identical(nowPlaying, item)) {
        return;
      }
      if (paused || !powerOn || troubleVisible) return;
      if (_position - _openedFrom >= const Duration(milliseconds: 300)) return;
      troubleVisible = true;
      notifyListeners();
    });
  }

  /// If a video hasn't started moving after a few seconds, skip it.
  void _checkForStall(
    QueueItem item,
    int generation, {
    Duration after = const Duration(seconds: 6),
    int retries = 3,
  }) {
    Timer(after, () {
      if (_disposed || generation != _tuneGeneration) return;
      if (!identical(nowPlaying, item) || paused || !powerOn) return;
      final moved = _position - _openedFrom;
      if (moved >= const Duration(milliseconds: 300)) return; // Playing fine.
      if (player.state.buffering && retries > 0) {
        // Slow drive or network share: give it a little longer.
        _checkForStall(
          item,
          generation,
          after: const Duration(seconds: 4),
          retries: retries - 1,
        );
        return;
      }
      _skipBroken(item, generation);
    });
  }

  void _onError(String message) {
    // Many decoder errors are harmless, so an error only triggers an early
    // check that the video is actually moving.
    final item = nowPlaying;
    if (item == null) return;
    if (DateTime.now().difference(_openedAt) > const Duration(seconds: 10)) {
      return;
    }
    _checkForStall(
      item,
      _tuneGeneration,
      after: const Duration(milliseconds: 2500),
      retries: 1,
    );
  }

  void _skipBroken(QueueItem item, int generation) {
    if (generation != _tuneGeneration ||
        _advancing ||
        !identical(nowPlaying, item)) {
      return;
    }
    _consecutiveFailures++;
    _unplayable.add(item.path);
    if (_consecutiveFailures > 8) {
      // Nothing on this channel will play; show snow instead of looping.
      nowPlaying = null;
      troubleVisible = false;
      staticVisible = true;
      notifyListeners();
      return;
    }
    if (!troubleVisible) {
      troubleVisible = true;
      notifyListeners();
    }
    unawaited(_playNext(generation));
  }

  void _onPosition(Duration position) {
    _position = position;
    if (troubleVisible &&
        position - _openedFrom > const Duration(milliseconds: 300)) {
      troubleVisible = false;
      notifyListeners();
    }
    if (_consecutiveFailures > 0 &&
        position - _openedFrom > const Duration(seconds: 3)) {
      _consecutiveFailures = 0;
    }
  }

  void _onCompleted(bool done) {
    if (!done || _switching || _advancing || !powerOn || channel == null) {
      return;
    }
    // Ignore a leftover "finished" signal from the video we just replaced.
    if (DateTime.now().difference(_openedAt) <
        const Duration(milliseconds: 300)) {
      return;
    }
    unawaited(_playNext(_tuneGeneration));
  }

  Future<void> _playNext(int generation) async {
    final ch = channel;
    if (ch == null) return;
    final engine = _engines[ch.folderName];
    if (engine == null) return;
    _advancing = true;
    try {
      final item = engine.advance();
      engine.state.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
      store.scheduleSave();
      if (item == null) {
        nowPlaying = null;
        staticVisible = true;
        await player.stop();
        notifyListeners();
        return;
      }
      await _openItem(item, Duration.zero, generation);
      if (!item.isCommercial &&
          settings.showTitles &&
          generation == _tuneGeneration) {
        _showOsd(
          channelText(ch.number),
          ch.name.isEmpty ? null : ch.name,
          titleFromPath(item.path),
        );
      }
    } finally {
      _advancing = false;
    }
  }

  /// Remembers how far into the current video we are.
  void _recordProgress({bool save = false}) {
    if (!powerOn || _switching) return;
    final ch = channel;
    final item = nowPlaying;
    if (ch == null || item == null) return;
    final engine = _engines[ch.folderName];
    if (engine == null || !identical(engine.state.current, item)) return;
    engine.state.positionMs = _position.inMilliseconds;
    engine.state.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    if (save) store.scheduleSave();
  }

  Future<void> saveForExit() async {
    _recordProgress();
    await store.saveNow();
  }

  // ---------------------------------------------------------------------------
  // Remote control buttons

  void channelUp() => _step(1);
  void channelDown() => _step(-1);

  void _step(int direction) {
    final list = channels;
    if (list.isEmpty || !powerOn) return;
    final current = channel?.number;
    final index = current == null
        ? -1
        : list.indexWhere((c) => c.number == current);
    int next;
    if (index < 0) {
      next = direction > 0 ? 0 : list.length - 1;
    } else {
      next = (index + direction) % list.length;
    }
    unawaited(tuneTo(list[next].number));
  }

  /// The "last channel" button.
  void previousChannel() {
    final p = _previousChannel;
    if (p != null) unawaited(tuneTo(p));
  }

  /// Number buttons: type 1-4 digits; it tunes after a short pause.
  void enterDigit(int digit) {
    if (!powerOn) return;
    if (digitBuffer.length >= 4) digitBuffer = '';
    digitBuffer += '$digit';
    _osdTimer?.cancel();
    osdChannel = 'CH ${digitBuffer.padRight(2, '-')}';
    osdName = null;
    osdTitle = null;
    notifyListeners();
    _digitTimer?.cancel();
    _digitTimer = Timer(const Duration(milliseconds: 1600), commitDigits);
  }

  void commitDigits() {
    _digitTimer?.cancel();
    if (digitBuffer.isEmpty) return;
    final number = int.tryParse(digitBuffer);
    digitBuffer = '';
    if (number != null) unawaited(tuneTo(number));
  }

  /// Starts the video that's on right now over from its beginning.
  Future<void> restartVideo() async {
    final ch = channel;
    final item = nowPlaying;
    if (!powerOn || _switching || ch == null || item == null) return;
    _openedAt = DateTime.now();
    _openedFrom = Duration.zero;
    _position = Duration.zero;
    await player.seek(Duration.zero);
    _recordProgress(save: true);
    _showOsd(
      channelText(ch.number),
      'From the start',
      item.isCommercial ? null : titleFromPath(item.path),
    );
  }

  // ---------------------------------------------------------------------------
  // Even volume across videos

  late final LoudnessProber _leveler = LoudnessProber(store.dataDir);
  final Set<String> _unmeasurable = {};

  /// Sets how far the player turns the current video up or down.
  Future<void> _setGain(double decibels) async {
    final native = player.platform;
    if (native is NativePlayer) {
      await native.setProperty(
        'replaygain-fallback',
        decibels.toStringAsFixed(1),
      );
    }
  }

  /// Lets a player call run on its own, ignoring a failure.
  static void _quietly(Future<void> call) =>
      unawaited(call.catchError((Object _) {}));

  final Set<String> _measuring = {};
  double _gain = 0;

  void _useGain(double decibels) {
    if (decibels == _gain) return;
    _gain = decibels;
    _quietly(_setGain(decibels));
  }

  /// Sets [item]'s volume adjustment without holding anything up: straight
  /// away if it has been measured before, otherwise it starts unadjusted
  /// and is measured in the background, with the adjustment applied a
  /// moment into the video.
  void _prepareLevel(QueueItem item) {
    if (!settings.levelSound) {
      _useGain(0);
      return;
    }
    final measured = store.loudness[item.path];
    _useGain(measured == null ? 0 : levelingGain(measured));
    if (measured != null ||
        _unmeasurable.contains(item.path) ||
        !_measuring.add(item.path)) {
      return;
    }

    final known = store.durations[item.path];
    // Flipping through channels shouldn't leave a queue of videos to
    // measure that are no longer on.
    bool wanted() => !_disposed && identical(nowPlaying, item);
    unawaited(
      _leveler
          .measure(
            item.path,
            length: known == null ? null : Duration(milliseconds: known),
            stillWanted: wanted,
          )
          .then((result) {
            _measuring.remove(item.path);
            if (result == null) {
              if (wanted()) _unmeasurable.add(item.path);
              return;
            }
            store.loudness[item.path] = result;
            store.scheduleSave();
            if (wanted() && settings.levelSound) _useGain(levelingGain(result));
          })
          .catchError((Object _) {
            _measuring.remove(item.path);
          }),
    );
  }

  /// Applies a change to the Level Volume setting to the video that's on.
  void applyLeveling() {
    final item = nowPlaying;
    if (item == null) {
      _useGain(0);
    } else {
      _prepareLevel(item);
    }
  }

  // ---------------------------------------------------------------------------
  // Sound and subtitle tracks

  /// On desktop the player draws subtitles into the picture itself, which
  /// covers every kind: styled ones and the picture-based ones on DVD and
  /// Blu-ray rips. Phones lack the fonts for that, so they show plain text
  /// subtitles over the video instead.
  static bool get drawsOwnSubtitles => !Platform.isAndroid && !Platform.isIOS;

  /// True from opening a video until its tracks are known and the saved
  /// language choices have been applied to it.
  bool _tracksPending = false;

  static bool _isRealTrack(String id) => id != 'auto' && id != 'no';

  List<AudioTrack> get audioTracks =>
      player.state.tracks.audio.where((t) => _isRealTrack(t.id)).toList();

  List<SubtitleTrack> get subtitleTracks =>
      player.state.tracks.subtitle.where((t) => _isRealTrack(t.id)).toList();

  static TrackInfo _audioInfo(AudioTrack t) =>
      TrackInfo(t.id, language: t.language, title: t.title);
  static TrackInfo _subtitleInfo(SubtitleTrack t) =>
      TrackInfo(t.id, language: t.language, title: t.title);

  /// What the menu shows for the sound track in use.
  String get audioTrackLabel {
    final tracks = audioTracks;
    if (tracks.isEmpty) return 'NONE';
    final i = tracks.indexWhere((t) => t.id == player.state.track.audio.id);
    if (i >= 0) return trackName(i, _audioInfo(tracks[i]));
    return tracks.length == 1
        ? trackName(0, _audioInfo(tracks[0]))
        : 'FILE DEFAULT';
  }

  String get subtitleTrackLabel {
    final tracks = subtitleTracks;
    if (tracks.isEmpty) return 'NONE';
    final current = player.state.track.subtitle.id;
    if (current == 'no') return 'OFF';
    final i = tracks.indexWhere((t) => t.id == current);
    return i >= 0 ? trackName(i, _subtitleInfo(tracks[i])) : 'FILE DEFAULT';
  }

  /// Switches this video to its next or previous sound track.
  void stepAudioTrack(int delta) {
    final tracks = audioTracks;
    if (tracks.length < 2) {
      showMessage('AUDIO', tracks.isEmpty ? 'NONE' : 'ONLY ONE TRACK');
      return;
    }
    final i = max(
      0,
      tracks.indexWhere((t) => t.id == player.state.track.audio.id),
    );
    final next = (i + delta) % tracks.length;
    unawaited(player.setAudioTrack(tracks[next]));
    showMessage('AUDIO', trackName(next, _audioInfo(tracks[next])));
  }

  /// Steps this video through off and each of its subtitle tracks.
  void stepSubtitleTrack(int delta) {
    final tracks = subtitleTracks;
    if (tracks.isEmpty) {
      showMessage('SUBTITLES', 'NONE IN THIS VIDEO');
      return;
    }
    // Position 0 is "off"; "file default" counts as off for stepping.
    final i =
        tracks.indexWhere((t) => t.id == player.state.track.subtitle.id) + 1;
    final next = (i + delta) % (tracks.length + 1);
    unawaited(
      player.setSubtitleTrack(
        next == 0 ? SubtitleTrack.no() : tracks[next - 1],
      ),
    );
    showMessage(
      'SUBTITLES',
      next == 0 ? 'OFF' : trackName(next - 1, _subtitleInfo(tracks[next - 1])),
    );
  }

  void _onTracks(Tracks tracks) {
    if (_disposed) return;
    final known =
        tracks.audio.any((t) => _isRealTrack(t.id)) ||
        tracks.subtitle.any((t) => _isRealTrack(t.id));
    if (_tracksPending && known) {
      _tracksPending = false;
      applyTrackDefaults();
    }
    notifyListeners();
  }

  /// Puts the saved language choices into effect on the video that's on.
  void applyTrackDefaults() {
    final audio = audioTracks;
    final subtitles = subtitleTracks;
    final choice = chooseTracks(
      audio: audio.map(_audioInfo).toList(),
      subtitles: subtitles.map(_subtitleInfo).toList(),
      audioLanguage: languageByCode(settings.audioLanguage),
      subtitleLanguage: languageByCode(settings.subtitleLanguage),
      mode: settings.subtitleMode,
    );
    for (final track in audio) {
      if (track.id == choice.audioId) unawaited(player.setAudioTrack(track));
    }
    if (choice.subtitleId == TrackChoice.noSubtitles) {
      unawaited(player.setSubtitleTrack(SubtitleTrack.no()));
    } else {
      for (final track in subtitles) {
        if (track.id == choice.subtitleId) {
          unawaited(player.setSubtitleTrack(track));
        }
      }
    }
  }

  void showInfo() {
    final ch = channel;
    if (ch == null) return;
    final item = nowPlaying;
    _showOsd(
      channelText(ch.number),
      ch.name.isEmpty ? null : ch.name,
      item == null
          ? null
          : (item.isCommercial ? 'Commercial break' : titleFromPath(item.path)),
    );
  }

  /// Flashes a short two-line note on the screen.
  void showMessage(String headline, String? detail) =>
      _showOsd(headline, detail, null);

  void _showOsd(String channelLabel, String? name, String? title) {
    osdChannel = channelLabel;
    osdName = name;
    osdTitle = settings.showTitles ? title : null;
    _osdTimer?.cancel();
    _osdTimer = Timer(const Duration(seconds: 4), () {
      osdChannel = null;
      osdName = null;
      osdTitle = null;
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    settings.volume = value < 0.0 ? 0.0 : (value > 100.0 ? 100.0 : value);
    settings.muted = false;
    await player.setVolume(settings.volume);
    _flashVolume();
  }

  void volumeStep(int direction) =>
      unawaited(setVolume(settings.volume + direction * 5));

  Future<void> toggleMute() async {
    settings.muted = !settings.muted;
    await player.setVolume(settings.muted ? 0.0 : settings.volume);
    _flashVolume();
  }

  void _flashVolume() {
    volumeOsdVisible = true;
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(seconds: 2), () {
      volumeOsdVisible = false;
      if (!_disposed) notifyListeners();
    });
    store.scheduleSave();
    notifyListeners();
  }

  Future<void> togglePause() async {
    if (!powerOn || nowPlaying == null) return;
    _recordProgress();
    paused = !paused;
    if (paused) {
      await player.pause();
    } else {
      await player.play();
    }
    notifyListeners();
  }

  Future<void> togglePower() async {
    if (powerOn) {
      _recordProgress(save: true);
      powerOn = false;
      staticVisible = false;
      osdChannel = null;
      _stopStaticSound();
      notifyListeners();
      await player.pause();
    } else {
      powerOn = true;
      notifyListeners();
      final ch = channel;
      if (ch != null) {
        // Live channels kept going while the TV was off.
        await tuneTo(ch.number, withStatic: false);
      } else if (channels.isNotEmpty) {
        await tuneTo(channels.first.number, withStatic: false);
      }
    }
  }

  void _playStaticSound() {
    final sfx = _sfx;
    final path = _staticSoundPath;
    if (sfx == null ||
        path == null ||
        !settings.staticSound ||
        settings.muted) {
      return;
    }
    unawaited(() async {
      try {
        await sfx.setVolume(settings.volume * 0.5);
        await sfx.open(Media(path), play: true);
      } catch (_) {}
    }());
  }

  void _stopStaticSound() {
    final sfx = _sfx;
    if (sfx != null) unawaited(sfx.stop());
  }

  // ---------------------------------------------------------------------------
  // Settings

  void updateSettings(void Function(AppSettings s) change) {
    change(settings);
    _configureEngines();
    store.scheduleSave();
    notifyListeners();
  }

  void updateChannel(Channel c, void Function(ChannelOverride o) change) {
    change(settings.overrideFor(c.folderName));
    _configureEngines();
    store.scheduleSave();
    notifyListeners();
  }

  /// Starts a channel over from its first video.
  Future<void> restartChannel(Channel c) async {
    final engine = _engines[c.folderName];
    if (engine == null) return;
    final watching = channel?.folderName == c.folderName;
    engine.restart();
    // Start at the very beginning of the first video, not a random spot.
    engine.advance();
    engine.state.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    store.scheduleSave();
    if (watching) {
      nowPlaying = null;
      await tuneTo(c.number, withStatic: false);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Guide

  /// Works out what's on every channel right now.
  Future<void> refreshGuide() async {
    _recordProgress();
    for (final c in channels) {
      if (channel?.folderName == c.folderName) continue;
      final engine = _engines[c.folderName];
      if (engine == null || !engine.hasContent) continue;
      await _bringUpToDate(engine, c.folderName);
    }
    notifyListeners();
  }

  NowOn nowOn(Channel c) {
    final engine = _engines[c.folderName];
    final item = engine?.state.current;
    if (engine == null || item == null) {
      return (title: null, commercial: false, remaining: null);
    }
    final watching = channel?.folderName == c.folderName;
    final position = watching
        ? _position
        : Duration(milliseconds: engine.state.positionMs);
    final length = store.durations[item.path];
    final remaining = length == null
        ? null
        : Duration(milliseconds: max(0, length - position.inMilliseconds));
    return (
      title: item.isCommercial ? null : titleFromPath(item.path),
      commercial: item.isCommercial,
      remaining: remaining,
    );
  }

  bool isShuffled(Channel c) => settings.shuffleFor(c.folderName);

  @override
  void dispose() {
    _recordProgress();
    unawaited(store.saveNow());
    _disposed = true;
    _osdTimer?.cancel();
    _volumeTimer?.cancel();
    _digitTimer?.cancel();
    _progressTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _troubleTimer?.cancel();
    unawaited(player.dispose());
    unawaited(_sfx?.dispose());
    super.dispose();
  }
}
