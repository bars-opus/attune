import 'dart:async';
import 'package:attune/features/conflict_translator/data/models/translator_request.dart';
import 'package:attune/features/conflict_translator/data/models/translator_response.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class TranslatorRepository {
  final SupabaseClient _supabase;

  TranslatorRepository(this._supabase);

  Future<TranslatorResponse> translate({
    required String message,
    required String relationshipId,
    TranslatorContext? context,
  }) async {
    try {
      final request = TranslatorRequest(
        message: message,
        context: context,
        relationshipId: relationshipId,
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
    } on TimeoutException {
      throw Exception('TIMEOUT');
    } catch (e) {
      throw Exception('Failed to translate: $e');
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
