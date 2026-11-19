import 'dart:async';

import 'package:flutter/widgets.dart';

/// Lets one tap at a time open something: a game, a landing page, a
/// session.
///
/// Held from the tap until the thing it asked for has ended, and then
/// through the end of that frame. A push reaches the tree only on the next
/// frame, and until it does the page is still in front, so a second tap in
/// the same frame would open a second screen. Nothing is held while the
/// opened screen is used: an open completes once navigation has begun
/// (see GameController.onPrimary), and the page coming back into view is
/// not the open ending -- a dialog it showed may have just closed.
mixin GameTapGuard<T extends StatefulWidget> on State<T> {
  bool _held = false;

  /// Whether a tap's open is still running.
  bool get tapHeld => _held;

  /// Called when the guard is taken and when it is let go, while mounted,
  /// for a page that draws itself busy meanwhile.
  void onTapHeldChanged() {}

  /// Runs [open] unless another tap's open is still running. [what] names
  /// the thing being opened in a reported failure.
  Future<void> runOnce(String what, FutureOr<void> Function() open) async {
    // The only guard against two taps in one frame: nothing drawn as busy
    // is rebuilt until the next one.
    if (_held) return;
    _held = true;
    onTapHeldChanged();
    try {
      await open();
    } catch (error, stack) {
      // Reported, not rethrown: nothing awaits a tap, so a rethrow would
      // surface as an uncaught zone error with no screen context. And not
      // swallowed: FlutterError.onError is where the app's failures go.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'games',
          context: ErrorDescription('while opening $what'),
        ),
      );
    } finally {
      // Held through the frame the open ended in, by which time a screen it
      // pushed is in front and takes the taps.
      await WidgetsBinding.instance.endOfFrame;
      _held = false;
      if (mounted) onTapHeldChanged();
    }
  }
}
