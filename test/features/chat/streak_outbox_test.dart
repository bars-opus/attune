import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:flutter_test/flutter_test.dart';

PendingSend _streak({int? budget = 3}) => PendingSend(
      clientMessageId: 'cm1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      text: '',
      localMediaPath: '/tmp/streak.mp4',
      mediaMimeType: 'video/mp4',
      mediaType: 'streak',
      mediaDurationMs: 42000,
      streakViewsRemaining: budget,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('a streak round-trips through the cache with its budget', () {
    // The outbox survives an app kill mid-upload. A budget lost in
    // serialisation would resurrect the streak as a plain view-once.
    final restored = PendingSend.fromJson(_streak().toJson());

    expect(restored.streakViewsRemaining, 3);
    expect(restored.mediaType, 'streak');
    expect(restored.localMediaPath, '/tmp/streak.mp4');
  });

  test('a non-streak carries a null budget, not a default', () {
    // Defaulting to 1 would quietly make every video a one-view message
    // if its media type were ever mis-set.
    final video = PendingSend(
      clientMessageId: 'cm2',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      text: '',
      localMediaPath: '/tmp/v.mp4',
      mediaType: 'video',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    expect(video.streakViewsRemaining, isNull);
    expect(PendingSend.fromJson(video.toJson()).streakViewsRemaining, isNull);
  });

  test('copyWith preserves the budget', () {
    // _attemptSend copyWiths the pending row on every retry; a budget
    // dropped there would be lost on the second attempt, not the first.
    final retried = _streak().copyWith(attempts: 2);
    expect(retried.streakViewsRemaining, 3);
  });
}
