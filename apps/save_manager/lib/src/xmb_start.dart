/// Start game from here: this app has no game library, so on Android it
/// hands the save to the XMB Frontend (an explicit intent to its
/// MainActivity), which finds the game in its library and starts it.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:save_kit/save_kit.dart';

/// The XMB Frontend's Android package and the activity that takes it.
const xmbPackage = 'com.westonuchiha.xmb_frontend';
const xmbActivity = '$xmbPackage.MainActivity';

/// The consoles the XMB starts (its Memory Card row's, in save_kit's names).
const xmbStartSystems = {'PS1', 'N64', 'SATURN', 'DC', 'GC'};

/// The intent's extras for [s]: the console, the game (the matched title,
/// the card's name for one-card-per-game consoles, or the save's own first
/// title line), its serial and file.
Map<String, String> xmbStartExtras(CardSave s) {
  final card = s.card;
  final title = s.game.isNotEmpty
      ? s.game
      : s.titleLines.isNotEmpty
      ? s.titleLines.first
      : '';
  return {
    'start_game_system': s.system,
    'start_game_title': title.trim(),
    'start_game_serial': s.serial,
    'start_game_file': s.file.isNotEmpty
        ? s.file
        : card == null
        ? ''
        : card.path.split(RegExp(r'[\\/]')).last,
  };
}

/// What to say when the XMB isn't there to start it.
const xmbMissingNotice =
    'Start game works through the XMB Frontend: install it (its Releases '
    'page) and its library starts the game';

/// Hands [s] to the XMB Frontend. Returns a notice to show, or null when
/// the XMB took it (it starts the game or says none matched).
Future<String?> startInXmb(
  CardSave s, {
  MethodChannel channel = const MethodChannel('save_manager/android'),
}) async {
  if (!Platform.isAndroid) {
    return 'Games are started from the XMB Frontend: this app manages the saves';
  }
  try {
    final r = await channel.invokeMethod<String>('startInXmb', {
      'package': xmbPackage,
      'activity': xmbActivity,
      'extras': xmbStartExtras(s),
    });
    return switch (r) {
      'ok' => null,
      'missing' => xmbMissingNotice,
      _ => 'Could not hand it to the XMB Frontend: $r',
    };
  } catch (e) {
    return 'Could not hand it to the XMB Frontend: $e';
  }
}
