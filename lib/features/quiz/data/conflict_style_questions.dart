// lib/features/quiz/data/conflict_style_questions.dart

import 'package:attune/features/quiz/domain/models/question_data.dart';

class ConflictStyleQuestions {
  static const String quizType = 'conflict';
  static const int instrumentVersion = 1;

  static List<QuestionData> getAllQuestions() {
    return [
      // Screen 1 — Questions 1 to 5
      QuestionData(
        globalIndex: 0,
        text:
            'During disagreement, I try to understand the concerns behind each person\'s position.',
        dimension: 'collaborating',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 1,
        text:
            'When an outcome matters strongly to me, I push firmly for my preferred position.',
        dimension: 'competing',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 2,
        text:
            'I sometimes step back from disagreement rather than address it immediately.',
        dimension: 'avoiding',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 3,
        text: 'I sometimes set aside what I want to preserve harmony.',
        dimension: 'accommodating',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 4,
        text: 'I look for a middle ground that each person can accept.',
        dimension: 'compromising',
        isReverseScored: false,
      ),

      // Screen 2 — Questions 6 to 10
      QuestionData(
        globalIndex: 5,
        text:
            'I invest time in finding an option that addresses everyone\'s important needs.',
        dimension: 'collaborating',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 6,
        text:
            'In disagreement, I argue strongly for the outcome I believe is right.',
        dimension: 'competing',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 7,
        text:
            'I postpone difficult conversations when engaging feels unhelpful or overwhelming.',
        dimension: 'avoiding',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 8,
        text:
            'I may go along with another person\'s preference even when mine is different.',
        dimension: 'accommodating',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 9,
        text:
            'I am willing to give up part of what I want to reach an agreement.',
        dimension: 'compromising',
        isReverseScored: false,
      ),

      // Screen 3 — Questions 11 to 15
      QuestionData(
        globalIndex: 10,
        text: 'I invite open discussion so we can solve the problem together.',
        dimension: 'collaborating',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 11,
        text:
            'When there is limited time, I am comfortable pressing for a clear decision.',
        dimension: 'competing',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 12,
        text:
            'I withdraw from a disagreement when I do not feel ready to continue it.',
        dimension: 'avoiding',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 13,
        text:
            'I may yield because the relationship feels more important than the issue.',
        dimension: 'accommodating',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 14,
        text:
            'I suggest that each person adjust their position to move forward.',
        dimension: 'compromising',
        isReverseScored: false,
      ),

      // Screen 4 — Questions 16 to 18
      QuestionData(
        globalIndex: 15,
        text:
            'I work with the other person to create a solution neither of us had considered at first.',
        dimension: 'collaborating',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 16,
        text:
            'I stand my ground when I believe an important principle is at stake.',
        dimension: 'competing',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 17,
        text:
            'I prefer to leave some disagreements alone rather than resolve every issue.',
        dimension: 'avoiding',
        isReverseScored: false,
      ),
    ];
  }
}
