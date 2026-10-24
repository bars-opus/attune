// An empty chat greets the partner and shows what the chat can do: one card
// per feature that is switched on, opening its manual page. It goes away
// with the first message.
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/widgets/documentation_tab_view.dart';
import 'package:attune/features/auth/intro/widgets/intro_guide_widget.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/chat_empty_state.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/home/widgets/semantic_container_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

const _allFlags = {
  ChatFeatureFlags.quietStates,
  ChatFeatureFlags.conflictToolkit,
  ChatFeatureFlags.privateSafetyCheck,
  ChatFeatureFlags.shareAWin,
  ChatFeatureFlags.appreciationNotes,
  ChatFeatureFlags.ephemeralVideo,
  ChatFeatureFlags.videoSharing,
};

void main() {
  group('which cards, in which order', () {
    test('every feature on: support, hard moment, win, noticed, games, '
        'streaks, then how chat works', () {
      expect(chatEmptyStateModules(_allFlags).map((m) => m.id).toList(), [
        'quietStates',
        'hardMoment',
        'shareAWin',
        'appreciation',
        'games',
        'streaks',
        'chat',
      ]);
    });

    test('a card only shows while its feature is on', () {
      expect(chatEmptyStateModules(const {}).map((m) => m.id).toList(), [
        'games',
        'chat',
      ]);
    });
  });

  Future<ProviderContainer> pumpChat(
    WidgetTester tester, {
    required FakeChatRepository repo,
    Set<String> flags = _allFlags,
    String? profileName = 'Ama',
  }) async {
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        documentationFlagsProvider.overrideWith((ref) async => flags),
        gamePartnerNameProvider.overrideWith((ref) async => profileName),
      ],
    );
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // The flags resolve asynchronously; let the list rebuild with them.
    await tester.pump();
    return container;
  }

  Future<void> tearDownChat(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    c.dispose();
  }

  testWidgets('an empty chat greets the partner and lists the features', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final c = await pumpChat(tester, repo: repo);

    expect(find.byType(ChatEmptyState), findsOneWidget);
    // "Say hello to" over the partner's own name, both large, heard as one
    // heading. The name is the partner's profile name, not the "Partner"
    // fallback.
    final hello = tester.widget<Text>(find.text('Say hello to'));
    final name = tester.widget<Text>(find.text('Ama'));
    expect(name.style!.fontSize, hello.style!.fontSize);
    expect(
      tester.getRect(find.text('Ama')).top,
      greaterThan(tester.getRect(find.text('Say hello to')).bottom - 1),
    );
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Say hello to Ama'), findsOneWidget);
    handle.dispose();
    // The hint sits in the app's tip container, between the greeting and
    // the cards, no wider than the cards' column.
    final hint = find.ancestor(
      of: find.textContaining('Whenever you are ready'),
      matching: find.byType(SemanticContainerWidget),
    );
    expect(hint, findsOneWidget);
    expect(
      tester.getRect(hint).top,
      greaterThan(tester.getRect(find.text('Ama')).bottom),
    );
    expect(
      tester.getRect(hint).bottom,
      lessThan(tester.getRect(find.byType(IntroGuideWidget).first).top),
    );
    expect(find.byType(IntroGuideWidget), findsWidgets);
    // Later cards sit past the screen edge in the sideways row.
    expect(find.text('Share a win', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('No messages yet'),
      findsNothing,
      reason: 'the bare sentence is replaced',
    );
    await tearDownChat(tester, c);
  });

  testWidgets('a feature that is off has no card', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final c = await pumpChat(tester, repo: repo, flags: const {});

    expect(find.text('Share a win', skipOffstage: false), findsNothing);
    expect(
      find.byType(IntroGuideWidget, skipOffstage: false),
      findsNWidgets(2),
    );
    await tearDownChat(tester, c);
  });

  testWidgets('tapping a card opens its manual page', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final c = await pumpChat(tester, repo: repo);

    final card = find.text('Share a win', skipOffstage: false);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(DocumentationTabView), findsOneWidget);
    await tearDownChat(tester, c);
  });

  testWidgets('the cards sit above the message bar', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final c = await pumpChat(tester, repo: repo);

    final cards = tester.getRect(find.byType(IntroGuideWidget).first);
    final field = tester.getRect(find.byType(ChatTextField));
    expect(cards.bottom, lessThanOrEqualTo(field.top));
    await tearDownChat(tester, c);
  });

  testWidgets('the first message replaces it', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'p1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hi there',
      createdAt: DateTime.now(),
    );
    final c = await pumpChat(tester, repo: repo);

    expect(find.byType(ChatEmptyState), findsNothing);
    expect(find.text('hi there'), findsOneWidget);
    await tearDownChat(tester, c);
  });

  testWidgets('fits a small phone with larger text, no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final c = await pumpChat(tester, repo: repo);

    expect(tester.takeException(), isNull);
    expect(find.byType(IntroGuideWidget), findsWidgets);
    await tearDownChat(tester, c);
  });

  testWidgets('with no real name it just says "Say hello", never "Partner"', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final c = await pumpChat(tester, repo: repo, profileName: null);

    expect(find.text('Say hello'), findsOneWidget);
    expect(find.text('Partner'), findsNothing);
    expect(find.text('Say hello to'), findsNothing);
    await tearDownChat(tester, c);
  });
}
