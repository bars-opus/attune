import 'dart:async';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/widgets/game_message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

const _won = GameCardState(
  gameType: 'snakes_and_ladders',
  status: 'completed',
  currentTurnUserId: null,
  winnerUserId: 'me',
  currentRound: null,
  totalRounds: null,
);

Message _gameCard() => Message(
  id: 'g1',
  clientMessageId: 'c-g1',
  relationshipId: 'r1',
  senderId: 'me',
  content: 'Snakes and Ladders',
  createdAt: DateTime(2026, 7, 1),
  status: MessageStatus.delivered,
  isMine: true,
  mediaType: 'game',
  gameSessionId: 's1',
);

void main() {
  testWidgets('a read-only transcript still phrases the card for its reader',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameCardProvider.overrideWith((ref, id) => Stream.value(_won)),
        ],
        child: withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: _gameCard(),
                currentUserId: null,
                viewerUserId: 'me',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You won!'), findsOneWidget);
    expect(find.text('You lost'), findsNothing);
  });

  testWidgets('a session that fails to load says so instead of "…"', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameCardProvider.overrideWith(
            (ref, id) => Stream<GameCardState?>.error(Exception('offline')),
          ),
        ],
        child: withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: GameMessageBubble(
                sessionId: 's1',
                viewerId: 'me',
                viewerIsSender: true,
                fallbackLabel: 'Snakes and Ladders',
                onTap: (_, __, ___) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Snakes and Ladders'), findsOneWidget);
    expect(find.text("Couldn't load right now"), findsOneWidget);
    expect(find.text('…'), findsNothing);
  });

  testWidgets('a stream error after a value keeps the card it had (T12 carry)', (
    tester,
  ) async {
    // An AsyncError that still carries the previous value is not "nothing
    // loaded": a transient realtime error used to replace a valid card
    // label with "Couldn't load right now".
    final controller = StreamController<GameCardState?>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameCardProvider.overrideWith((ref, id) => controller.stream)],
        child: withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: GameMessageBubble(
                sessionId: 's1',
                viewerId: 'me',
                viewerIsSender: true,
                fallbackLabel: 'Snakes and Ladders',
                onTap: (_, __, ___) {},
              ),
            ),
          ),
        ),
      ),
    );
    controller.add(_won);
    await tester.pumpAndSettle();
    expect(find.text('You won!'), findsOneWidget);

    controller.addError(Exception('socket dropped'));
    await tester.pumpAndSettle();
    expect(find.text('You won!'), findsOneWidget);
    expect(find.text("Couldn't load right now"), findsNothing);
  });
}
