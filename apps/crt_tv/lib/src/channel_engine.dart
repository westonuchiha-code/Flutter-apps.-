import 'dart:math';

/// One thing a channel plays: a show/movie, or a commercial.
class QueueItem {
  const QueueItem(this.path, {this.isCommercial = false});

  final String path;
  final bool isCommercial;

  Map<String, Object?> toJson() => {'p': path, if (isCommercial) 'c': true};

  static QueueItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['p'];
    if (path is! String) return null;
    return QueueItem(path, isCommercial: json['c'] == true);
  }
}

/// Where a channel is in its schedule. Saved to disk so channels pick up
/// where they were after the app restarts.
class ChannelState {
  /// Shows and movies in play order (shuffled for shuffle channels).
  List<String> order = [];

  /// Index in [order] of the most recently scheduled program. -1 = none yet.
  int cursor = -1;

  /// What is on right now.
  QueueItem? current;

  /// Already-decided next items (the rest of a commercial break, then the
  /// next program).
  List<QueueItem> upcoming = [];

  /// How far into [current] the channel was at [updatedAtMs].
  int positionMs = 0;

  /// Wall-clock time (ms since epoch) when [positionMs] was recorded.
  /// 0 = the channel has never been watched.
  int updatedAtMs = 0;

  bool get neverWatched => updatedAtMs == 0;

  void reset() {
    order = [];
    cursor = -1;
    current = null;
    upcoming = [];
    positionMs = 0;
    updatedAtMs = 0;
  }

  Map<String, Object?> toJson() => {
    'order': order,
    'cursor': cursor,
    'current': current?.toJson(),
    'upcoming': [for (final q in upcoming) q.toJson()],
    'positionMs': positionMs,
    'updatedAtMs': updatedAtMs,
  };

  static ChannelState fromJson(Object? json) {
    final state = ChannelState();
    if (json is! Map) return state;
    final order = json['order'];
    if (order is List) {
      state.order = [
        for (final p in order)
          if (p is String) p,
      ];
    }
    final cursor = json['cursor'];
    if (cursor is num) state.cursor = cursor.toInt();
    state.current = QueueItem.fromJson(json['current']);
    final upcoming = json['upcoming'];
    if (upcoming is List) {
      for (final q in upcoming) {
        final item = QueueItem.fromJson(q);
        if (item != null) state.upcoming.add(item);
      }
    }
    final pos = json['positionMs'];
    if (pos is num) state.positionMs = max(0, pos.toInt());
    final updated = json['updatedAtMs'];
    if (updated is num) state.updatedAtMs = updated.toInt();
    return state;
  }
}

/// Decides what a channel plays next: programs from its folder, with
/// commercial breaks between them.
///
/// This class has no Flutter or player code in it, so it can be unit tested.
class ChannelEngine {
  ChannelEngine(this.state, {Random? random}) : _random = random ?? Random();

  final ChannelState state;
  final Random _random;

  List<String> _programs = const [];
  List<String> _commercialPool = const [];
  bool _shuffle = false;
  int _perBreak = 0;
  bool _configured = false;

  /// Commercials not yet played in this round, so they don't repeat until
  /// every one has had a turn.
  List<String> _bag = [];
  String? _lastCommercial;

  bool get hasContent => _programs.isNotEmpty || _commercialPool.isNotEmpty;
  bool get shuffle => _shuffle;

  /// Call when the library is scanned or the channel's settings change.
  ///
  /// [commercialPool] is the channel's own commercials, or the global ones
  /// when the channel has none.
  void configure({
    required List<String> programs,
    required List<String> commercialPool,
    required bool shuffle,
    required int perBreak,
  }) {
    final shuffleChanged = _configured && shuffle != _shuffle;
    final breakChanged =
        _configured &&
        (perBreak != _perBreak || !_sameList(commercialPool, _commercialPool));

    _programs = List.unmodifiable(programs);
    _commercialPool = List.unmodifiable(commercialPool);
    _shuffle = shuffle;
    _perBreak = perBreak;
    _configured = true;

    final commercialSet = commercialPool.toSet();
    _bag = _bag.where(commercialSet.contains).toList();

    _syncOrder(reshuffle: shuffleChanged);

    // Forget queued items that were deleted, or a break planned with old settings.
    final programSet = programs.toSet();
    bool exists(QueueItem q) => q.isCommercial
        ? commercialSet.contains(q.path)
        : programSet.contains(q.path);
    state.upcoming.removeWhere(
      (q) => !exists(q) || (breakChanged && q.isCommercial),
    );
    final current = state.current;
    if (current != null && !exists(current)) {
      state.current = null;
      state.positionMs = 0;
    }
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _syncOrder({required bool reshuffle}) {
    final cursorProgram = state.cursor >= 0 && state.cursor < state.order.length
        ? state.order[state.cursor]
        : null;

    if (!_shuffle) {
      state.order = List.of(_programs);
    } else if (reshuffle || state.order.isEmpty) {
      state.order = List.of(_programs)..shuffle(_random);
    } else {
      // Keep the saved shuffle; drop deleted videos and slot new ones in
      // somewhere after the current position.
      final available = _programs.toSet();
      final kept = state.order.where(available.contains).toList();
      final keptSet = kept.toSet();
      final added = _programs.where((p) => !keptSet.contains(p)).toList()
        ..shuffle(_random);
      for (final p in added) {
        final start = cursorProgram == null
            ? 0
            : kept.indexOf(cursorProgram) + 1;
        final insertAt = start + _random.nextInt(kept.length - start + 1);
        kept.insert(insertAt, p);
      }
      state.order = kept;
    }

    if (cursorProgram != null) {
      state.cursor = state.order.indexOf(cursorProgram);
    } else {
      state.cursor = max(-1, min(state.cursor, state.order.length - 1));
    }
  }

  /// Moves to the next item and returns it (null if the channel is empty).
  QueueItem? advance() {
    final previous = state.current;
    if (state.upcoming.isEmpty) {
      _refill(afterProgram: previous != null && !previous.isCommercial);
    }
    state.current = state.upcoming.isEmpty ? null : state.upcoming.removeAt(0);
    state.positionMs = 0;
    return state.current;
  }

  void _refill({required bool afterProgram}) {
    if (afterProgram && _programs.isNotEmpty) {
      for (final c in _drawBreak()) {
        state.upcoming.add(QueueItem(c, isCommercial: true));
      }
    }
    final next = _nextProgram();
    if (next != null) {
      state.upcoming.add(QueueItem(next));
      return;
    }
    // A channel with only commercials plays them back to back.
    final c = _drawCommercial(const []);
    if (c != null) state.upcoming.add(QueueItem(c, isCommercial: true));
  }

  String? _nextProgram() {
    if (state.order.isEmpty) return null;
    var next = state.cursor + 1;
    if (next >= state.order.length) {
      next = 0;
      if (_shuffle && state.order.length > 1) {
        final last = state.order.last;
        state.order.shuffle(_random);
        if (state.order.first == last) {
          // Don't play the same video twice in a row across rounds.
          final swapWith = 1 + _random.nextInt(state.order.length - 1);
          final tmp = state.order[0];
          state.order[0] = state.order[swapWith];
          state.order[swapWith] = tmp;
        }
      }
    }
    state.cursor = next;
    return state.order[next];
  }

  int _breakLength() {
    final wanted = _perBreak == -1 ? 1 + _random.nextInt(3) : max(0, _perBreak);
    return min(wanted, _commercialPool.length);
  }

  List<String> _drawBreak() {
    final picked = <String>[];
    final count = _breakLength();
    for (var i = 0; i < count; i++) {
      final c = _drawCommercial(picked);
      if (c == null) break;
      picked.add(c);
    }
    return picked;
  }

  String? _drawCommercial(List<String> exclude) {
    if (_commercialPool.isEmpty) return null;
    if (_bag.isEmpty) {
      _bag = List.of(_commercialPool)..shuffle(_random);
      if (_bag.length > 1 && _bag.last == _lastCommercial) {
        final tmp = _bag.first;
        _bag[0] = _bag.last;
        _bag[_bag.length - 1] = tmp;
      }
    }
    for (var i = _bag.length - 1; i >= 0; i--) {
      if (!exclude.contains(_bag[i])) {
        final c = _bag.removeAt(i);
        _lastCommercial = c;
        return c;
      }
    }
    final fallback = _commercialPool
        .where((c) => !exclude.contains(c))
        .toList();
    if (fallback.isEmpty) return null;
    final c = fallback[_random.nextInt(fallback.length)];
    _lastCommercial = c;
    return c;
  }

  /// Moves the channel forward as if it had kept playing for [elapsed]
  /// while nobody was watching. [durationOf] gives each video's length.
  Future<void> catchUp(
    Duration elapsed,
    Future<Duration> Function(QueueItem item) durationOf,
  ) async {
    if (state.current == null && advance() == null) return;
    int position = state.positionMs + max<int>(0, elapsed.inMilliseconds);
    for (var steps = 0; steps < 4000; steps++) {
      final item = state.current;
      if (item == null) return;
      final length = (await durationOf(item)).inMilliseconds;
      if (length <= 0) {
        position = 0;
        break;
      }
      // Within the last 2 seconds counts as finished.
      if (position < length - 2000) break;
      position -= length;
      if (advance() == null) return;
      if (steps == 3999) position = 0;
    }
    state.positionMs = max<int>(0, position);
  }

  /// Starts the channel over from its first video.
  void restart() {
    state.reset();
    _bag = [];
    _syncOrder(reshuffle: true);
  }
}
