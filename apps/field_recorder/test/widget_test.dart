import 'dart:io';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:field_recorder/main.dart';
import 'package:field_recorder/src/editor_page.dart';
import 'package:field_recorder/src/home_page.dart';
import 'package:field_recorder/src/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Records one second of a fixed signal without a microphone.
class FakeMic extends MicRecorder {
  File? _file;
  double _secs = 0;

  @override
  double get seconds => _secs;

  @override
  Future<bool> start(
    File file, {
    int sampleRate = 48000,
    MicSource source = MicSource.unprocessed,
  }) async {
    _file = file;
    markers.clear();
    state = MicState.recording;
    notifyListeners();
    return true;
  }

  @override
  void addMarker() {
    _secs = 0.5;
    super.addMarker();
  }

  @override
  Future<WavInfo?> stop() async {
    final f = _file;
    if (f == null) return null;
    final w = await WavFileWriter.create(f, const WavFormat(sampleRate: 1000));
    await w.add(
      Int16List.fromList(List.filled(1000, 8000)).buffer.asUint8List(),
    );
    final info = await w.close();
    _file = null;
    state = MicState.idle;
    notifyListeners();
    return info;
  }
}

class SilentPlayer extends ClipPlayer {
  @override
  Future<void> load(File file) async {}
  @override
  Future<void> play({double from = 0, double? to}) async {}
}

void main() {
  test('trim keeps and shifts markers inside the range', () {
    final r = trimMarkers([0.5, 2.0, 3.25, 9.0], 1.0, 4.0);
    expect(r.markers, [1.0, 2.25]);
    expect(parseTags(' Birds, rain,,birds '), ['birds', 'rain']);
    expect(defaultName(DateTime(2026, 11, 23, 9, 5)), 'Recording 23 Nov 09:05');
  });

  test('leftover takes are listed, edit scratch is not', () async {
    final dir = Directory.systemTemp.createTempSync('takes_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final takes = Takes(dir);
    expect(await takes.leftovers(), isEmpty);
    await takes.newFile().create(recursive: true);
    await takes.scratchFile().create(recursive: true);
    expect(await takes.leftovers(), hasLength(1));
  });

  testWidgets('record, mark, stop, save to the locker', (tester) async {
    createPlayer = SilentPlayer.new;
    final dir = Directory.systemTemp.createTempSync('rec_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final takes = Takes(Directory('${dir.path}/takes'));
    final mic = FakeMic();
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> io(Finder until) async {
      for (var i = 0; i < 100 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(until, findsWidgets);
    }

    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(takes: takes, recorder: mic),
      ),
    );
    await io(find.textContaining('No recordings yet'));

    await tester.tap(find.byTooltip('Record'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Record (R)'));
    await tester.pump();
    expect(find.textContaining('Recording ·'), findsOneWidget);
    await tester.tap(find.byTooltip('Marker (M)'));
    await tester.pump();
    expect(find.text('Recording · 1 markers'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop (R)'));
    await io(find.text('Save to Asset Locker'));
    expect(find.text('Length 0:01.0'), findsOneWidget);
    expect(find.widgetWithText(InputChip, '0:00.5'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Tags'),
      'Test, birds',
    );

    await tester.tap(find.text('Save to Asset Locker'));
    await io(find.text('Recordings'));
    final saved = (await tester.runAsync(
      () => services.locker.list(type: AssetType.recording),
    ))!;
    expect(saved, hasLength(1));
    expect(saved.single.tags, ['test', 'birds']);
    expect(saved.single.extra['markers'], [0.5]);
    expect(saved.single.extra['seconds'], 1.0);
    expect(saved.single.hasThumbnail, isTrue);
    expect(await tester.runAsync(() => takes.leftovers()), isEmpty);
    await io(find.text(saved.single.name));
    await tester.pump(const Duration(seconds: 1));
  });
}
