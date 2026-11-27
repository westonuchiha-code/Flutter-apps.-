import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:cross_save/cross_save.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// GitHub's two device-flow endpoints, answering from a script.
class FakeGitHub {
  FakeGitHub(this.polls);

  /// What each poll of the token endpoint answers, in order.
  final List<Map<String, Object?>> polls;
  final asked = <(Uri, Map<String, String>)>[];
  final waits = <int>[];

  Future<({int status, String body})> post(
    Uri url,
    Map<String, String> form,
  ) async {
    asked.add((url, form));
    if (url == DeviceLogin.codeUrl) {
      return (
        status: 200,
        body: jsonEncode({
          'device_code': 'dev123',
          'user_code': 'WDJB-MJHT',
          'verification_uri': 'https://github.com/login/device',
          'expires_in': 900,
          'interval': 5,
        }),
      );
    }
    return (status: 200, body: jsonEncode(polls.removeAt(0)));
  }

  DeviceLogin login() => DeviceLogin(
    clientId: 'test-client',
    post: post,
    wait: (d) async => waits.add(d.inSeconds),
  );
}

const pending = {'error': 'authorization_pending'};

/// A repo that is never reached (setToken only checks a real GitHubRepo).
class NoRepo implements SaveRepo {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  test('asks for a code with the client ID and the repo scope', () async {
    final gh = FakeGitHub([]);
    final code = await gh.login().start();
    expect(code.userCode, 'WDJB-MJHT');
    expect(code.interval, 5);
    expect(gh.asked.single.$2, {'client_id': 'test-client', 'scope': 'repo'});
  });

  test('a token after authorization_pending', () async {
    final gh = FakeGitHub([
      pending,
      pending,
      {'access_token': 'gho_abc', 'token_type': 'bearer', 'scope': 'repo'},
    ]);
    final l = gh.login();
    final token = await l.waitForToken(await l.start());
    expect(token, 'gho_abc');
    expect(gh.waits, [5, 5, 5]);
    final form = gh.asked.last.$2;
    expect(gh.asked.last.$1, DeviceLogin.tokenUrl);
    expect(form['device_code'], 'dev123');
    expect(form['grant_type'], 'urn:ietf:params:oauth:grant-type:device_code');
  });

  test('slow_down waits longer from then on', () async {
    final gh = FakeGitHub([
      pending,
      {'error': 'slow_down', 'interval': 10},
      pending,
      {'error': 'slow_down'}, // no interval given: 5 s more
      {'access_token': 'gho_x'},
    ]);
    final l = gh.login();
    expect(await l.waitForToken(await l.start()), 'gho_x');
    expect(gh.waits, [5, 5, 10, 10, 15]);
  });

  test('expired and denied codes stop with a reason', () async {
    for (final (error, failure) in [
      ('expired_token', DeviceLoginFailure.expired),
      ('access_denied', DeviceLoginFailure.denied),
      ('device_flow_disabled', DeviceLoginFailure.other),
    ]) {
      final gh = FakeGitHub([
        pending,
        {'error': error},
      ]);
      final l = gh.login();
      await expectLater(
        l.waitForToken(await l.start()),
        throwsA(
          isA<DeviceLoginError>().having((e) => e.failure, 'failure', failure),
        ),
      );
    }
  });

  test('stops asking once cancelled, and when the code runs out', () async {
    final gh = FakeGitHub([pending, pending, pending]);
    final l = gh.login();
    var n = 0;
    await expectLater(
      l.waitForToken(await l.start(), cancelled: () => ++n > 3),
      throwsA(
        isA<DeviceLoginError>().having(
          (e) => e.failure,
          'failure',
          DeviceLoginFailure.cancelled,
        ),
      ),
    );
    final short = FakeGitHub([pending, pending, pending]);
    final s = short.login();
    final c = await s.start();
    await expectLater(
      s.waitForToken(
        DeviceCode(
          deviceCode: c.deviceCode,
          userCode: c.userCode,
          verificationUri: c.verificationUri,
          interval: 5,
          expiresIn: 10,
        ),
      ),
      throwsA(
        isA<DeviceLoginError>().having(
          (e) => e.failure,
          'failure',
          DeviceLoginFailure.expired,
        ),
      ),
    );
  });

  test('the Cross-Save client ID is set (sign-in is on)', () {
    expect(crossSaveClientId, isNotEmpty);
    expect(DeviceLogin().enabled, isTrue);
  });

  testWidgets('the dialog shows the code, then saves the token', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('xs_sign_in');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = (await tester.runAsync(() async => AppStorage(dir)))!;
    final c = CrossSaveController(storage, makeRepo: (_) => NoRepo());
    final gh = FakeGitHub([
      pending,
      {'access_token': 'gho_ok'},
    ]);
    final gate = Completer<void>();
    final login = DeviceLogin(
      clientId: 'test-client',
      post: gh.post,
      wait: (_) => gate.future, // polls wait until the test opens it
    );
    String? opened;
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showGitHubSignIn(
              context,
              c,
              login: login,
              openUrl: (u) async {
                opened = u;
                return true;
              },
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();
    expect(find.text('WDJB-MJHT'), findsOneWidget);
    await tester.tap(find.text('Open GitHub'));
    await tester.pump();
    expect(opened, 'https://github.com/login/device');
    expect(
      find.text('Waiting for you to approve it on GitHub…'),
      findsOneWidget,
    );
    gate.complete();
    for (var i = 0; i < 10 && result == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(result, isTrue);
    expect(c.token, 'gho_ok');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  });

  testWidgets('B cancels; with no client ID it asks for a token', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('xs_sign_in');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = (await tester.runAsync(() async => AppStorage(dir)))!;
    final c = CrossSaveController(storage, makeRepo: (_) => NoRepo());
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showGitHubSignIn(
              context,
              c,
              login: DeviceLogin(clientId: ''),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Paste a GitHub token'), findsOneWidget);
    expect(find.textContaining('not switched on'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(c.token, isEmpty);
  });

  test('a sync report reads as lines for a panel', () {
    final r = SyncReport()
      ..took.addAll(['mGBA/Pokemon Emerald.srm', 'Gambatte/Crystal.srm'])
      ..sent.add('mGBA/Zelda.srm');
    final lines = syncReportLines(r);
    expect(lines.first, '2 saves arrived from your other devices:');
    expect(lines, contains('   Pokemon Emerald'));
    expect(lines, contains('1 save from this device went to the repo.'));
    expect(
      syncReportLines(SyncReport()).first,
      startsWith('Everything is up to date'),
    );
    expect(
      syncReportLines(SyncReport()..error = 'offline'),
      contains('Not finished: offline'),
    );
  });
}
