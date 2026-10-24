// Stories Wave 3 final review I3: the chat stays mounted behind the privacy
// cover and the lock check, so its "partner is in this chat" poll must stop
// itself while Attune is not on screen, and catch up once on return.
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/presentation/providers/partner_presence_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _Counting extends FakeChatRepository {
  _Counting() : super(currentUserId: 'me');
  int polls = 0;

  @override
  Future<bool> partnerIsActiveInChat(String relationshipId) async {
    polls++;
    return false;
  }
}

Future<(_Counting, ProviderContainer)> _pump(WidgetTester tester) async {
  final repo = _Counting();
  final container = ProviderContainer(
    overrides: [chatRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (_, ref, __) {
            ref.watch(partnerActiveInChatProvider('r1'));
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return (repo, container);
}

/// Closing the chat disposes the provider and its timer.
Future<void> _closeChat(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: const SizedBox()),
  );
  await tester.pump();
}

void main() {
  testWidgets('backgrounded for a minute: no poll; back: exactly one '
      'catch-up poll', (tester) async {
    final (repo, container) = await _pump(tester);
    expect(repo.polls, 1, reason: 'the first poll on open');
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    expect(container.read(appContentVisibleProvider), isFalse);
    await tester.pump(const Duration(minutes: 1));
    expect(repo.polls, 1, reason: 'no RPC while away');

    for (final s in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    expect(repo.polls, 2, reason: 'one catch-up on return');
    await tester.pump(const Duration(seconds: 15));
    expect(repo.polls, 3, reason: 'the 15 s poll carries on');
    await _closeChat(tester, container);
  });

  testWidgets("during the Safety lock's return check: no poll until it opens", (
    tester,
  ) async {
    final (repo, container) = await _pump(tester);
    container.read(appContentVisibleProvider.notifier).setLockOpen(false);
    await tester.pump(const Duration(seconds: 45));
    expect(repo.polls, 1);
    container.read(appContentVisibleProvider.notifier).setLockOpen(true);
    await tester.pump();
    expect(repo.polls, 2);
    await _closeChat(tester, container);
  });
}
