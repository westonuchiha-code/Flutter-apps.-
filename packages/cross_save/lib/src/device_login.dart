/// "Sign in with GitHub" without typing a password into the app: GitHub's
/// OAuth device flow. The app asks GitHub for a short code, the player
/// opens github.com/login/device (on this device or any other), types the
/// code and approves; meanwhile the app asks GitHub every few seconds
/// whether it was approved, and gets a token when it was.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The Cross-Save OAuth app's client ID (public, not a secret: the device
/// flow has no client secret). Device Flow is enabled on it and its tokens
/// don't expire. Empty would switch sign-in off (the apps then offer
/// pasting a token instead).
const crossSaveClientId = 'Ov23liHggf77LmpNo0F9';

/// The scope the token needs: the Cross-Save repo is private.
const crossSaveScope = 'repo';

/// One form POST to GitHub: its status code and body. Tests pass a fake.
typedef FormPost = Future<({int status, String body})> Function(
  Uri url,
  Map<String, String> form,
);

/// What the player needs to approve the sign-in.
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresIn,
  });

  /// Kept by the app (asked about while polling); never shown.
  final String deviceCode;

  /// "WDJB-MJHT": what the player types on github.com/login/device.
  final String userCode;
  final String verificationUri;

  /// Seconds between polls (GitHub's minimum).
  final int interval;

  /// Seconds the code stays valid.
  final int expiresIn;
}

/// Why a sign-in stopped without a token.
enum DeviceLoginFailure {
  /// The code ran out (15 minutes) before it was approved.
  expired,

  /// The player pressed Cancel on GitHub.
  denied,

  /// The app stopped asking (the player closed the dialog).
  cancelled,

  /// Anything else (no network, device flow not enabled, bad client ID).
  other,
}

class DeviceLoginError implements Exception {
  const DeviceLoginError(this.failure, this.message);
  final DeviceLoginFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// GitHub's device flow. [post] and [wait] are for tests.
class DeviceLogin {
  DeviceLogin({
    this.clientId = crossSaveClientId,
    this.scope = crossSaveScope,
    FormPost? post,
    Future<void> Function(Duration)? wait,
  }) : _post = post ?? postForm,
       _wait = wait ?? ((d) => Future<void>.delayed(d));

  final String clientId;
  final String scope;
  final FormPost _post;
  final Future<void> Function(Duration) _wait;

  static final codeUrl = Uri.https('github.com', '/login/device/code');
  static final tokenUrl = Uri.https('github.com', '/login/oauth/access_token');

  /// Whether sign-in can be offered at all.
  bool get enabled => clientId.isNotEmpty;

  /// Asks GitHub for a code to show the player.
  Future<DeviceCode> start() async {
    final j = await _ask(codeUrl, {'client_id': clientId, 'scope': scope});
    final err = j['error'];
    if (err != null) {
      throw DeviceLoginError(DeviceLoginFailure.other, _explain('$err', j));
    }
    final code = j['device_code'], user = j['user_code'];
    if (code is! String || user is! String) {
      throw const DeviceLoginError(
        DeviceLoginFailure.other,
        'GitHub sent no sign-in code',
      );
    }
    return DeviceCode(
      deviceCode: code,
      userCode: user,
      verificationUri:
          '${j['verification_uri'] ?? 'https://github.com/login/device'}',
      interval: _int(j['interval'], 5),
      expiresIn: _int(j['expires_in'], 900),
    );
  }

  /// Asks GitHub every [DeviceCode.interval] seconds until the player
  /// approved (returns the token), said no, or the code ran out. Stops
  /// with [DeviceLoginFailure.cancelled] once [cancelled] says so.
  Future<String> waitForToken(
    DeviceCode code, {
    bool Function()? cancelled,
  }) async {
    var interval = code.interval;
    var left = code.expiresIn;
    while (true) {
      if (cancelled?.call() ?? false) {
        throw const DeviceLoginError(DeviceLoginFailure.cancelled, 'stopped');
      }
      await _wait(Duration(seconds: interval));
      left -= interval;
      if (cancelled?.call() ?? false) {
        throw const DeviceLoginError(DeviceLoginFailure.cancelled, 'stopped');
      }
      final Map<String, Object?> j;
      try {
        j = await _ask(tokenUrl, {
          'client_id': clientId,
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        });
      } on DeviceLoginError {
        // A dropped connection while waiting: try again until it runs out.
        if (left <= 0) rethrow;
        continue;
      }
      final token = j['access_token'];
      if (token is String && token.isNotEmpty) return token;
      switch ('${j['error']}') {
        case 'authorization_pending':
          break;
        case 'slow_down':
          // GitHub says how long to wait now (otherwise 5 s more).
          interval = _int(j['interval'], interval + 5);
        case 'expired_token':
          throw const DeviceLoginError(
            DeviceLoginFailure.expired,
            'The code ran out before it was approved. Try again for a new one.',
          );
        case 'access_denied':
          throw const DeviceLoginError(
            DeviceLoginFailure.denied,
            'The sign-in was cancelled on GitHub.',
          );
        default:
          throw DeviceLoginError(
            DeviceLoginFailure.other,
            _explain('${j['error']}', j),
          );
      }
      if (left <= 0) {
        throw const DeviceLoginError(
          DeviceLoginFailure.expired,
          'The code ran out before it was approved. Try again for a new one.',
        );
      }
    }
  }

  Future<Map<String, Object?>> _ask(Uri url, Map<String, String> form) async {
    final ({int status, String body}) res;
    try {
      res = await _post(url, form);
    } catch (e) {
      throw DeviceLoginError(
        DeviceLoginFailure.other,
        "Couldn't reach GitHub ($e)",
      );
    }
    Object? j;
    try {
      j = jsonDecode(res.body);
    } catch (_) {}
    if (j is Map<String, Object?>) return j;
    throw DeviceLoginError(
      DeviceLoginFailure.other,
      'GitHub said ${res.status}: '
      '${res.body.length > 120 ? res.body.substring(0, 120) : res.body}',
    );
  }

  static int _int(Object? v, int fallback) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? fallback;

  static String _explain(String error, Map<String, Object?> j) =>
      switch (error) {
        'device_flow_disabled' =>
          'Sign in with GitHub is not switched on for this app yet '
              '(the OAuth app needs "Enable Device Flow").',
        'incorrect_client_credentials' =>
          'GitHub does not know this app (its client ID is wrong).',
        _ => 'GitHub said: ${j['error_description'] ?? error}',
      };
}

/// A form POST with dart:io's HttpClient, asking for JSON back.
Future<({int status, String body})> postForm(
  Uri url,
  Map<String, String> form,
) async {
  final http = HttpClient();
  try {
    final req = await http.postUrl(url).timeout(const Duration(seconds: 15));
    req.headers
      ..set('Accept', 'application/json')
      ..set('User-Agent', 'xmb-frontend-android')
      ..contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
    req.write(Uri(queryParameters: form).query);
    final res = await req.close().timeout(const Duration(seconds: 30));
    final body = await utf8.decodeStream(res);
    return (status: res.statusCode, body: body);
  } finally {
    http.close();
  }
}
