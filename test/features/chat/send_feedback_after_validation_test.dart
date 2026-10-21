import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/games/invites/services/game_invite_service.dart';
import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('a message the controller will refuse gets no chirp or haptic', (
    tester,
  ) async {
    // 12k characters: sendMessage returns silently on !isValidContent, yet
    // the "sent" chirp played and the composer emptied - nothing said no.
    // Plan 3 fixed the refusal; this pins that it sits ABOVE the feedback.
    // The draft is written to the controller directly (as _appendToComposer
    // and the translator do) because plan 3's input formatter would clamp
    // tester.enterText to 10,000 code points and make the case vacuous.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final sound = FakeSoundService();
    final haptics = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        soundServiceProvider.overrideWithValue(sound),
        hapticsProvider.overrideWithValue(haptics),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));

    final tooLong = 'a' * (Message.maxContentRunes + 2000);
    final field = find.byType(TextField).first;
    tester.widget<TextField>(field).controller!.value = TextEditingValue(
      text: tooLong,
      selection: TextSelection.collapsed(offset: tooLong.length),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 30));

    expect(sound.played, isEmpty);
    expect(haptics.lightCount, 0);
    expect(repo.sendCallCount, 0);
    expect(
      find.textContaining('10,000 characters'),
      findsOneWidget,
      reason: 'plan 3 tells the person; the refusal must not go silent',
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });

  group('a staged game send (T11 carry: behavioural, not source-pinned)', () {
    Future<
      ({
        ProviderContainer container,
        FakeSoundService sound,
        FakeHaptics haptics,
        FakeChatRepository repo,
      })
    >
    pumpWithGame(
      WidgetTester tester, {
      bool soundsOn = true,
      bool inviteFails = false,
    }) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final sound = FakeSoundService();
      final haptics = FakeHaptics();
      final convo = activeConversation('rel-1');
      repo.conversationOverride = convo;
      final container = buildChatContainer(
        repository: repo,
        userId: 'user-a',
        extraOverrides: [
          soundServiceProvider.overrideWithValue(sound),
          hapticsProvider.overrideWithValue(haptics),
          messageSoundsEnabledProvider.overrideWith(
            (ref) => SoundPreferenceNotifier.forTesting(enabled: soundsOn),
          ),
          gameInviteGatewayProvider.overrideWithValue(
            _InviteGateway(fails: inviteFails),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: withScreenUtil(
            MaterialApp(home: ChatScreen(conversation: convo)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));
      container.read(gameComposerProvider('rel-1').notifier).stage('mirror');
      await tester.pump(const Duration(milliseconds: 300));
      return (
        container: container,
        sound: sound,
        haptics: haptics,
        repo: repo,
      );
    }

    Future<void> sendAndTearDown(
      WidgetTester tester,
      ProviderContainer container,
      void Function() expectations,
    ) async {
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expectations();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    }

    testWidgets('success plays the send chirp and one selection', (
      tester,
    ) async {
      final rig = await pumpWithGame(tester);
      await sendAndTearDown(tester, rig.container, () {
        expect(rig.sound.played, [ChatSound.send]);
        expect(rig.haptics.selectionCount, 1);
        expect(
          rig.container.read(gameComposerProvider('rel-1')).isStaged,
          isFalse,
        );
      });
    });

    testWidgets('with message sounds off it is silent but still confirms', (
      tester,
    ) async {
      final rig = await pumpWithGame(tester, soundsOn: false);
      await sendAndTearDown(tester, rig.container, () {
        expect(rig.sound.played, isEmpty);
        expect(rig.haptics.selectionCount, 1);
      });
    });

    testWidgets('an invite the server refuses gets no chirp or haptic', (
      tester,
    ) async {
      final rig = await pumpWithGame(tester, inviteFails: true);
      await sendAndTearDown(tester, rig.container, () {
        expect(rig.sound.played, isEmpty);
        expect(rig.haptics.selectionCount, 0);
        expect(
          rig.container.read(gameComposerProvider('rel-1')).isStaged,
          isTrue,
          reason: 'the game stays staged for the retry',
        );
      });
    });
  });
}

class _InviteGateway implements GameInviteGateway {
  _InviteGateway({this.fails = false});
  final bool fails;

  @override
  Future<GameInvite> create({
    required String relationshipId,
    required String gameType,
    required String idempotencyKey,
    String tone = 'connecting',
  }) async {
    if (fails) throw StateError('offline');
    return const GameInvite(sessionId: 's1', existing: false);
  }

  @override
  Future<void> accept(String sessionId) async {}

  @override
  Future<void> decline(String sessionId) async {}
}
