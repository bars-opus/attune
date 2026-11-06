// Spec 1 W10a: the chat at large text (audit order: 1st). The thread with
// a long message, a reply, a game card and its trail, the typing dots and
// a long draft. The in-chat Games sheet is audited by
// in_chat_games_large_text_test.dart (Games files are never edited).
//   flutter test --update-goldens test/accessibility/w10/chat_large_text_test.dart
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/chat/support/chat_test_harness.dart';
import 'support/large_text_audit.dart';

FakeChatRepository _thread() {
  final repo = FakeChatRepository(currentUserId: 'user-a');
  // A fixed evening long ago: the bubbles' times and the date chip never
  // change from run to run.
  final now = DateTime(2026, 6, 1, 19, 30);
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  repo.seedIncoming(
    id: 'm1',
    relationshipId: 'rel-1',
    senderId: 'partner',
    content:
        'Are we still on for dinner at the place by the water on Saturday evening?',
    createdAt: ago(9),
  );
  repo.seedIncoming(
    id: 'm2',
    relationshipId: 'rel-1',
    senderId: 'user-a',
    content: 'Yes! I booked it for seven. Can you pick up the cake on the way?',
    createdAt: ago(8),
  );
  repo.seedIncoming(
    id: 'm3',
    relationshipId: 'rel-1',
    senderId: 'partner',
    content: 'Of course',
    createdAt: ago(7),
    replyToMessageId: 'm2',
    quotedText: 'Can you pick up the cake on the way?',
  );
  repo.seedIncoming(
    id: 'm4',
    relationshipId: 'rel-1',
    senderId: 'partner',
    content: 'Snakes and Ladders',
    createdAt: ago(6),
    mediaType: 'game',
    gameSessionId: 'gs1',
  );
  repo.seedIncoming(
    id: 'm5',
    relationshipId: 'rel-1',
    senderId: 'user-a',
    content: 'You moved to square 42',
    createdAt: ago(5),
    mediaType: 'game_trail',
  );
  return repo;
}

void main() {
  for (final phone in auditPhones) {
    for (final scale in auditScales) {
      testWidgets('chat, ${phone.width.toInt()} wide, text $scale', (t) async {
        setPhone(t, phone, scale);
        final repo = _thread();
        final container = buildChatContainer(
          repository: repo,
          userId: 'user-a',
          extraOverrides: [
            gameCardProvider.overrideWith(
              (ref, id) => Stream.value(
                const GameCardState(
                  gameType: 'snakes_and_ladders',
                  status: 'active',
                  currentTurnUserId: 'user-a',
                  winnerUserId: null,
                  currentRound: null,
                  totalRounds: null,
                ),
              ),
            ),
          ],
        );
        // W10 B1 I-1: disposed even when a golden or finder throws, so the
        // chat's idle-eviction timer never leaks into the next test.
        addTearDown(container.dispose);
        final convo = activeConversation('rel-1');
        repo.conversationOverride = convo;
        final overflows = await collectOverflows(() async {
          try {
            await t.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: withScreenUtil(
                  MaterialApp(
                    theme: AppTheme.lightTheme,
                    debugShowCheckedModeBanner: false,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    // What app_shell.dart does with the cap under audit.
                    builder:
                        (context, child) => MediaQuery.withClampedTextScaling(
                          maxScaleFactor: scale,
                          child: child!,
                        ),
                    home: ChatScreen(conversation: convo),
                  ),
                ),
              ),
            );
            await settle(t);
            repo.emitPartnerTyping('partner', true);
            await settle(t, const Duration(milliseconds: 600));
            await t.enterText(
              find.byType(TextField).last,
              'A longer draft that wraps onto a few lines in the composer box',
            );
            await settle(t, const Duration(milliseconds: 600));
            if (phone == auditPhones.first && goldenScales.contains(scale)) {
              // The wallpaper tile decodes off the test clock: wait for it,
              // so every golden has it drawn.
              await t.runAsync(
                () => precacheImage(
                  const AssetImage(
                    'assets/images/attune_chat_wallpaper_tile_refined.png',
                  ),
                  t.element(find.byType(ChatScreen)),
                ),
              );
              await t.pump();
              await expectLater(
                find.byType(MaterialApp),
                matchesGoldenFile('goldens/chat.${scaleName(scale)}.png'),
              );
            }
          } finally {
            // Unmount, then dispose: unmounting arms the chat's idle
            // eviction timer, and disposing the container cancels it.
            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(milliseconds: 100));
            container.dispose();
          }
        });
        expect(overflows, isEmpty);
      });
    }
  }
}
