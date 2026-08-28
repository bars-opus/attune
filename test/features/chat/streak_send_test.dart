import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('streakClipUploads', () {
    test('one upload plan per segment, in recording order', () {
      final plans = streakClipUploads(const [
        StreakSegment(path: '/tmp/a.mp4', duration: Duration(seconds: 60)),
        StreakSegment(path: '/tmp/b.mp4', duration: Duration(seconds: 20)),
      ]);

      expect(plans, hasLength(2));
      expect(plans[0].clipIndex, 0);
      expect(plans[1].clipIndex, 1);
      expect(plans.map((p) => p.localPath), ['/tmp/a.mp4', '/tmp/b.mp4']);
    });

    test('duration is carried per clip, not assumed to be a full segment', () {
      // A partial final segment is kept, so its real length must survive
      // to the row — otherwise the viewer's progress would be wrong.
      final plans = streakClipUploads(const [
        StreakSegment(path: '/tmp/a.mp4', duration: Duration(seconds: 60)),
        StreakSegment(path: '/tmp/b.mp4', duration: Duration(seconds: 17)),
      ]);

      expect(plans[0].durationMs, 60000);
      expect(plans[1].durationMs, 17000);
    });

    test('an empty recording produces no uploads', () {
      expect(streakClipUploads(const []), isEmpty);
    });
  });
}
