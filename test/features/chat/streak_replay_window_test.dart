import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/utils/streak_replay_window.dart';
import 'package:flutter_test/flutter_test.dart';

Message _streak({
  required bool isMine,
  required int remaining,
  DateTime? viewedAt,
}) => Message(
  id: 's1',
  clientMessageId: 'c1',
  relationshipId: 'r1',
  senderId: isMine ? 'me' : 'partner',
  content: '',
  createdAt: DateTime(2026, 10, 19, 10),
  status: MessageStatus.delivered,
  isMine: isMine,
  mediaType: 'streak',
  streakViewsRemaining: remaining,
  viewedAt: viewedAt,
);

void main() {
  final now = DateTime(2026, 10, 19, 12);

  test('the window is 30 minutes, as on the server', () {
    expect(kStreakReplayWindow, const Duration(minutes: 30));
  });

  test('an unopened streak keeps its full budget', () {
    expect(streakViewsAvailable(_streak(isMine: false, remaining: 3), now), 3);
  });

  test('a missing budget reads as nothing left', () {
    final m = Message(
      id: 's2',
      clientMessageId: 'c2',
      relationshipId: 'r1',
      senderId: 'partner',
      content: '',
      createdAt: DateTime(2026, 10, 19, 10),
      status: MessageStatus.delivered,
      isMine: false,
      mediaType: 'streak',
    );
    expect(streakViewsAvailable(m, now), 0);
  });

  test('inside the window the replay budget stands', () {
    final m = _streak(
      isMine: false,
      remaining: 2,
      viewedAt: now.subtract(const Duration(minutes: 29)),
    );
    expect(streakViewsAvailable(m, now), 2);
  });

  test('past the window the bubble reads Opened without a tap', () {
    // "Play 2x" used to stay up until the person tapped and the server
    // refused — by which time the clip had already played once more.
    final m = _streak(
      isMine: false,
      remaining: 2,
      viewedAt: now.subtract(kStreakReplayWindow),
    );
    expect(streakViewsAvailable(m, now), 0);
  });

  test('a viewedAt ahead of the device clock does not expire it', () {
    // Server time a little ahead of a slow phone clock is not "expired".
    final m = _streak(
      isMine: false,
      remaining: 2,
      viewedAt: now.add(const Duration(minutes: 5)),
    );
    expect(streakViewsAvailable(m, now), 2);
  });

  test('the window never governs the sender', () {
    final m = _streak(
      isMine: true,
      remaining: 2,
      viewedAt: now.subtract(const Duration(hours: 2)),
    );
    expect(streakViewsAvailable(m, now), 2);
  });

  test(
    'the streak bubble reads the budget through the window rule',
    () {
      final src =
          File(
            'lib/features/chat/presentation/widgets/message_bubble.dart',
          ).readAsStringSync();
      expect(src, contains('streakViewsAvailable(message'));
    },
  );

  test('clips are fetched through the gated RPC, never the table', () {
    final src =
        File(
          'lib/features/chat/data/repositories/streak_repository.dart',
        ).readAsStringSync();
    final fetch = src.substring(src.indexOf('fetchClips('));
    expect(fetch, contains("'streak_clips_for_viewing'"));
    expect(fetch, contains('.rpc('));
    expect(fetch, isNot(contains(".from('streak_clips')")));
  });
}
