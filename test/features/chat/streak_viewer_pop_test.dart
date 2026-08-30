import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/presentation/screens/streak_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// No clips, so the viewer reaches its "unavailable" state without a real
/// video controller — the exit paths are what this exercises, not playback.
class _FakeStreakRepository implements StreakRepository {
  int markViewedCalls = 0;

  @override
  Future<int> markViewed(String messageId) async {
    markViewedCalls++;
    return 0;
  }

  @override
  Future<List<StreakClip>> fetchClips(String messageId) async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('dismissing the viewer actually closes it', (tester) async {
    // _finish() requests a pop, and this screen's own PopScope intercepts
    // it and calls _finish() again. When the close lived inside the
    // _viewSpent guard, that second call returned early and NOTHING
    // popped — a black screen the user could not leave.
    final repo = _FakeStreakRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [streakRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<int>(
                              builder:
                                  (_) =>
                                      const StreakViewerScreen(messageId: 'm1'),
                            ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(StreakViewerScreen), findsOneWidget);

    // Dismissed the way PLAYBACK COMPLETION does: _finish() called on its
    // own, with no gesture in flight. A tap instead reaches _close through
    // the GestureDetector before PopScope re-enters, which hides exactly
    // the deadlock this is here to catch.
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    await (state as dynamic).finishForTest();
    await tester.pumpAndSettle();

    expect(
      find.byType(StreakViewerScreen),
      findsNothing,
      reason: 'the viewer never closed — the screen is stuck black',
    );
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the remaining count reaches the caller', (tester) async {
    // The bubble only applies a NON-NULL result. If the route closes by
    // any path that drops the pop argument, the count never arrives, the
    // bubble keeps its build-time value, and the streak stays on "Play"
    // however many times it is watched.
    final repo = _FakeStreakRepository();
    int? received = -1;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [streakRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        received = await Navigator.of(context).push<int>(
                          MaterialPageRoute<int>(
                            builder:
                                (_) =>
                                    const StreakViewerScreen(messageId: 'm1'),
                          ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    await (state as dynamic).finishForTest();
    await tester.pumpAndSettle();

    expect(
      received,
      0,
      reason:
          'the fake reports 0 views left; anything else means the result '
          'was dropped on the way out and the bubble learns nothing',
    );
  });

  testWidgets('the view is charged exactly once, however it closes', (
    tester,
  ) async {
    // The guard still has to hold: PopScope re-enters _finish, and a
    // double charge would spend two views for one watch.
    final repo = _FakeStreakRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [streakRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<int>(
                              builder:
                                  (_) =>
                                      const StreakViewerScreen(messageId: 'm1'),
                            ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    await (state as dynamic).finishForTest();
    await tester.pumpAndSettle();

    expect(repo.markViewedCalls, 1);
  });
}
