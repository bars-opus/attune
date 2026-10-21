import 'dart:io';

import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

Widget _reduced(Widget child) => MaterialApp(
  builder:
      (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: app!,
      ),
  home: child,
);

void main() {
  testWidgets('the record disc does not spring under Reduce Motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _reduced(
        Scaffold(
          body: Center(
            child: StreakRecordButton(
              progress: 0.2,
              isRecording: true,
              onPressStart: () {},
              onPressEnd: () {},
            ),
          ),
        ),
      ),
    );
    final fill = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('streak-record-fill-entrance')),
    );
    final arc = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('streak-record-arc-entrance')),
    );
    expect(fill.duration, Duration.zero);
    expect(arc.duration, Duration.zero);
  });

  testWidgets('the typing bubble does not pop/scale under Reduce Motion', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(_reduced(ChatScreen(conversation: convo))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    repo.emitPartnerTyping('partner', true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final switcher = tester.widget<AnimatedSwitcher>(
      find.ancestor(
        of: find.byKey(const ValueKey('typing_indicator')),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });

  test('scroll helpers jump instead of animating under Reduce Motion', () {
    final src =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();
    final scrollToLatest = src.substring(
      src.indexOf('void _scrollToLatest()'),
      src.indexOf('Future<void> _openPulse()'),
    );
    expect(scrollToLatest, contains('reduceMotionOf(context)'));
    expect(scrollToLatest, contains('jumpTo(0)'));

    final ensure = src.substring(
      src.indexOf('bool _tryEnsureMessageVisible('),
      src.indexOf('Future<void> _jumpToMessage('),
    );
    expect(ensure, contains('reduceMotionOf(context)'));
    expect(ensure, contains('Duration.zero'));
  });
}
