import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/support/chat_test_harness.dart';

/// RC-14: delivered_at was only ever stamped by a foregrounded chat or the
/// conversation list. A push the SDK hands to Dart (foreground display or
/// a tap) is proof the device has the message, so it acks too.
User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

const _newMessage = {'type': 'new_message', 'relationship_id': 'rel-1'};

void main() {
  test('picks the relationship out of a new_message payload only', () {
    expect(chatRelationshipIdForDeliveryAck(_newMessage), 'rel-1');
    expect(
      chatRelationshipIdForDeliveryAck({
        'type': 'message_reaction',
        'relationship_id': 'rel-1',
      }),
      isNull,
    );
    expect(chatRelationshipIdForDeliveryAck({'type': 'new_message'}), isNull);
    expect(chatRelationshipIdForDeliveryAck(null), isNull);
  });

  test('handleChatPushReceived marks the relationship delivered', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(_user('user-a')),
      ],
    );
    addTearDown(container.dispose);
    final service = container.read(oneSignalServiceProvider);

    await service.handleChatPushReceived(_newMessage);
    await service.handleChatPushReceived({
      'type': 'message_reaction',
      'relationship_id': 'rel-1',
    });
    await service.handleChatPushReceived({'type': 'new_message'});

    expect(repo.relationshipDeliveredCalls, ['rel-1']);
  });

  test('a push arriving while signed out never calls the RPC', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(oneSignalServiceProvider)
        .handleChatPushReceived(_newMessage);
    expect(repo.relationshipDeliveredCalls, isEmpty);
  });

  test('a failing ack never throws out of the push handler', () async {
    final container = ProviderContainer(
      overrides: [currentUserProvider.overrideWithValue(_user('user-a'))],
    );
    addTearDown(container.dispose);
    final service = OneSignalService(
      container.read(_refProvider),
      ackChatDelivery: (_) async => throw StateError('offline'),
    );
    await expectLater(service.handleChatPushReceived(_newMessage), completes);
  });
}

final _refProvider = Provider<Ref>((ref) => ref);
