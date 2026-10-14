import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/together_live.dart';

/// This phone's opt-in (Phase 8c R4); off unless set.
const liveEnabledKey = 'together_live_enabled';

/// Where the lock-screen plan goes (a seam so tests never touch iOS).
abstract class LiveActivityStore {
  Future<bool> isSupported();
  Future<void> show(LivePlan plan);
  Future<void> end();
}

/// iOS ActivityKit via ios/Runner/TogetherLiveActivityChannel.swift. On
/// Android the channel isn't registered, so every call throws and is caught.
class ChannelLiveActivityStore implements LiveActivityStore {
  const ChannelLiveActivityStore();

  static const _channel = MethodChannel('attune/together_live');

  @override
  Future<bool> isSupported() async =>
      await _channel.invokeMethod<bool>('supported') ?? false;

  @override
  Future<void> show(LivePlan plan) => _channel.invokeMethod('show', {
    'title': plan.title,
    'start': plan.start.millisecondsSinceEpoch,
    'end': plan.end.millisecondsSinceEpoch,
  });

  @override
  Future<void> end() => _channel.invokeMethod('end');
}

/// Starts, updates or ends the lock-screen plan. Never throws: a phone
/// without Live Activities (or a test without the channel) must not break
/// the caller.
class TogetherLiveActivity {
  static LiveActivityStore store = const ChannelLiveActivityStore();

  /// False off iOS, below iOS 16.2, or with Live Activities off in Settings.
  static Future<bool> isSupported() async {
    try {
      return await store.isSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<void> end() async {
    try {
      await store.end();
    } catch (_) {}
  }

  /// Shows [plan], or ends what's showing when there's none, only if this
  /// phone opted in, read from storage itself so a stale in-memory "on"
  /// (say, after sign-out) never shows anything.
  static Future<void> showIfEnabled(LivePlan? plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(liveEnabledKey) ?? false)) return;
      if (plan == null) {
        await store.end();
      } else {
        await store.show(plan);
      }
    } catch (_) {}
  }
}
