import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:pad_input/pad_input.dart';

import '../bindings.dart';
import '../folder_browser.dart';
import '../languages.dart';
import '../models.dart';
import '../tv_controller.dart';
import '../season.dart';
import 'skins.dart';
import 'type_path.dart';

/// One line of an on-screen menu.
sealed class OsdRow {
  const OsdRow(this.label);

  final String label;
}

/// Plain text that the cursor skips.
class OsdInfo extends OsdRow {
  const OsdInfo(super.label);
}

/// Does something, or opens another menu, when selected.
class OsdLink extends OsdRow {
  const OsdLink(super.label, this.onSelect, {this.value = ''});

  final String value;
  final VoidCallback onSelect;
}

/// A setting with a few named values; left and right step through them.
class OsdChoice extends OsdRow {
  const OsdChoice(super.label, this.value, this.onChange);

  final String value;
  final void Function(int delta) onChange;
}

/// A setting shown as a bar; left and right lower and raise it.
class OsdMeter extends OsdRow {
  const OsdMeter(super.label, this.fraction, this.onChange);

  final double fraction;
  final void Function(int delta) onChange;
}

class OsdPage {
  const OsdPage(this.title, this.rows);

  final String title;

  /// Built fresh every time, so the menu always shows current values.
  final List<OsdRow> Function() rows;
}

class _Level {
  _Level(this.page);

  final OsdPage page;
  int cursor = 0;
}

/// A menu drawn on the picture like a mid-90s set: a short list, one
/// highlighted line, up/down to move, left/right to change. This part knows
/// nothing about the TV, only how a menu behaves.
class OsdMenuCore extends ChangeNotifier {
  final List<_Level> _stack = [];
  Timer? _noticeTimer;
  Timer? _captureTimer;

  /// Whether the last input came from a controller (for the hint line).
  bool usingPad = false;

  /// A short message under the list, such as what a rebind displaced.
  String? notice;

  /// The action waiting for a new key or button, if any.
  TvAction? captureAction;
  bool capturePad = false;

  static const padCapturePatience = Duration(seconds: 8);

  bool get isOpen => _stack.isNotEmpty;
  bool get capturing => captureAction != null;
  String get title => _stack.last.page.title;

  List<OsdRow> get rows => [
    ..._stack.last.page.rows(),
    OsdLink(_stack.length > 1 ? 'BACK' : 'CLOSE MENU', back),
  ];

  int get cursor {
    final level = _stack.last;
    final list = rows;
    if (level.cursor >= list.length) level.cursor = list.length - 1;
    if (list[level.cursor] is OsdInfo) {
      level.cursor = list.indexWhere((r) => r is! OsdInfo);
    }
    return level.cursor;
  }

  void open(OsdPage page) {
    _stack
      ..clear()
      ..add(_Level(page));
    notice = null;
    notifyListeners();
  }

  void push(OsdPage page) {
    _stack.add(_Level(page));
    notifyListeners();
  }

  void back() {
    if (_stack.isEmpty) return;
    _stack.removeLast();
    notice = null;
    notifyListeners();
  }

  void close() {
    _stack.clear();
    cancelCapture();
    notifyListeners();
  }

  void move(int delta) {
    if (!isOpen) return;
    final list = rows;
    var index = cursor;
    for (var i = 0; i < list.length; i++) {
      index = (index + delta) % list.length;
      if (list[index] is! OsdInfo) break;
    }
    _stack.last.cursor = index;
    notifyListeners();
  }

  void change(int delta) {
    if (!isOpen) return;
    switch (rows[cursor]) {
      case OsdChoice(:final onChange) || OsdMeter(:final onChange):
        onChange(delta);
      case OsdLink() || OsdInfo():
        break;
    }
    notifyListeners();
  }

  void select() {
    if (!isOpen) return;
    switch (rows[cursor]) {
      case OsdLink(:final onSelect):
        onSelect();
      case OsdChoice(:final onChange):
        onChange(1);
      case OsdMeter() || OsdInfo():
        break;
    }
    notifyListeners();
  }

  void hover(int index) {
    if (!isOpen ||
        capturing ||
        rows[index] is OsdInfo ||
        _stack.last.cursor == index) {
      return;
    }
    _stack.last.cursor = index;
    notifyListeners();
  }

  void tap(int index) {
    if (!isOpen || capturing || rows[index] is OsdInfo) return;
    _stack.last.cursor = index;
    select();
  }

  void flash(String text) {
    notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _captureTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Rebinding

  void startCapture(TvAction action, {required bool pad}) {
    captureAction = action;
    capturePad = pad;
    _captureTimer?.cancel();
    // With only a controller in hand there'd be no other way to cancel.
    if (pad) _captureTimer = Timer(padCapturePatience, cancelCapture);
    notifyListeners();
  }

  void cancelCapture() {
    _captureTimer?.cancel();
    if (captureAction == null) return;
    captureAction = null;
    notifyListeners();
  }

  /// Which controller's symbols to use in the hint line.
  PadKind get padKind => PadKind.xbox;

  /// What the view redraws for.
  Listenable get source => this;

  /// The menu's colours.
  OsdPalette get palette => OsdPalette.classic;
}

/// [OsdMenuCore] plus the TV's actual menus.
class OsdMenu extends OsdMenuCore {
  OsdMenu(this.tv, {required this.runDialog, this.onQuit});

  final TvController tv;

  /// Saves and closes the program. Null where the system does that itself
  /// (phones).
  final Future<void> Function()? onQuit;

  /// Runs something that needs a system window (the folder picker).
  final Future<void> Function(Future<void> Function(BuildContext context) body)
  runDialog;

  @override
  PadKind get padKind => tv.padKind;

  @override
  Listenable get source => Listenable.merge([this, tv]);

  @override
  OsdPalette get palette => OsdPalette.of(tv.settings.skin);

  static final _modifier = RegExp('Shift|Control|Alt|Meta|Caps Lock|Fn');

  void captureKey(LogicalKeyboardKey key) {
    final action = captureAction;
    if (action == null) return;
    if (key == LogicalKeyboardKey.escape) {
      cancelCapture();
    } else if (capturePad || _modifier.hasMatch(key.keyLabel)) {
      return;
    } else if (Bindings.isReserved(key)) {
      flash(
        '${Bindings.keyName(key).toUpperCase()} IS KEPT FOR THE TV. TRY ANOTHER.',
      );
    } else {
      TvAction? emptied;
      tv.updateSettings((_) => emptied = tv.bindings.bindKey(action, key));
      cancelCapture();
      _noteEmptied(emptied, 'KEY');
    }
  }

  void capturePadButton(PadButton button) {
    final action = captureAction;
    if (action == null || !capturePad) return;
    TvAction? emptied;
    tv.updateSettings((_) => emptied = tv.bindings.bindPad(action, button));
    cancelCapture();
    _noteEmptied(emptied, 'BUTTON');
  }

  void _noteEmptied(TvAction? emptied, String what) {
    if (emptied != null) {
      flash('${emptied.label.toUpperCase()} NOW HAS NO $what');
    }
  }

  // ---------------------------------------------------------------------------
  // The menus

  static String _onOff(bool on) => on ? 'ON' : 'OFF';

  static T _step<T>(List<T> values, T current, int delta) =>
      values[(values.indexOf(current) + delta) % values.length];

  static String _channelLine(Channel c) =>
      '${c.number.toString().padLeft(2, '0')} ${c.label.toUpperCase()}';

  OsdPage mainPage() => OsdPage(
    'MENU',
    () => [
      OsdLink('GUIDE', () => push(guidePage()), value: '►'),
      OsdLink('PICTURE', () => push(picturePage()), value: '►'),
      OsdLink('SOUND & SUBTITLES', () => push(tracksPage()), value: '►'),
      OsdLink('CHANNELS', () => push(channelsPage()), value: '►'),
      OsdLink('CONTROLS', () => push(controlsPage()), value: '►'),
      OsdLink('THEME', () => push(themePage()), value: '►'),
      OsdLink('TV FOLDER', () => push(folderPage()), value: '►'),
      if (onQuit != null) OsdLink('QUIT CRT TV', () => unawaited(onQuit!())),
    ],
  );

  OsdPage guidePage() {
    unawaited(tv.refreshGuide().whenComplete(notifyListeners));
    return OsdPage('GUIDE', () {
      if (tv.channels.isEmpty) return const [OsdInfo('NO CHANNELS YET')];
      return [
        for (final c in tv.channels)
          OsdLink(_channelLine(c), () {
            unawaited(tv.tuneTo(c.number));
            close();
          }, value: _nowLine(c)),
      ];
    });
  }

  String _nowLine(Channel c) {
    if (c.programs.isEmpty && tv.commercialsFor(c).isEmpty) return 'NO VIDEOS';
    final now = tv.nowOn(c);
    if (now.commercial) return 'COMMERCIALS';
    return (now.title ?? '').toUpperCase();
  }

  OsdPage picturePage() => OsdPage('PICTURE', () {
    final s = tv.settings;
    return [
      OsdMeter('VOLUME', s.muted ? 0 : s.volume / 100, tv.volumeStep),
      OsdChoice(
        'TUBE LOOK',
        s.crtEffect.name.toUpperCase(),
        (d) => tv.updateSettings(
          (s) => s.crtEffect = _step(CrtEffect.values, s.crtEffect, d),
        ),
      ),
      OsdChoice(
        'WIDE VIDEO',
        switch (s.videoFit) {
          VideoFit.fit => 'LETTERBOX',
          VideoFit.zoom => 'ZOOM',
          VideoFit.stretch => 'STRETCH',
        },
        (d) => tv.updateSettings(
          (s) => s.videoFit = _step(VideoFit.values, s.videoFit, d),
        ),
      ),
      OsdChoice(
        'CHANNEL STATIC',
        _onOff(s.staticOnChange),
        (_) => tv.updateSettings((s) => s.staticOnChange = !s.staticOnChange),
      ),
      OsdChoice(
        'STATIC SOUND',
        _onOff(s.staticSound),
        (_) => tv.updateSettings((s) => s.staticSound = !s.staticSound),
      ),
      OsdChoice(
        'SHOW TITLES',
        _onOff(s.showTitles),
        (_) => tv.updateSettings((s) => s.showTitles = !s.showTitles),
      ),
    ];
  });

  OsdPage tracksPage() => OsdPage('SOUND & SUBTITLES', () {
    final s = tv.settings;
    // '' first: no preference.
    final codes = ['', for (final language in kLanguages) language.code];
    String name(String code, String none) =>
        languageByCode(code)?.name.toUpperCase() ?? none;
    void save(void Function(AppSettings s) change) {
      tv.updateSettings(change);
      tv.applyTrackDefaults();
    }

    return [
      const OsdInfo('THIS VIDEO'),
      OsdChoice('AUDIO TRACK', tv.audioTrackLabel, tv.stepAudioTrack),
      OsdChoice('SUBTITLES', tv.subtitleTrackLabel, tv.stepSubtitleTrack),
      const OsdInfo('EVERY VIDEO'),
      OsdChoice('LEVEL VOLUME', _onOff(s.levelSound), (_) {
        tv.updateSettings((s) => s.levelSound = !s.levelSound);
        tv.applyLeveling();
      }),
      OsdChoice(
        'PREFERRED AUDIO',
        name(s.audioLanguage, 'FILE DEFAULT'),
        (d) => save((s) => s.audioLanguage = _step(codes, s.audioLanguage, d)),
      ),
      OsdChoice(
        'SHOW SUBTITLES',
        switch (s.subtitleMode) {
          SubtitleMode.fileDefault => 'FILE DEFAULT',
          SubtitleMode.off => 'OFF',
          SubtitleMode.on => 'ON',
          SubtitleMode.auto => 'IF AUDIO DIFFERS',
        },
        (d) => save(
          (s) => s.subtitleMode = _step(SubtitleMode.values, s.subtitleMode, d),
        ),
      ),
      OsdChoice(
        'SUBTITLE LANGUAGE',
        name(s.subtitleLanguage, 'ANY'),
        (d) => save(
          (s) => s.subtitleLanguage = _step(codes, s.subtitleLanguage, d),
        ),
      ),
    ];
  });

  OsdPage channelsPage() => OsdPage('CHANNELS', () {
    final s = tv.settings;
    return [
      OsdChoice(
        'COMMERCIALS',
        breakLabel(s.commercialsPerBreak).toUpperCase(),
        (d) => tv.updateSettings(
          (s) => s.commercialsPerBreak = _step(
            kBreakChoices,
            s.commercialsPerBreak,
            d,
          ),
        ),
      ),
      OsdChoice(
        'KEEP PLAYING',
        _onOff(s.liveMode),
        (_) => tv.updateSettings((s) => s.liveMode = !s.liveMode),
      ),
      OsdChoice(
        'SEASONAL CHANNELS',
        s.seasonalAlways ? 'ALWAYS ON' : 'IN SEASON',
        (_) => tv.updateSettings((s) => s.seasonalAlways = !s.seasonalAlways),
      ),
      // Every channel, on the air or not, so seasonal ones can be set up.
      for (final c in tv.library?.channels ?? const <Channel>[])
        OsdLink(
          _channelLine(c),
          () => push(channelPage(c)),
          value: c.months.isEmpty ? '►' : '${seasonLabel(c.months)} ►',
        ),
    ];
  });

  OsdPage channelPage(Channel c) => OsdPage(_channelLine(c), () {
    final perBreak = tv.settings.overrides[c.folderName]?.commercialsPerBreak;
    final choices = <int?>[null, ...kBreakChoices];
    return [
      if (c.months.isNotEmpty) OsdInfo('ON THE AIR: ${seasonLabel(c.months)}'),
      OsdInfo(
        '${c.programs.length} VIDEOS, '
        '${c.commercials.isNotEmpty ? '${c.commercials.length} OWN COMMERCIALS' : 'MAIN COMMERCIALS'}',
      ),
      OsdChoice(
        'SHUFFLE',
        _onOff(tv.isShuffled(c)),
        (_) => tv.updateChannel(c, (o) => o.shuffle = !o.shuffle),
      ),
      OsdChoice(
        'COMMERCIALS',
        perBreak == null ? 'MAIN SETTING' : breakLabel(perBreak).toUpperCase(),
        (d) => tv.updateChannel(
          c,
          (o) => o.commercialsPerBreak = _step(choices, perBreak, d),
        ),
      ),
      OsdLink('START CHANNEL OVER', () {
        unawaited(tv.restartChannel(c));
        flash('BACK TO THE FIRST VIDEO');
      }),
    ];
  });

  OsdPage controlsPage() => OsdPage(
    'CONTROLS',
    () => [
      OsdInfo('CONTROLLER: ${tv.padStatus}'),
      OsdLink('KEYBOARD', () => push(_bindingsPage(pad: false)), value: '►'),
      OsdLink('CONTROLLER', () => push(_bindingsPage(pad: true)), value: '►'),
      OsdLink('RESET TO DEFAULTS', () {
        tv.updateSettings((_) => tv.bindings.resetAll());
        flash('CONTROLS RESET');
      }),
      const OsdInfo('NUMBER KEYS, ENTER, ESC AND F1 STAY AS THEY ARE'),
    ],
  );

  OsdPage _bindingsPage({required bool pad}) =>
      OsdPage(pad ? 'CONTROLLER' : 'KEYBOARD', () {
        final b = tv.bindings;
        String value(TvAction action) {
          if (pad) {
            final button = b.padFor(action);
            return button == null
                ? 'NOT SET'
                : padLabel(button, tv.padKind).toUpperCase();
          }
          final keys = b.keysFor(action);
          return keys.isEmpty
              ? 'NOT SET'
              : keys.take(2).map(Bindings.keyName).join(', ').toUpperCase();
        }

        return [
          for (final action in TvAction.values)
            OsdLink(
              action.label.toUpperCase(),
              () => startCapture(action, pad: pad),
              value: value(action),
            ),
        ];
      });

  OsdPage themePage() => OsdPage(
    'THEME',
    () => [
      for (final skin in const [
        // Real sets by year, then the fantasy ones, then the plain ones.
        SkinStyle.boombox,
        SkinStyle.portable,
        SkinStyle.combo,
        SkinStyle.crt95,
        SkinStyle.clear,
        SkinStyle.cyberpunk,
        SkinStyle.wasteland,
        SkinStyle.atomic,
        SkinStyle.memphis,
        SkinStyle.wood,
        SkinStyle.black,
        SkinStyle.silver,
        SkinStyle.none,
      ])
        OsdLink(
          skin.label.toUpperCase(),
          () => tv.updateSettings((s) => s.skin = skin),
          value: tv.settings.skin == skin ? '●' : '',
        ),
    ],
  );

  static const _browseTitle = 'CHOOSE FOLDER';

  /// One folder of the computer, for walking to the TV folder with just
  /// the arrow keys or a controller. '' is the list of drives on Windows.
  OsdPage browsePage(String path) => OsdPage(_browseTitle, () {
    final windows = Platform.isWindows;
    // Android: the top is internal storage and any SD cards.
    final roots = tv.android ? tv.storageRoots : const <String>[];
    final folders = listFolders(path, roots: roots);
    final parent = parentFolder(path, windows: windows, roots: roots);
    final channels = folders?.where(isChannelFolderName).length ?? 0;
    return [
      OsdInfo(
        path.isEmpty
            ? (tv.android ? 'THIS DEVICE' : 'THIS COMPUTER')
            : tv.folderLabel(path).toUpperCase(),
      ),
      if (path.isNotEmpty)
        OsdLink(
          channels == 0
              ? 'USE THIS FOLDER'
              : 'USE THIS FOLDER ($channels CHANNELS)',
          () => _useFolder(path),
        ),
      if (parent != null)
        OsdLink('UP ONE LEVEL', () => push(browsePage(parent)), value: '▲'),
      if (folders == null) const OsdInfo("CAN'T READ THIS FOLDER"),
      if (folders != null && folders.isEmpty)
        const OsdInfo('NO FOLDERS IN HERE'),
      for (final name in folders ?? const <String>[])
        OsdLink(
          (path.isEmpty ? tv.folderLabel(name) : name).toUpperCase(),
          () => push(
            browsePage(
              path.isEmpty ? name : childFolder(path, name, windows: windows),
            ),
          ),
          value: '►',
        ),
    ];
  });

  void _useFolder(String path) {
    unawaited(tv.loadLibrary(path));
    // Leave the browser, however deep it went.
    while (_stack.isNotEmpty && _stack.last.page.title == _browseTitle) {
      _stack.removeLast();
    }
    if (_stack.isNotEmpty) flash('READING THE NEW FOLDER');
    notifyListeners();
  }

  OsdPage folderPage() => OsdPage('TV FOLDER', () {
    final lib = tv.library;
    final path = tv.settings.libraryPath;
    final defaultFolder = tv.android ? tv.defaultFolder : null;
    return [
      OsdInfo(
        path == null ? 'NOT CHOSEN YET' : tv.folderLabel(path).toUpperCase(),
      ),
      if (tv.permissionProblem case final problem?) OsdInfo(problem),
      if (tv.android && !tv.allFilesAccess)
        OsdLink(
          'ALLOW ACCESS TO FILES',
          () => unawaited(tv.requestAllFilesAccess()),
          value: '►',
        ),
      OsdInfo(
        lib == null
            ? (tv.scanning ? 'READING...' : '')
            : '${lib.channels.length} CHANNELS, ${lib.videoCount} VIDEOS',
      ),
      if (tv.probeTotal > 0 && tv.probedCount < tv.probeTotal)
        OsdInfo('CHECKING LENGTHS ${tv.probedCount} OF ${tv.probeTotal}'),
      OsdLink(
        'CHOOSE FOLDER',
        () => push(
          browsePage(
            browseStart(
              path,
              roots: tv.android ? tv.storageRoots : const [],
              defaultFolder: defaultFolder,
            ),
          ),
        ),
        value: '►',
      ),
      if (defaultFolder != null && tv.allFilesAccess && path != defaultFolder)
        OsdLink('USE ${tv.folderLabel(defaultFolder).toUpperCase()}', () {
          unawaited(tv.useDefaultFolder());
          flash('READING THE NEW FOLDER');
        }),
      if (!tv.android && !Platform.isIOS)
        OsdLink(
          'TYPE A PATH',
          () => unawaited(runDialog((context) => typeLibraryPath(context, tv))),
        ),
      OsdLink('RESCAN', () {
        unawaited(tv.rescan());
        flash('READING THE FOLDER AGAIN');
      }),
      if (lib != null)
        for (final warning in lib.warnings.take(2))
          OsdInfo(warning.toUpperCase()),
    ];
  });
}

/// Draws the open menu over the picture.
class OsdMenuView extends StatelessWidget {
  const OsdMenuView({super.key, required this.menu});

  final OsdMenuCore menu;

  Color get _panel => menu.palette.panel;
  Color get _ink => menu.palette.ink;
  Color get _accent => menu.palette.accent;
  Color get _bar => menu.palette.bar;
  Color get _barInk => menu.palette.barInk;

  static TextStyle _style(double size, Color color) => TextStyle(
    color: color,
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: size * 0.06,
    height: 1.15,
    fontFamily: 'monospace',
    fontFamilyFallback: const [
      'Consolas',
      'Courier New',
      'DejaVu Sans Mono',
      'Menlo',
    ],
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: menu.source,
      builder: (context, _) {
        if (!menu.isOpen) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, box) {
            final h = box.maxHeight;
            final size = max(10.0, h * 0.04);
            final rowHeight = size * 1.6;
            final rows = menu.rows;
            final cursor = menu.cursor;
            // A page can have fewer rows than the smallest window (a folder
            // with one entry, say), so the window never exceeds the rows.
            final visible = min(
              rows.length,
              max(4, (h * 0.58 / rowHeight).floor()),
            );
            final first = (cursor - visible ~/ 2)
                .clamp(0, max(0, rows.length - visible))
                .toInt();
            final width = min(box.maxWidth * 0.86, h * 1.12);

            return Center(
              child: Container(
                width: width,
                padding: EdgeInsets.all(size * 0.7),
                decoration: BoxDecoration(
                  color: _panel,
                  border: Border.all(color: _ink, width: max(1.5, size * 0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            menu.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _style(size * 1.2, _accent),
                          ),
                        ),
                        if (first > 0)
                          Text('▲', style: _style(size * 0.8, _ink)),
                        if (first + visible < rows.length)
                          Text(' ▼', style: _style(size * 0.8, _ink)),
                      ],
                    ),
                    Container(
                      height: max(1.5, size * 0.1),
                      margin: EdgeInsets.symmetric(vertical: size * 0.4),
                      color: _ink,
                    ),
                    if (menu.capturing)
                      _capturePrompt(size, rowHeight * visible)
                    else
                      for (var i = first; i < first + visible; i++)
                        _row(rows[i], i, i == cursor, size, rowHeight),
                    SizedBox(height: size * 0.5),
                    Text(
                      menu.notice ?? _hints(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _style(
                        size * 0.72,
                        menu.notice != null
                            ? _accent
                            : _ink.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _hints() {
    if (menu.usingPad) {
      final kind = menu.padKind;
      return 'D-PAD MOVE/CHANGE   ${padLabel(PadButton.south, kind)} SELECT   '
          '${padLabel(PadButton.east, kind)} BACK';
    }
    return '↑↓ MOVE   ←→ CHANGE   ENTER SELECT   ESC BACK';
  }

  Widget _capturePrompt(double size, double height) {
    final action = menu.captureAction!;
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            menu.capturePad ? 'PRESS A CONTROLLER BUTTON' : 'PRESS A KEY',
            style: _style(size * 1.1, _accent),
          ),
          SizedBox(height: size * 0.5),
          Text(
            'FOR ${action.label.toUpperCase()}',
            textAlign: TextAlign.center,
            style: _style(size, _ink),
          ),
          SizedBox(height: size),
          Text(
            menu.capturePad
                ? 'CANCELS BY ITSELF AFTER ${OsdMenuCore.padCapturePatience.inSeconds} SECONDS'
                : 'ESC CANCELS',
            style: _style(size * 0.72, _ink.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }

  Widget _row(
    OsdRow row,
    int index,
    bool selected,
    double size,
    double rowHeight,
  ) {
    if (row is OsdInfo) {
      return SizedBox(
        height: rowHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.4),
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _style(size * 0.78, _ink.withValues(alpha: 0.75)),
            ),
          ),
        ),
      );
    }
    final ink = selected ? _barInk : _ink;
    final Widget value = switch (row) {
      OsdMeter(:final fraction) => _meter(fraction, size, ink),
      OsdChoice(:final value) => Text(
        selected ? '◄ $value ►' : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _style(size, ink),
      ),
      OsdLink(:final value) => Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: _style(size, ink),
      ),
      OsdInfo() => const SizedBox.shrink(),
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // Only real mouse movement moves the highlight; a mouse resting here
      // must not pull it back from the keyboard or controller.
      onHover: (_) => menu.hover(index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => menu.tap(index),
        child: Container(
          height: rowHeight,
          color: selected ? _bar : null,
          padding: EdgeInsets.symmetric(horizontal: size * 0.4),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(size, ink),
                ),
              ),
              SizedBox(width: size),
              Expanded(
                flex: 2,
                child: Align(alignment: Alignment.centerRight, child: value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meter(double fraction, double size, Color ink) {
    const segments = 16;
    final lit = (fraction.clamp(0.0, 1.0) * segments).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < segments; i++)
          Container(
            width: size * 0.4,
            height: size * 0.9,
            margin: EdgeInsets.only(left: size * 0.13),
            color: i < lit ? ink : ink.withValues(alpha: 0.22),
          ),
      ],
    );
  }
}
