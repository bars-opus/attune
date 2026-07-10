// lib/features/quiz/data/attachment_questions.dart
import 'package:attune/features/quiz/domain/models/question_data.dart';


class AttachmentQuestions {
  static List<QuestionData> getAllQuestions() {
    return [
      // Screen 1 — Questions 1 to 5
      QuestionData(
        globalIndex: 0,
        text: 'I worry about whether my partner really cares about me.',
        dimension: 'A',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 1,
        text: 'I prefer not to rely on my partner too much.',
        dimension: 'V',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 2,
        text: 'I often wonder if my partner truly wants to be with me.',
        dimension: 'A',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 3,
        text: 'I find it hard to let myself depend on someone I am with.',
        dimension: 'V',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 4,
        text: 'I feel comfortable sharing my feelings with my partner.',
        dimension: 'A',
        isReverseScored: true, // R
      ),

      // Screen 2 — Questions 6 to 10
      QuestionData(
        globalIndex: 5,
        text: 'I get uncomfortable when a partner wants to be very close.',
        dimension: 'V',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 6,
        text: 'I need a lot of reassurance that my partner loves me.',
        dimension: 'A',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 7,
        text: 'I find it easy to be emotionally open with my partner.',
        dimension: 'V',
        isReverseScored: true, // R
      ),
      QuestionData(
        globalIndex: 8,
        text: 'I worry a lot that my partner will not want to stay with me.',
        dimension: 'A',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 9,
        text: 'I keep my guard up even in relationships I really care about.',
        dimension: 'V',
        isReverseScored: false,
      ),

      // Screen 3 — Questions 11 to 15
      QuestionData(
        globalIndex: 10,
        text: 'When my partner is away I find myself worrying about them.',
        dimension: 'A',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 11,
        text: 'I feel suffocated when someone gets too close too fast.',
        dimension: 'V',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 12,
        text: 'I feel secure knowing my partner is there for me.',
        dimension: 'A',
        isReverseScored: true, // R
      ),
      QuestionData(
        globalIndex: 13,
        text: 'I find it difficult to trust a partner completely.',
        dimension: 'V',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 14,
        text: 'Small things my partner does can make me feel unloved.',
        dimension: 'A',
        isReverseScored: false,
      ),

      // Screen 4 — Questions 16 to 20
      QuestionData(
        globalIndex: 15,
        text: 'Being emotionally intimate with someone feels natural to me.',
        dimension: 'V',
        isReverseScored: true, // R
      ),
      QuestionData(
        globalIndex: 16,
        text: 'I often feel like my partner does not want to be as close as I do.',
        dimension: 'A',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 17,
        text: 'I tend to keep my romantic partner at a certain distance.',
        dimension: 'V',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 18,
        text: 'I do not often worry about being abandoned by the person I am with.',
        dimension: 'A',
        isReverseScored: true, // R
      ),
      QuestionData(
        globalIndex: 19,
        text: 'Opening up fully to a partner makes me feel exposed.',
        dimension: 'V',
        isReverseScored: false,
      ),

      // Screen 5 — Questions 21 to 25
      QuestionData(
        globalIndex: 20,
        text: 'I sometimes feel my partner does not value me as much as I value them.',
        dimension: 'A',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 21,
        text: 'I am comfortable with my partner knowing most things about me.',
        dimension: 'V',
        isReverseScored: true, // R
      ),
      QuestionData(
        globalIndex: 22,
        text: 'I get anxious when my partner does not respond quickly.',
        dimension: 'A',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 23,
        text: 'I value my independence more than closeness in a relationship.',
        dimension: 'V',
        isReverseScored: false,
      ),
      QuestionData(
        globalIndex: 24,
        text: 'I feel relaxed and confident in my relationship most of the time.',
        dimension: 'A',
        isReverseScored: true, // R
      ),
    ];
  }
}
