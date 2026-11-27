import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'buttons.dart';
import 'pad_input.dart';
import 'pad_keys.dart';

/// Hands controller buttons to [onButton] while this is on screen: from
/// [PadInput] (XInput / joysticks on Windows, /dev/input/js* on Linux),
/// and with [keys], from the controller key events under it (Android's
/// controllers, gameButtonA etc. and the d-pad's arrows). Only the newest
/// enabled listener on the current page hears them.
///
/// Directions repeat while held (after [GamepadInput.firstRepeat], then
/// every [GamepadInput.nextRepeat]); other buttons fire once, and their
/// release goes to [onRelease].
class PadListener extends StatefulWidget {
  const PadListener({
    super.key,
    required this.onButton,
    this.onRelease,
    this.enabled = true,
    this.keys = true,
    this.input,
    required this.child,
  });

  final void Function(PadButton button) onButton;
  final void Function(PadButton button)? onRelease;

  /// False: buttons go past this one (a text box is open, say).
  final bool enabled;

  /// Also read controller key events from the focused widget under this
  /// one. False when the child reads key events itself (and wants
  /// controller keys handled there, with the keyboard).
  final bool keys;

  /// The controllers to listen to (default [PadInput.instance]).
  final PadInput? input;

  final Widget child;

  @override
  State<PadListener> createState() => _PadListenerState();
}

class _PadListenerState extends State<PadListener> {
  PadHandle? _handle;
  ModalRoute<Object?>? _route;
  late PadKeys _padKeys = _makePadKeys();

  static PadKeys _makePadKeys() =>
      PadKeys(android: defaultTargetPlatform == TargetPlatform.android);

  PadInput get _input => widget.input ?? PadInput.instance;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(PadListener old) {
    super.didUpdateWidget(old);
    if ((old.input ?? PadInput.instance) != _input) {
      _handle?.detach();
      _attach();
    }
    _padKeys = _makePadKeys();
  }

  @override
  void dispose() {
    _handle?.detach();
    _handle = null;
    super.dispose();
  }

  void _attach() {
    _handle = _input.attach(
      onButton: (b) => widget.onButton(b),
      onRelease: (b) => widget.onRelease?.call(b),
      enabled: () => mounted && widget.enabled && (_route?.isCurrent ?? true),
    );
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    final pad = _padKeys.read(event);
    if (pad == null) return KeyEventResult.ignored;
    if (pad.fire) {
      widget.onButton(pad.button);
    } else if (event is KeyUpEvent && !pad.button.isDirection) {
      widget.onRelease?.call(pad.button);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => widget.keys
      ? Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _key,
          child: widget.child,
        )
      : widget.child;
}
