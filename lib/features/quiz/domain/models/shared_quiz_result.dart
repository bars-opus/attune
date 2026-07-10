import 'attachment_result.dart';
import 'communication_style_result.dart';
import 'conflict_style_result.dart';
import 'love_language_result.dart';

class SharedQuizResult {
  final String quizType;
  final AttachmentResult? attachmentResult;
  final LoveLanguageResult? loveLanguageResult;
  final CommunicationStyleResult? communicationStyleResult;
  final ConflictStyleResult? conflictStyleResult;

  const SharedQuizResult._({
    required this.quizType,
    this.attachmentResult,
    this.loveLanguageResult,
    this.communicationStyleResult,
    this.conflictStyleResult,
  });

  factory SharedQuizResult.attachment(AttachmentResult result) {
    return SharedQuizResult._(quizType: 'attachment', attachmentResult: result);
  }

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
