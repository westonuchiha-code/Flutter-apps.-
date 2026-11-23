import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const volume = SliderSetting(
  key: 'volume',
  title: 'Volume',
  defaultValue: 0.5,
  section: 'Sound',
);
const loud = BoolSetting(key: 'loud', title: 'Loud mode', section: 'Sound');

void main() {
  late Directory dir;
  late AppStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('app_shell_test');
    storage = AppStorage(dir);
  });
  tearDown(() => dir.delete(recursive: true));

  group('AppStorage', () {
    test('writes and reads back', () async {
      await storage.writeJson('a.json', {'x': 1});
      expect(await storage.readJson('a.json'), {'x': 1});
    });

    test('keeps the previous copy and recovers from a corrupt file', () async {
      await storage.writeJson('a.json', {'v': 1});
      await storage.writeJson('a.json', {'v': 2});
      await storage.file('a.json').writeAsString('{broken');
      expect(await storage.readJson('a.json'), {'v': 1});
    });

    test('missing file reads as null', () async {
      expect(await storage.readJson('nope.json'), isNull);
      expect(await storage.readBytes('nope.bin'), isNull);
    });
  });

  group('SettingsStore', () {
    test('defaults, set, save and reload', () async {
      final store = SettingsStore(storage, [volume, loud]);
      await store.load();
      expect(store.get(volume), 0.5);
      expect(store.get(loud), isFalse);
      store.set(volume, 0.8);
      store.set(loud, true);
      await store.save();
      store.dispose();

      final again = SettingsStore(storage, [volume, loud]);
      await again.load();
      expect(again.get(volume), 0.8);
      expect(again.get(loud), isTrue);
      again.dispose();
    });

    test('bad saved values fall back to defaults', () async {
      await storage.writeJson('settings.json', {
        'volume': 'loud',
        'shell.themeMode': 'purple',
      });
      final store = SettingsStore(storage, [volume, themeModeSetting]);
      await store.load();
      expect(store.get(volume), 0.5);
      expect(store.get(themeModeSetting), 'system');
      store.dispose();
    });

    test('slider values are clamped', () {
      expect(volume.decode(7), 1.0);
      expect(volume.decode(-1), 0.0);
    });
  });

  group('CrashLog', () {
    test('records, caps, reports and clears', () async {
      final log = CrashLog(storage, maxEntries: 3);
      for (var i = 0; i < 5; i++) {
        await log.record(StateError('boom $i'), StackTrace.current);
      }
      final entries = await log.entries();
      expect(entries, hasLength(3));
      expect(entries.last.error, contains('boom 4'));
      final report = await log.report('Test App', '1.0');
      expect(report, contains('Test App'));
      expect(report, contains('boom 4'));
      await log.clear();
      expect(await log.entries(), isEmpty);
    });
  });

  test('errors are published to the Asset Locker', () async {
    final services = await ShellServices.create(
      const AppShellConfig(id: 'test_app', name: 'Test App'),
      root: dir,
    );
    await services.crashLog.record(StateError('kaboom'), null);
    final reports = await services.locker.readErrorReports();
    expect(reports['test_app']?['name'], 'Test App');
    expect(
      (reports['test_app']?['entries'] as List).single['error'],
      contains('kaboom'),
    );
    await services.crashLog.clear();
    expect(await services.locker.readErrorReports(), isEmpty);
  });

  group('pages', () {
    testWidgets('settings page is generated and changes values', (
      tester,
    ) async {
      final services = (await tester.runAsync(
        () => ShellServices.create(
          const AppShellConfig(
            id: 'test_app',
            name: 'Test App',
            settings: [volume, loud],
          ),
          root: dir,
        ),
      ))!;
      await tester.pumpWidget(
        ShellApp(
          services: services,
          home: (context) =>
              Scaffold(appBar: AppBar(actions: shellActions(context))),
        ),
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Sound'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      await tester.tap(find.text('Loud mode'));
      await tester.pump();
      expect(services.settings.get(loud), isTrue);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('about page shows version and an empty error log', (
      tester,
    ) async {
      final services = (await tester.runAsync(
        () => ShellServices.create(
          const AppShellConfig(
            id: 'test_app',
            name: 'Test App',
            version: '2.3.4',
          ),
          root: dir,
        ),
      ))!;
      await tester.pumpWidget(
        ShellApp(
          services: services,
          home: (context) =>
              Scaffold(appBar: AppBar(actions: shellActions(context))),
        ),
      );
      await tester.tap(find.byTooltip('About'));
      await tester.pumpAndSettle();
      expect(find.text('Version 2.3.4'), findsOneWidget);
      await tester.tap(find.text('Error log'));
      for (
        var k = 0;
        k < 10 && find.text('No errors recorded.').evaluate().isEmpty;
        k++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('No errors recorded.'), findsOneWidget);
    });
  });
}
