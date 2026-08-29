import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the message column list selects streak_views_remaining', () {
    // A streak row fetched without its budget parses as null, and the
    // bubble then reads 0 views remaining — so a freshly sent streak
    // renders as already expired, or does not render at all.
    final src = File(
      'lib/features/chat/data/repositories/supabase_chat_repository.dart',
    ).readAsStringSync();

    final block = RegExp(r'_messageColumns\s*=\s*((?:\s*.[^;]*?)+);')
        .firstMatch(src)
        ?.group(1);

    expect(block, isNotNull, reason: '_messageColumns not found');
    expect(
      block,
      contains('streak_views_remaining'),
      reason: 'a streak cannot render without its view budget',
    );
    // Guard the neighbours too: this list is edited by hand and a
    // dropped column fails silently at parse time, never at compile time.
    expect(block, contains('media_type'));
    expect(block, contains('is_view_once'));
  });

  test('Message.fromRow keeps a streak budget of zero distinct from null',
      () {
    // Null means "not a streak"; zero means "spent". Collapsing them
    // makes an unspent streak look expired.
    final spent = Message.fromRow(const {
      'id': 'm1',
      'relationship_id': 'rel-1',
      'sender_id': 'user-a',
      'client_message_id': 'cm1',
      'content': '',
      'created_at': '2026-01-01T00:00:00Z',
      'media_type': 'streak',
      'streak_views_remaining': 0,
    }, currentUserId: 'user-b');

    final fresh = Message.fromRow(const {
      'id': 'm2',
      'relationship_id': 'rel-1',
      'sender_id': 'user-a',
      'client_message_id': 'cm2',
      'content': '',
      'created_at': '2026-01-01T00:00:00Z',
      'media_type': 'streak',
      'streak_views_remaining': 1,
    }, currentUserId: 'user-b');

    expect(spent.streakViewsRemaining, 0);
    expect(fresh.streakViewsRemaining, 1);
    expect(spent.isStreak, isTrue);
    expect(fresh.isStreak, isTrue);
  });

  test('the streak viewer signs its clip keys before playback', () {
    // streak_clips.media_url holds a raw STORAGE KEY, and the bucket is
    // private. Passing it straight to VideoPlayerController.networkUrl
    // requests a path that is not a URL at all, so playback fails with no
    // useful error. Every other media path signs first.
    final src = File(
      'lib/features/chat/presentation/screens/streak_viewer_screen.dart',
    ).readAsStringSync();

    expect(
      src,
      contains('createSignedMediaUrl'),
      reason: 'a raw storage key is not playable',
    );

    // And the signed value must be what reaches the player.
    final playsRawKey = RegExp(
      r'networkUrl\(\s*Uri\.parse\(\s*_clips\[[^\]]+\]\.mediaUrl',
    ).hasMatch(src);
    expect(
      playsRawKey,
      isFalse,
      reason: 'the player must receive the signed URL, not the key',
    );
  });
}
