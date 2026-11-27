/// The "Sign in with GitHub" dialog both apps use: a big code to type on
/// github.com/login/device, a button that opens that page, and "Paste a
/// token instead" for when sign-in is off (no client ID) or fails.
/// Gamepad: A presses the focused button, B cancels (swapped with
/// [GitHubSignIn.swapAB]); the d-pad moves between buttons. Touch works too.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'controller.dart';
import 'device_login.dart';

/// Where fine-grained tokens are made (the paste-a-token way).
const tokenPageUrl = 'https://github.com/settings/personal-access-tokens/new';

/// Opens [url] in the browser; false when nothing could open it.
typedef OpenUrl = Future<bool> Function(String url);

/// Shows [GitHubSignIn]; true when a working token was saved in
/// [controller] (it was checked against the Cross-Save repo).
Future<bool> showGitHubSignIn(
  BuildContext context,
  CrossSaveController controller, {
  DeviceLogin? login,
  OpenUrl? openUrl,
  bool swapAB = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => GitHubSignIn(
      controller: controller,
      login: login,
      openUrl: openUrl,
      swapAB: swapAB,
    ),
  );
  return ok ?? false;
}

enum _Step { asking, code, checking, failed, paste }

class GitHubSignIn extends StatefulWidget {
  const GitHubSignIn({
    super.key,
    required this.controller,
    this.login,
    this.openUrl,
    this.swapAB = false,
  });

  final CrossSaveController controller;

  /// The device flow (tests pass a fake); default: GitHub with
  /// [crossSaveClientId].
  final DeviceLogin? login;
  final OpenUrl? openUrl;

  /// Nintendo-style: the right face button confirms.
  final bool swapAB;

  @override
  State<GitHubSignIn> createState() => _GitHubSignInState();
}

class _GitHubSignInState extends State<GitHubSignIn> {
  late final DeviceLogin _login = widget.login ?? DeviceLogin();
  _Step _step = _Step.asking;
  DeviceCode? _code;
  String _error = '';
  String _note = '';
  bool _stopped = false;
  int _attempt = 0;
  final _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_login.enabled) {
      unawaited(_begin());
    } else {
      _step = _Step.paste;
      _note =
          'Sign in with GitHub is not switched on in this build yet, so for '
          'now make a token and paste it here.';
    }
  }

  @override
  void dispose() {
    _stopped = true;
    _field.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    final attempt = ++_attempt;
    setState(() {
      _step = _Step.asking;
      _error = '';
      _note = '';
    });
    try {
      final code = await _login.start();
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _code = code;
        _step = _Step.code;
      });
      final token = await _login.waitForToken(
        code,
        cancelled: () => _stopped || attempt != _attempt,
      );
      if (!mounted || attempt != _attempt) return;
      await _check(token);
    } on DeviceLoginError catch (e) {
      if (!mounted || attempt != _attempt) return;
      if (e.failure == DeviceLoginFailure.cancelled) return;
      setState(() {
        _step = _Step.failed;
        _error = e.message;
      });
    }
  }

  /// Keeps [token] if it opens the Cross-Save repo.
  Future<void> _check(String token) async {
    setState(() => _step = _Step.checking);
    final err = await widget.controller.setToken(token);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _step = _Step.failed;
      _error =
          'Signed in, but it could not open your Cross-Save repo: $err. '
          'Sign in with the GitHub account that owns Cross-Save.';
    });
  }

  Future<void> _open(String url) async {
    final ok = await widget.openUrl?.call(url) ?? false;
    if (!ok && mounted) {
      setState(
        () => _note = 'Open ${_bare(url)} in your browser (on any device).',
      );
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _note = 'Code copied');
  }

  void _cancel() {
    _stopped = true;
    Navigator.of(context).pop(false);
  }

  void _toPaste() {
    _attempt++; // stops the polling
    setState(() {
      _step = _Step.paste;
      _error = '';
      _note = '';
    });
  }

  static String _bare(String url) =>
      url.replaceFirst(RegExp(r'^https?://'), '');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final confirm = widget.swapAB
        ? LogicalKeyboardKey.gameButtonB
        : LogicalKeyboardKey.gameButtonA;
    final back = widget.swapAB
        ? LogicalKeyboardKey.gameButtonA
        : LogicalKeyboardKey.gameButtonB;
    return Shortcuts(
      shortcuts: {
        SingleActivator(confirm): const ActivateIntent(),
        SingleActivator(back): const DismissIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _cancel();
              return null;
            },
          ),
        },
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _step == _Step.paste
                        ? 'Paste a GitHub token'
                        : 'Sign in with GitHub',
                    style: t.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ..._body(t),
                  if (_note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _note,
                      style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(ThemeData t) {
    switch (_step) {
      case _Step.asking:
        return [
          _waiting(t, 'Asking GitHub for a sign-in code…'),
          _buttons([
            TextButton(onPressed: _toPaste, child: const Text('Paste a token')),
            TextButton(
              autofocus: true,
              onPressed: _cancel,
              child: const Text('Cancel'),
            ),
          ]),
        ];
      case _Step.code:
        final c = _code!;
        return [
          Text(
            '1. Open ${_bare(c.verificationUri)} (here or on any device).\n'
            '2. Type this code, then press Authorize.',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: t.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SelectableText(
                c.userCode,
                key: const Key('github-user-code'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  letterSpacing: 4,
                  color: t.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _waiting(t, 'Waiting for you to approve it on GitHub…'),
          _buttons([
            FilledButton.icon(
              autofocus: true,
              onPressed: () => unawaited(_open(c.verificationUri)),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open GitHub'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(_copy(c.userCode)),
              icon: const Icon(Icons.copy),
              label: const Text('Copy Code'),
            ),
            TextButton(onPressed: _cancel, child: const Text('Cancel')),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _toPaste,
              child: const Text('Paste a token instead'),
            ),
          ),
        ];
      case _Step.checking:
        return [_waiting(t, 'Signed in. Checking your Cross-Save repo…')];
      case _Step.failed:
        return [
          Text(_error, style: t.textTheme.bodyMedium),
          _buttons([
            FilledButton(
              autofocus: true,
              onPressed: () => unawaited(_begin()),
              child: const Text('Try Again'),
            ),
            TextButton(
              onPressed: _toPaste,
              child: const Text('Paste a token instead'),
            ),
            TextButton(onPressed: _cancel, child: const Text('Cancel')),
          ]),
        ];
      case _Step.paste:
        return [
          Text(
            'On github.com: Settings > Developer settings > Personal access '
            'tokens > Fine-grained tokens > Generate new token. Repository '
            'access: only Cross-Save. Permissions > Contents: Read and write. '
            'Generate, copy it and paste it here.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _field,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'github_pat_…'),
            onSubmitted: (_) => _savePasted(),
          ),
          _buttons([
            FilledButton(
              autofocus: true,
              onPressed: _savePasted,
              child: const Text('Save'),
            ),
            OutlinedButton(
              onPressed: () => unawaited(_open(tokenPageUrl)),
              child: const Text('Make a Token'),
            ),
            if (_login.enabled)
              TextButton(
                onPressed: () => unawaited(_begin()),
                child: const Text('Sign in instead'),
              ),
            TextButton(onPressed: _cancel, child: const Text('Cancel')),
          ]),
        ];
    }
  }

  void _savePasted() {
    final text = _field.text.trim();
    if (text.isEmpty) {
      setState(() => _note = 'Paste the token first');
      return;
    }
    unawaited(_check(text));
  }

  Widget _waiting(ThemeData t, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: t.textTheme.bodySmall)),
      ],
    ),
  );

  Widget _buttons(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: children,
    ),
  );
}
