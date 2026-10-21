import 'dart:io';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/utils/conversation_preview.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _withLast(Message message) => Conversation(
  id: 'c1',
  relationshipId: 'rel-1',
  partnerId: 'user-b',
  name: 'Ama',
  availability: ConversationAvailability.active,
  unreadCount: 0,
  updatedAt: DateTime.utc(2026, 1, 1),
  relationshipStatus: 'active',
  lastMessage: message,
);

Message _streak({String content = ''}) => Message(
  id: 'm1',
  clientMessageId: 'cm1',
  relationshipId: 'rel-1',
  senderId: 'user-a',
  content: content,
  createdAt: DateTime.utc(2026, 1, 1),
  status: MessageStatus.sent,
  isMine: false,
  mediaType: 'streak',
);

void main() {
  test('the conversations preview says Streak and never the caption', () {
    final preview = conversationPreviewText(
      _withLast(_streak(content: 'a private caption')),
    );

    expect(preview, 'Streak');
    expect(
      preview,
      isNot(contains('a private caption')),
      reason:
          'a caption is view-time only — revealing it in the list '
          'defeats the point of an unopened streak',
    );
  });

  test('a streak with no caption reads the same as one with', () {
    // Identical previews either way: a differing label would leak whether
    // a caption exists, which is itself information about the message.
    expect(conversationPreviewText(_withLast(_streak())), 'Streak');
  });

  test('other media types still append their captions', () {
    final photo = conversationPreviewText(
      _withLast(
        Message(
          id: 'm2',
          clientMessageId: 'cm2',
          relationshipId: 'rel-1',
          senderId: 'user-a',
          content: 'at the beach',
          createdAt: DateTime.utc(2026, 1, 1),
          status: MessageStatus.sent,
          isMine: false,
          mediaType: 'image',
        ),
      ),
    );
    expect(photo, 'Photo: at the beach');
  });

  test('a view is spent once per viewing, not once per clip', () {
    // A three-clip streak must not burn a three-view budget in one watch,
    // and completion and an explicit dismissal cannot both charge it
    // either. Task 5b: the spend fires at presentation, memoised per open,
    // and every attempt (the first and any retry) carries the SAME open id,
    // which the server charges once (mark_streak_viewed(p_message_id,
    // p_open_id)). Behaviour is pinned by streak_viewer_presented_gate_test;
    // this pins the shape that makes it hold.
    final src =
        File(
          'lib/features/chat/presentation/screens/streak_viewer_screen.dart',
        ).readAsStringSync();

    // One first spend per open: memoised, never replaced.
    expect(src, contains('_spend ??= _attemptSpend();'));
    expect(
      RegExp(r'_spend = ').allMatches(src).length,
      0,
      reason: 'a reassigned spend future is a second first spend',
    );

    // markViewed must be reachable from exactly one place, with the open id.
    final calls = RegExp(r'markViewed\(').allMatches(src).toList();
    expect(
      calls,
      hasLength(1),
      reason: 'more than one call site can double-charge',
    );
    expect(src, contains('markViewed(_messageId, openId: _openId)'));

    // One open id per viewer, minted once: a retry with a fresh id would be
    // a second view server-side.
    expect(src, contains('final String _openId = const Uuid().v4();'));
    expect(RegExp(r'Uuid\(\)').allMatches(src).length, 1);
    expect(RegExp(r'openId:').allMatches(src).length, 1);

    // Fired at presentation (video and photo), not on exit.
    expect(
      RegExp(r'_spendNow\(\);').allMatches(src).length,
      3,
      reason: 'video presented, photo first frame, and the settle',
    );
  });

  test('streaks carry no caption at all', () {
    // Captions were removed to keep capture to record -> send or cancel.
    // The viewer must not have grown one back, and the preview must still
    // return a bare label.
    final viewer =
        File(
          'lib/features/chat/presentation/screens/streak_viewer_screen.dart',
        ).readAsStringSync();
    expect(
      viewer,
      isNot(contains('caption')),
      reason: 'the viewer has no caption to render',
    );

    final preview =
        File(
          'lib/features/chat/domain/utils/conversation_preview.dart',
        ).readAsStringSync();
    expect(
      preview,
      contains("if (message.mediaType == 'streak') return label;"),
      reason: 'the preview must return the bare label for a streak',
    );
  });
}
