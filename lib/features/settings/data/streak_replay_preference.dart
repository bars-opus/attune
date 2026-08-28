import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'streak_allow_replays';

/// Views a recipient gets. Strict view-once unless the sender has opted
/// into replays in chat settings.
///
/// Capped at 3 rather than unlimited because a replayable streak outlives
/// a view-once one on the server: the clips are destroyed only when the
/// budget reaches zero, so a larger budget means longer retention.
int streakViewBudget({required bool allowReplays}) => allowReplays ? 3 : 1;

/// Whether streaks this user sends may be replayed.
///
/// A persistent setting rather than a per-send toggle: deciding it once in
/// chat settings keeps the capture flow to record → send or cancel, which
/// is the whole point of a streak being fast to send.
class StreakReplayPreferenceNotifier extends StateNotifier<bool> {
  StreakReplayPreferenceNotifier(SharedPreferences prefs)
      : _prefs = prefs,
        super(prefs.getBool(_kKey) ?? false);

  /// Test-only: skips the SharedPreferences-backed default for harnesses
  /// that need this provider overridden synchronously.
  StreakReplayPreferenceNotifier.forTesting([super.initial = false])
      : _prefs = null;

  final SharedPreferences? _prefs;

  Future<void> setAllowReplays(bool value) async {
    state = value;
    await _prefs?.setBool(_kKey, value);
  }
}

final streakReplayPreferenceProvider =
    StateNotifierProvider<StreakReplayPreferenceNotifier, bool>((ref) {
  // Falls back to the in-memory notifier when SharedPreferences has not
  // been overridden. This is a cosmetic preference on a settings row, so
  // it must never take down a screen that merely renders that row —
  // several widget tests build the chat settings tree without wiring
  // prefs, and throwing here made them fail for a reason unrelated to
  // what they were testing.
  try {
    return StreakReplayPreferenceNotifier(ref.watch(sharedPreferencesProvider));
  } catch (_) {
    return StreakReplayPreferenceNotifier.forTesting();
  }
});
