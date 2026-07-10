// lib/features/quiz/data/communication_style_questions.dart
import 'package:attune/features/quiz/domain/models/question_data.dart';


class CommunicationStyleQuestions {
  static const String quizType = 'communication';
  static const int instrumentVersion = 1;

  static List<QuestionData> getAllQuestions() {
    return [
      // Screen 1 — Questions 1 to 5
      QuestionData(
        globalIndex: 0,
        text: 'I express my needs clearly and directly.',
        dimension: 'assertive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 1,
        text: 'I hold back my true feelings to avoid disagreement.',
        dimension: 'passive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 2,
        text: 'When I strongly disagree, I interrupt before the other person has finished.',
        dimension: 'aggressive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 3,
        text: 'When I am frustrated, I sometimes use sarcasm instead of saying what is wrong.',
        dimension: 'passive_aggressive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 4,
        text: 'I feel able to set a boundary respectfully.',
        dimension: 'assertive',
        isReverseScored: false,
      ),

      // Screen 2 — Questions 6 to 10
      QuestionData(
        globalIndex: 5,
        text: 'I find it hard to say no when I do not want to agree.',
        dimension: 'passive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 6,
        text: 'When something goes wrong, I quickly focus on what the other person did wrong.',
        dimension: 'aggressive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 7,
        text: 'I sometimes agree to something and show my resentment later.',
        dimension: 'passive_aggressive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 8,
        text: 'I make room for another person\'s view while explaining my own.',
        dimension: 'assertive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 9,
        text: 'I avoid raising an issue even when it matters to me.',
        dimension: 'passive',
        isReverseScored: false,
      ),

      // Screen 3 — Questions 11 to 15
      QuestionData(
        globalIndex: 10,
        text: 'When I am frustrated, my words can become harsh or dismissive.',
        dimension: 'aggressive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 11,
        text: 'I sometimes show displeasure by becoming deliberately unresponsive instead of explaining it.',
        dimension: 'passive_aggressive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 12,
        text: 'I can disagree without attacking the other person\'s character.',
        dimension: 'assertive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 13,
        text: 'I set aside my own needs even when I would prefer to speak up.',
        dimension: 'passive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 14,
        text: 'I take over conversations when I feel strongly about something.',
        dimension: 'aggressive',
        isReverseScored: false,
      ),

      // Screen 4 — Questions 16 to 20
      QuestionData(
        globalIndex: 15,
        text: 'When I feel hurt, I sometimes make an indirect critical remark.',
        dimension: 'passive_aggressive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 16,
        text: 'I can ask for what I need without demanding it.',
        dimension: 'assertive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 17,
        text: 'I struggle to speak up when other people may disagree.',
        dimension: 'passive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 18,
        text: 'During conflict, I make accusations about the other person\'s behavior.',
        dimension: 'aggressive',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 19,
        text: 'I avoid addressing an issue directly but let my frustration show in other ways.',
        dimension: 'passive_aggressive',
        isReverseScored: false,
      ),
    ];
  }
}
