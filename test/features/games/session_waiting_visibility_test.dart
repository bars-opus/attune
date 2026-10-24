// Stories Wave 3 final review M2: the session-game wait stays mounted behind
// the privacy cover and the lock check, so its 3 s poll and its 20 s
// hand-off to the chat must not run while Attune is not on screen.
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_waiting_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingRepository extends SessionGameRepository {
  int reads = 0;
  bool bothAnswered = false;

  @override
  Future<RevealedRound> fetchRevealedRound(String roundId) async {
    reads++;
    return RevealedRound(
      answerA: null,
      answerB: null,
      bothAnswered: bothAnswered,
    );
  }
}

typedef _Wait =
    ({_CountingRepository repo, ProviderContainer c, List<String> events});

Future<_Wait> _pump(WidgetTester t) async {
  final repo = _CountingRepository();
  final events = <String>[];
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: SessionGameWaitingScreen(
            roundId: 'r1',
            repository: repo,
            onRevealed: () => events.add('revealed'),
            onLeaveToChat: () => events.add('left'),
          ),
        ),
      ),
    ),
  );
  return (repo: repo, c: c, events: events);
}

Future<void> _lifecycle(WidgetTester t, List<AppLifecycleState> states) async {
  for (final s in states) {
    t.binding.handleAppLifecycleStateChanged(s);
    await t.pump();
  }
}

const _away = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const _back = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

void main() {
  testWidgets('away for a minute: no reads and no hand-off to the chat; back: '
      'one catch-up read and a fresh 20 s wait', (t) async {
    final w = await _pump(t);
    await t.pump(const Duration(seconds: 7));
    expect(w.repo.reads, 2, reason: 'polls every 3 s while on screen');

    await _lifecycle(t, _away);
    await t.pump(const Duration(minutes: 1));
    expect(w.repo.reads, 2, reason: 'no reads while away');
    expect(w.events, isEmpty, reason: 'the grace is not spent while away');

    await _lifecycle(t, _back);
    expect(w.repo.reads, 3, reason: 'one catch-up read on return');
    await t.pump(const Duration(seconds: 19));
    expect(w.events, isEmpty, reason: 'the whole window again on return');
    await t.pump(const Duration(seconds: 2));
    expect(w.events, ['left']);
  });

  testWidgets("during the Safety lock's return check: no reads; a partner who "
      'answered meanwhile is revealed once it opens', (t) async {
    final w = await _pump(t);
    w.c.read(appContentVisibleProvider.notifier).setLockOpen(false);
    await t.pump(const Duration(seconds: 30));
    expect(w.repo.reads, 0);
    expect(w.events, isEmpty);

    w.repo.bothAnswered = true;
    w.c.read(appContentVisibleProvider.notifier).setLockOpen(true);
    await t.pump();
    expect(w.repo.reads, 1);
    expect(w.events, ['revealed']);
  });
}
