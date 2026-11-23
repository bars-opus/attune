// Spec 2 W8a (§3.0 Discretion, §6.7, §7.4; F-4): while any Dating page is
// open, the screen is protected. Android: FLAG_SECURE on the window
// (screenshots and screen recording come out black, the Recents thumbnail
// too). iOS can't block screenshots: the app switcher is covered by the
// existing AppPrivacyCover, and Dating pages blur while the screen is
// being captured (recorded or mirrored): sceneCaptureState on iOS 17 and
// later, UIScreen.isCaptured before. Both through the existing
// attune/safety channel (MainActivity.kt, AppDelegate.swift): setSecure
// answers whether the screen is captured now, and iOS calls
// captureChanged(bool) while it watches. Nothing is stored or sent.
//
// Task 2 fix round 1: the cover keeps one tree shape, so a capture starting
// or stopping never rebuilds the page (nothing typed is lost; I-1); on a
// phone a failure is reported (FlutterError.reportError), never swallowed
// (I-3); an iPhone is covered from the moment it asks until it answers
// (M-2). Round 2: the blur changes only outside a frame's build and
// teardown (M-8), and a report names Attune, never Dating (M-9). Round 3
// (M-11): a cover built in that same frame is blurred already
// (_coverNow), so the first frame of a page opened mid-capture is too.
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class DatingDiscretion {
  static const channel = MethodChannel('attune/safety');

  /// True while iOS says the screen is being captured (never on Android:
  /// FLAG_SECURE blanks the capture itself).
  static final captured = ValueNotifier<bool>(false);

  static bool _secure = false;
  static bool _listening = false;

  /// Round 3 (M-11): a blur asked for inside a frame, before its deferred
  /// notify lands: read by covers built in that frame (the new page's own),
  /// never notified, cleared just after the frame.
  static bool _coverNow = false;

  /// The phone this runs on, for tests (null: the real one).
  @visibleForTesting
  static TargetPlatform? debugDevice;

  static bool get _ios =>
      debugDevice == null
          ? !kIsWeb && Platform.isIOS
          : debugDevice == TargetPlatform.iOS;

  static bool get _phone =>
      debugDevice == null
          ? !kIsWeb && (Platform.isAndroid || Platform.isIOS)
          : debugDevice == TargetPlatform.android ||
              debugDevice == TargetPlatform.iOS;

  /// Whether the last call asked for protection (tests).
  @visibleForTesting
  static bool get secure => _secure;

  /// [on]: the first Dating page opened; off: the last one closed. Never
  /// throws. Off a phone (a test, a desktop) a missing channel is expected
  /// and quiet; on a phone every failure is reported.
  static Future<void> setSecure(bool on) async {
    _secure = on;
    if (!_listening) {
      _listening = true;
      channel.setMethodCallHandler(_onCall);
    }
    // Off: nothing is blurred any more. On, on an iPhone: covered until iOS
    // answers, so a page opened during a recording shows no frame (M-2).
    _set(on && _ios);
    try {
      final now = await channel.invokeMethod<bool>('setSecure', on);
      // A late answer for an earlier call changes nothing.
      if (_secure == on) _set(on && now == true);
    } on MissingPluginException catch (e) {
      if (_secure == on) _set(false);
      if (_phone) _report(e);
    } catch (e) {
      if (_secure == on) _set(false);
      _report(e);
    }
  }

  /// Round 2 (M-8): a page opens in a frame's build and goes in its
  /// teardown, when no other Dating surface may be marked; the change then
  /// lands just after that frame (as DatingSurface.reset), in order.
  static void _set(bool value) {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (value) _coverNow = true;
      binding.addPostFrameCallback((_) {
        _coverNow = false;
        captured.value = value;
      });
      return;
    }
    captured.value = value;
  }

  // M-9: the device log never names Dating: no stack (its frames name the
  // files), the library is Attune's.
  static void _report(Object e) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: e,
      library: 'attune',
      context: ErrorDescription('while protecting the screen'),
    ),
  );

  static Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'captureChanged') {
      _set(_secure && call.arguments == true);
    }
    return null;
  }

  /// Back to the first launch's state (tests).
  @visibleForTesting
  static void reset() {
    _secure = false;
    _listening = false;
    _coverNow = false;
    debugDevice = null;
    captured.value = false;
  }
}

/// A Dating page while the screen is being captured: blurred past reading,
/// not touchable and not announced (a recording can carry a screen
/// reader's voice). One tree shape, captured or not: only the flags change,
/// so the page underneath keeps its state (I-1).
class DatingCaptureCover extends StatelessWidget {
  const DatingCaptureCover({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: DatingDiscretion.captured,
    child: child,
    builder: (context, captured, child) {
      // M-11: a blur asked for in this frame counts at once.
      final on = captured || DatingDiscretion._coverNow;
      return ExcludeSemantics(
        key: const ValueKey('dating_capture_cover'),
        excluding: on,
        child: ImageFiltered(
          enabled: on,
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: AbsorbPointer(absorbing: on, child: child),
        ),
      );
    },
  );
}
