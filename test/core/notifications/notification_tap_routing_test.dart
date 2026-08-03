import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thirty_six_question_invite payload extraction', () {
    test('sessionId and chapter present and well-formed', () {
      final data = {
        'type': 'thirty_six_question_invite',
        'session_id': 'sess-1',
        'chapter': 2,
      };
      final sessionId = data['session_id'] as String?;
      final chapter = data['chapter'] as int?;
      expect(sessionId, 'sess-1');
      expect(chapter, 2);
    });

    test('missing chapter is null, not a crash', () {
      final data = {'type': 'thirty_six_question_invite', 'session_id': 'sess-1'};
      final chapter = data['chapter'] as int?;
      expect(chapter, isNull);
    });
  });

  group('forum_topic_activated / forum_activity / forum_quiet payload extraction', () {
    test('topic_id present', () {
      final data = {'type': 'forum_activity', 'topic_id': 'topic-1'};
      final topicId = data['topic_id'] as String?;
      expect(topicId, 'topic-1');
    });

    test('empty topic_id treated as absent', () {
      final data = {'type': 'forum_quiet', 'topic_id': ''};
      final topicId = data['topic_id'] as String?;
      expect(topicId != null && topicId.isNotEmpty, isFalse);
    });
  });

  group('opinion_liked / opinion_commented / opinion_comment_reply payload extraction', () {
    test('opinion_id present', () {
      final data = {'type': 'opinion_liked', 'opinion_id': 'op-1'};
      final opinionId = data['opinion_id'] as String?;
      expect(opinionId, 'op-1');
    });

    test('missing opinion_id is null', () {
      final data = {'type': 'opinion_commented'};
      final opinionId = data['opinion_id'] as String?;
      expect(opinionId, isNull);
    });
  });
}
