import 'package:crt_tv/src/bindings.dart';
import 'package:crt_tv/src/gamepad.dart';
import 'package:crt_tv/src/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults: every action has a key and its own controller button', () {
    final b = Bindings(AppSettings());
    // Audio track is the one action without room on the controller.
    const keyboardOnly = {TvAction.audioTrack};
    for (final action in TvAction.values) {
      expect(b.keysFor(action), isNotEmpty, reason: action.name);
      expect(b.padFor(action), keyboardOnly.contains(action) ? isNull : isNotNull, reason: action.name);
    }
    expect(Bindings.defaultPad.values.toSet().length, TvAction.values.length - keyboardOnly.length);
    final allKeys = [for (final keys in Bindings.defaultKeys.values) ...keys];
    expect(allKeys.toSet().length, allKeys.length, reason: 'a key is used twice');
    expect(allKeys.where(Bindings.isReserved), isEmpty);
    expect(b.actionForKey(LogicalKeyboardKey.keyR), TvAction.restart);
    expect(b.actionForPad(PadButton.north), TvAction.restart);
    expect(b.isCustom, isFalse);
  });

  test('rebinding a key takes it from whoever had it', () {
    final b = Bindings(AppSettings());
    // M is mute's main key; mute keeps its other key.
    expect(b.bindKey(TvAction.restart, LogicalKeyboardKey.keyM), isNull);
    expect(b.actionForKey(LogicalKeyboardKey.keyM), TvAction.restart);
    expect(b.actionForKey(LogicalKeyboardKey.keyR), isNull);
    expect(b.keysFor(TvAction.mute), [LogicalKeyboardKey.audioVolumeMute]);
    // G is the guide's only key, so the guide is left with none.
    expect(b.bindKey(TvAction.info, LogicalKeyboardKey.keyG), TvAction.guide);
    expect(b.keysFor(TvAction.guide), isEmpty);
  });

  test('rebinding a controller button takes it from whoever had it', () {
    final b = Bindings(AppSettings());
    expect(b.bindPad(TvAction.restart, PadButton.south), TvAction.pause);
    expect(b.actionForPad(PadButton.south), TvAction.restart);
    expect(b.padFor(TvAction.pause), isNull);
    expect(b.actionForPad(PadButton.north), isNull);
    expect(b.bindPad(TvAction.pause, PadButton.l3), TvAction.subtitles);
    expect(b.actionForPad(PadButton.l3), TvAction.pause);
  });

  test('changes survive saving and loading, and reset clears them', () {
    final settings = AppSettings();
    final b = Bindings(settings);
    b.bindKey(TvAction.restart, LogicalKeyboardKey.keyZ);
    b.bindPad(TvAction.restart, PadButton.l3);
    b.bindKey(TvAction.info, LogicalKeyboardKey.keyG);

    final loaded = AppSettings()..loadJson(settings.toJson());
    final again = Bindings(loaded);
    expect(again.actionForKey(LogicalKeyboardKey.keyZ), TvAction.restart);
    expect(again.padFor(TvAction.restart), PadButton.l3);
    expect(again.keysFor(TvAction.guide), isEmpty);
    expect(again.isCustom, isTrue);

    again.resetAll();
    expect(again.actionForKey(LogicalKeyboardKey.keyR), TvAction.restart);
    expect(again.isCustom, isFalse);
  });

  test('number keys, Enter, Esc and F1 cannot be rebound', () {
    expect(Bindings.isReserved(LogicalKeyboardKey.digit5), isTrue);
    expect(Bindings.isReserved(LogicalKeyboardKey.numpad5), isTrue);
    expect(Bindings.isReserved(LogicalKeyboardKey.escape), isTrue);
    expect(Bindings.isReserved(LogicalKeyboardKey.enter), isTrue);
    expect(Bindings.isReserved(LogicalKeyboardKey.f1), isTrue);
    expect(Bindings.isReserved(LogicalKeyboardKey.keyK), isFalse);
  });
}
