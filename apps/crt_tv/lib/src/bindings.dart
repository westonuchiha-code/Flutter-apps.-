import 'package:flutter/services.dart';

import 'gamepad.dart';
import 'models.dart';

/// Everything a key or controller button can be set to do.
enum TvAction {
  channelUp,
  channelDown,
  volumeUp,
  volumeDown,
  pause,
  lastChannel,
  mute,
  restart,
  subtitles,
  audioTrack,
  info,
  guide,
  videoOnly,
  fullscreen,
  settings,
  themes,
  power,
}

extension TvActionInfo on TvAction {
  String get label => switch (this) {
    TvAction.channelUp => 'Channel up',
    TvAction.channelDown => 'Channel down',
    TvAction.volumeUp => 'Volume up',
    TvAction.volumeDown => 'Volume down',
    TvAction.pause => 'Pause / play',
    TvAction.lastChannel => 'Last channel',
    TvAction.mute => 'Mute',
    TvAction.restart => 'Start this video over',
    TvAction.subtitles => 'Subtitles',
    TvAction.audioTrack => 'Audio track',
    TvAction.info => "What's on",
    TvAction.guide => 'Guide',
    TvAction.videoOnly => 'Video only (no cabinet)',
    TvAction.fullscreen => 'Full screen',
    TvAction.settings => 'Settings',
    TvAction.themes => 'Themes',
    TvAction.power => 'Power',
  };

  /// A few words, for the pop-up controller hints.
  String get shortLabel => switch (this) {
    TvAction.channelUp => 'Channel +',
    TvAction.channelDown => 'Channel −',
    TvAction.volumeUp => 'Volume +',
    TvAction.volumeDown => 'Volume −',
    TvAction.pause => 'Pause',
    TvAction.restart => 'Start over',
    TvAction.videoOnly => 'Video only',
    _ => label,
  };

  /// Whether holding the key or button down keeps doing it.
  bool get repeats =>
      this == TvAction.channelUp ||
      this == TvAction.channelDown ||
      this == TvAction.volumeUp ||
      this == TvAction.volumeDown;
}

/// Which key and which controller button does what. The defaults live here;
/// only the user's changes are saved, in [AppSettings].
class Bindings {
  Bindings(this._settings);

  final AppSettings _settings;

  static final Map<TvAction, List<LogicalKeyboardKey>> defaultKeys = {
    TvAction.channelUp: [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.channelUp,
    ],
    TvAction.channelDown: [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.channelDown,
    ],
    TvAction.volumeUp: [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.numpadAdd,
      LogicalKeyboardKey.audioVolumeUp,
    ],
    TvAction.volumeDown: [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.numpadSubtract,
      LogicalKeyboardKey.audioVolumeDown,
    ],
    TvAction.pause: [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.mediaPlayPause,
    ],
    TvAction.lastChannel: [
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.backspace,
    ],
    TvAction.mute: [
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.audioVolumeMute,
    ],
    TvAction.restart: [LogicalKeyboardKey.keyR],
    TvAction.subtitles: [LogicalKeyboardKey.keyC],
    TvAction.audioTrack: [LogicalKeyboardKey.keyA],
    TvAction.info: [LogicalKeyboardKey.keyI],
    TvAction.guide: [LogicalKeyboardKey.keyG],
    TvAction.videoOnly: [LogicalKeyboardKey.keyV],
    TvAction.fullscreen: [LogicalKeyboardKey.keyF, LogicalKeyboardKey.f11],
    TvAction.settings: [LogicalKeyboardKey.keyS],
    TvAction.themes: [LogicalKeyboardKey.keyT],
    TvAction.power: [LogicalKeyboardKey.keyP, LogicalKeyboardKey.power],
  };

  static const Map<TvAction, PadButton> defaultPad = {
    TvAction.channelUp: PadButton.up,
    TvAction.channelDown: PadButton.down,
    TvAction.volumeUp: PadButton.right,
    TvAction.volumeDown: PadButton.left,
    TvAction.pause: PadButton.south,
    TvAction.lastChannel: PadButton.east,
    TvAction.mute: PadButton.west,
    TvAction.restart: PadButton.north,
    TvAction.subtitles: PadButton.l3,
    TvAction.info: PadButton.l1,
    TvAction.guide: PadButton.r1,
    TvAction.videoOnly: PadButton.l2,
    TvAction.fullscreen: PadButton.r2,
    TvAction.settings: PadButton.start,
    TvAction.themes: PadButton.select,
    TvAction.power: PadButton.r3,
  };

  static const _noKey = 0;
  static const _noButton = '';

  /// Keys the TV always keeps for itself: channel numbers, Enter to confirm
  /// them, Esc to leave full screen and F1 for the controller hints.
  static bool isReserved(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    final isDigit = RegExp(r'^(Numpad )?[0-9]$').hasMatch(label);
    return isDigit ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.f1;
  }

  List<LogicalKeyboardKey> keysFor(TvAction action) {
    final saved = _settings.keyOverrides[action.name];
    if (saved == null) return defaultKeys[action]!;
    if (saved == _noKey) return const [];
    return [
      LogicalKeyboardKey.findKeyByKeyId(saved) ?? LogicalKeyboardKey(saved),
    ];
  }

  PadButton? padFor(TvAction action) {
    final saved = _settings.padOverrides[action.name];
    if (saved == null) return defaultPad[action];
    for (final button in PadButton.values) {
      if (button.name == saved) return button;
    }
    return null;
  }

  TvAction? actionForKey(LogicalKeyboardKey key) {
    for (final action in TvAction.values) {
      if (keysFor(action).contains(key)) return action;
    }
    return null;
  }

  TvAction? actionForPad(PadButton button) {
    for (final action in TvAction.values) {
      if (padFor(action) == button) return action;
    }
    return null;
  }

  bool get isCustom =>
      _settings.keyOverrides.isNotEmpty || _settings.padOverrides.isNotEmpty;

  /// Gives [key] to [action]. Returns the action that was left with no key
  /// at all because of it, if any.
  TvAction? bindKey(TvAction action, LogicalKeyboardKey key) {
    TvAction? emptied;
    for (final other in TvAction.values) {
      if (other == action) continue;
      final keys = keysFor(other);
      if (!keys.contains(key)) continue;
      final rest = keys.where((k) => k != key).toList();
      _settings.keyOverrides[other.name] = rest.isEmpty
          ? _noKey
          : rest.first.keyId;
      if (rest.isEmpty) emptied = other;
    }
    _settings.keyOverrides[action.name] = key.keyId;
    return emptied;
  }

  /// Gives [button] to [action]. Returns the action that lost it, if any.
  TvAction? bindPad(TvAction action, PadButton button) {
    TvAction? emptied;
    for (final other in TvAction.values) {
      if (other != action && padFor(other) == button) {
        _settings.padOverrides[other.name] = _noButton;
        emptied = other;
      }
    }
    _settings.padOverrides[action.name] = button.name;
    return emptied;
  }

  void resetAll() {
    _settings.keyOverrides.clear();
    _settings.padOverrides.clear();
  }

  /// "Arrow Up", "Space", "M".
  static String keyName(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space) return 'Space';
    final label = key.keyLabel.trim();
    return label.isNotEmpty ? label : (key.debugName ?? 'Key ${key.keyId}');
  }
}
