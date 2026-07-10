// lib/features/quiz/services/quiz_notification_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuizNotificationService {
  final SupabaseClient _supabase;

  QuizNotificationService(this._supabase);

  /// Send notification to partner when user shares their quiz result
  Future<void> notifyPartnerQuizShared({
    required String partnerId,
    required String sharerName,
    required String quizType,
  }) async {
    final profileRes =
        await _supabase
            .from('profiles')
            .select('display_name')
            .eq('id', partnerId)
            .maybeSingle();

    final partnerName = profileRes?['display_name'] as String? ?? 'partner';

    String title;
    String body;

    switch (quizType) {
      case 'attachment':
        title = '$sharerName shared their attachment style';
        body = 'See how your styles compare in your profile.';
        break;
      case 'love_language':
        title = '$sharerName shared their love language';
        body = 'See their result in your profile.';
        break;
      case 'communication':
        title = '$sharerName shared their communication style';
        body = 'See your communication profile.';
        break;
      case 'conflict':
        title = '$sharerName shared their conflict style';
        body = 'See how you both handle disagreements.';
        break;
      default:
        title = '$sharerName shared a quiz result';
        body = 'Check it out in your profile.';
    }

    debugPrint(
      '[quiz] notify_partner_quiz_shared partner=$partnerId '
      'partnerName=$partnerName title="$title" body="$body"',
    );
  }
}
