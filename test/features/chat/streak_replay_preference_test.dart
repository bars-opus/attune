import 'package:attune/features/settings/data/streak_replay_preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('replays are OFF by default — strict view-once', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier = StreakReplayPreferenceNotifier(prefs);
    expect(notifier.state, isFalse);
  });

  test('enabling persists, and maps to a 3-view budget', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier = StreakReplayPreferenceNotifier(prefs);

    await notifier.setAllowReplays(true);
    expect(notifier.state, isTrue);

    // A fresh notifier reads the stored value.
    expect(StreakReplayPreferenceNotifier(prefs).state, isTrue);
  });

  test('the budget is 1 when off and 3 when on', () {
    expect(streakViewBudget(allowReplays: false), 1);
    expect(streakViewBudget(allowReplays: true), 3);
  });
}
