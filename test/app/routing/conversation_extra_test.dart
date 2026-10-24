// A chat route rebuilt from go_router's saved state (iOS paste prompt, app
// resume) gets its extra back as a map. That used to throw a type error and
// put a red screen over the chat.
import 'dart:io';

import 'package:attune/app/routing/conversation_extra.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _convo(String id) => Conversation(
  id: id,
  relationshipId: id,
  partnerId: 'partner',
  name: 'Ama',
  updatedAt: DateTime(2026, 10, 23),
  relationshipStatus: 'active',
  availability: ConversationAvailability.active,
);

void main() {
  setUp(resetConversationRouteExtraForTesting);

  test('a conversation extra is returned as is', () {
    final c = _convo('rel-1');
    expect(conversationFromRouteExtra(c), same(c));
  });

  test('a map extra (restored route state) falls back to the last '
      'conversation instead of throwing', () {
    final c = _convo('rel-1');
    conversationFromRouteExtra(c);
    expect(
      conversationFromRouteExtra(<String, dynamic>{'id': 'rel-1'}),
      same(c),
    );
  });

  test('nothing pushed yet: null, so the route shows its own fallback', () {
    expect(conversationFromRouteExtra(<String, dynamic>{}), isNull);
    expect(conversationFromRouteExtra(null), isNull);
  });

  test('the router never casts a route extra straight to Conversation', () {
    final src = File('lib/app/routing/app_router.dart').readAsStringSync();
    expect(src.contains('as Conversation?'), isFalse);
    expect(src.contains('as Conversation;'), isFalse);
  });

  test('no route extra is cast directly anywhere in the router', () {
    final src = File('lib/app/routing/app_router.dart').readAsStringSync();
    expect(RegExp(r'state\.extra as ').hasMatch(src), isFalse);
  });

  test('a route opened with no extra on purpose never gets the last one', () {
    conversationFromRouteExtra(_convo('rel-1'));
    expect(conversationFromRouteExtra(null), isNull);
  });
}
