import 'dart:async';
import 'package:attune/features/conflict_translator/data/models/translator_request.dart';
import 'package:attune/features/conflict_translator/data/models/translator_response.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


/// The server's per-day cap (Spec 8, plan review I9) was reached: its own
/// answer, never a "try again" (sync audit 2026-10-18).
class TranslatorLimitReached implements Exception {
  const TranslatorLimitReached(this.message);

  final String message;
}

const kTranslatorLimitCopy =
    "You've used the translator a lot today. Try again tomorrow.";

/// What a failed translate call means to the sheet.
Exception translatorFailure(Object error) {
  if (error is FunctionException && error.status == 429) {
    final details = error.details;
    final message = details is Map ? details['message'] : null;
    return TranslatorLimitReached(
      message is String && message.isNotEmpty ? message : kTranslatorLimitCopy,
    );
  }
  if (error is TimeoutException) return Exception('TIMEOUT');
  return Exception('Failed to translate: $error');
}

class TranslatorRepository {
  final SupabaseClient _supabase;

  TranslatorRepository(this._supabase);

  Future<TranslatorResponse> translate({
    required String message,
    required String relationshipId,
    TranslatorRegister register = TranslatorRegister.nvc,
  }) async {
    try {
      final request = TranslatorRequest(
        message: message,
        relationshipId: relationshipId,
        register: register,
      );

      final response = await _supabase.functions.invoke(
        'translate-conflict',
        body: request.toJson(),
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Failed to translate: invalid response');
      }

      return TranslatorResponse.fromJson(data);
    } catch (e) {
      throw translatorFailure(e);
    }
  }

  Future<void> logTranslatorUsage({
    required String userId,
    required String relationshipId,
    required String coreNeedIdentified,
    required String rewriteConfidence,
    required int originalLength,
    required int rewriteLength,
    bool? choseRewrite,
  }) async {
    try {
      if (_supabase.auth.currentUser?.id == null) {
        return;
      }

      await _supabase.from('translator_logs').insert({
        'user_id': userId,
        'relationship_id': relationshipId,
        'core_need_identified': coreNeedIdentified,
        'rewrite_confidence': rewriteConfidence,
        'message_length_original': originalLength,
        'message_length_rewrite': rewriteLength,
        'chose_rewrite': choseRewrite,
      });
    } catch (e) {
      // Silently fail — logging is not critical
      debugPrint('Failed to log translator usage: $e');
    }
  }
}
