import 'communication_style_result.dart';
import 'conflict_style_result.dart';
import 'love_language_result.dart';

class SharedQuizResult {
  final String quizType;
  final LoveLanguageResult? loveLanguageResult;
  final CommunicationStyleResult? communicationStyleResult;
  final ConflictStyleResult? conflictStyleResult;

  const SharedQuizResult._({
    required this.quizType,
    this.loveLanguageResult,
    this.communicationStyleResult,
    this.conflictStyleResult,
  });

  // No attachment: it is about the person who took it and is never shared
  // with a partner (Spec 5, F9 (3)).

  factory SharedQuizResult.loveLanguage(LoveLanguageResult result) {
    return SharedQuizResult._(
      quizType: 'love_language',
      loveLanguageResult: result,
    );
  }

  factory SharedQuizResult.communication(CommunicationStyleResult result) {
    return SharedQuizResult._(
      quizType: 'communication',
      communicationStyleResult: result,
    );
  }

  factory SharedQuizResult.conflict(ConflictStyleResult result) {
    return SharedQuizResult._(
      quizType: 'conflict',
      conflictStyleResult: result,
    );
  }
}
