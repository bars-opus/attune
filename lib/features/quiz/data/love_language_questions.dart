// lib/features/quiz/data/love_language_questions.dart

import 'package:attune/features/quiz/domain/models/question_data.dart';

import '../presentation/widgets/question_screen.dart';

class LoveLanguageQuestions {
  static List<QuestionData> getAllQuestions() {
    return [
      // Screen 1 — Questions 1 to 5
      QuestionData(
        globalIndex: 0,
        text: 'I feel most loved when my partner tells me they appreciate me.',
        dimension: 'words',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 1,
        text: 'I value undivided attention from my partner more than gifts.',
        dimension: 'quality_time',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 2,
        text: 'A thoughtful gift makes me feel truly seen and cared for.',
        dimension: 'gifts',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 3,
        text: 'I feel loved when my partner does something helpful for me.',
        dimension: 'acts',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 4,
        text: 'Physical affection is one of the most important ways I feel connected.',
        dimension: 'touch',
        isReverseScored: false,
      ),

      // Screen 2 — Questions 6 to 10
      QuestionData(
        globalIndex: 5,
        text: 'Hearing "I love you" matters more to me than almost anything else.',
        dimension: 'words',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 6,
        text: 'Spending quality time together is my favourite way to connect.',
        dimension: 'quality_time',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 7,
        text: 'Receiving a meaningful gift makes me feel valued and appreciated.',
        dimension: 'gifts',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 8,
        text: 'I feel cared for when my partner takes care of something for me.',
        dimension: 'acts',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 9,
        text: 'A hug or a touch can make me feel instantly closer to my partner.',
        dimension: 'touch',
        isReverseScored: false,
      ),

      // Screen 3 — Questions 11 to 15
      QuestionData(
        globalIndex: 10,
        text: 'Words of encouragement from my partner mean a lot to me.',
        dimension: 'words',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 11,
        text: 'I feel closest to my partner when we are doing something together.',
        dimension: 'quality_time',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 12,
        text: 'The thought behind a gift matters more to me than the gift itself.',
        dimension: 'gifts',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 13,
        text: 'When my partner helps me with something, I feel supported and loved.',
        dimension: 'acts',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 14,
        text: 'Feeling my partner\'s touch makes me feel safe and loved.',
        dimension: 'touch',
        isReverseScored: false,
      ),
    ];
  }
}
