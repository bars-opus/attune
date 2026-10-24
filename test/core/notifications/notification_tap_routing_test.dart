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

  group('opinion_liked / opinion_commented / opinion_comment_reply payload extraction', () {
    test('opinion_id present', () {
      final data = <String, dynamic>{'type': 'opinion_liked', 'opinion_id': 'op-1'};
      final opinionId = data['opinion_id'] as String?;
      expect(opinionId, 'op-1');
    });

    test('missing opinion_id is null', () {
      final data = <String, dynamic>{'type': 'opinion_commented'};
      final opinionId = data['opinion_id'] as String?;
      expect(opinionId, isNull);
    });
  });
}
