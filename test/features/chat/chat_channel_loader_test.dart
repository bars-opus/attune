import 'dart:async';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_channel_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// The server has no chat for this person: not a member, or the row is gone.
class _NoConversationRepository extends FakeChatRepository {
  _NoConversationRepository() : super(currentUserId: 'me');

  @override
  Future<Conversation?> getConversation(String relationshipId) async => null;
}

Future<ProviderContainer> _pumpLoader(
  WidgetTester tester,
  FakeChatRepository repository,
) async {
  final container = buildChatContainer(repository: repository, userId: 'me');
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: withScreenUtil(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => const ChatChannelLoader(
                                    relationshipId: 'rel',
                                  ),
                            ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  return container;
}

void main() {
  // A null result used to fall through `!snapshot.hasData` and spin
  // forever, and so did an error: a push for a chat the person can no
  // longer open left them on an endless loader with no way out.
  testWidgets('while loading, the spinner shows', (tester) async {
    final repository = FakeChatRepository(currentUserId: 'me')
      ..getConversationGate = Completer<void>();
    await _pumpLoader(tester, repository);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.getConversationGate!.complete();
    repository.getConversationError = StateError('stop here');
    await tester.pumpAndSettle();
  });

  testWidgets('no conversation shows a final, friendly state with a way back', (
    tester,
  ) async {
    await _pumpLoader(tester, _NoConversationRepository());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text("This conversation isn't available"), findsOneWidget);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a failed load shows the same state, not an endless spinner', (
    tester,
  ) async {
    final repository = FakeChatRepository(currentUserId: 'me')
      ..getConversationError = Exception('network');
    await _pumpLoader(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text("This conversation isn't available"), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
  });
}
