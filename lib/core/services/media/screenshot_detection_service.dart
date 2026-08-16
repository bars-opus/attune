import 'dart:async';

import 'package:flutter/services.dart';

/// Best-effort screenshot detection, scoped to whatever screen constructs
/// it (per-call-site instantiation, not a singleton — mirrors
/// VoiceRecorderService/ImagePickerService's established pattern).
///
/// iOS: backed by UIApplication.userDidTakeScreenshotNotification via a
/// platform channel — a genuine, reliable system API.
/// Android: backed by a best-effort ContentObserver on the device's
/// screenshot media store path — acknowledged unreliable across
/// OEMs/launchers, shipped anyway per the design spec's explicit choice.
/// Neither platform detects screen RECORDING — not reliably available on
/// either OS.
///
/// In a pure-Dart test host (no real platform channel registered), method
/// calls throw MissingPluginException — caught and treated as "detection
/// unavailable," never surfaced as an error to callers, since this is
/// purely best-effort instrumentation and must never block the core
/// capture/send/view flow.
class ScreenshotDetectionService {
  static const _channel = MethodChannel('attune/screenshot_detection');

  final _controller = StreamController<void>.broadcast();

  Stream<void> get onScreenshotDetected => _controller.stream;

  ScreenshotDetectionService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') {
        _controller.add(null);
      }
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _channel.invokeMethod<void>('startDetection');
    } catch (_) {
      // No real platform implementation (test host, or a platform this
      // service doesn't support) — silently no-op, per this service's
      // best-effort contract.
    }
  }

  void dispose() {
    unawaited(_channel.invokeMethod<void>('stopDetection').catchError((_) {}));
    _channel.setMethodCallHandler(null);
    unawaited(_controller.close());
  }
}
