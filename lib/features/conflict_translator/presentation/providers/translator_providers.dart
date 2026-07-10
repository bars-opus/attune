// lib/features/conflict_translator/presentation/providers/translator_providers.dart

import 'package:attune/features/conflict_translator/data/models/translator_request.dart';
import 'package:attune/features/conflict_translator/data/models/translator_response.dart';
import 'package:attune/features/conflict_translator/data/repositories/translator_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'translator_pattern_providers.dart' as translator_patterns;

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final translatorRepositoryProvider = Provider<TranslatorRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return TranslatorRepository(supabase);
});

final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response = await supabase
      .from('relationships')
      .select('id')
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .eq('status', 'active')
      .maybeSingle();

  return response?['id'] as String?;
});

final currentUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return supabase.auth.currentUser?.id;
});

final translatorStateProvider = StateProvider<TranslatorState>((ref) {
  return const TranslatorState();
});

class TranslatorState {
  final bool isLoading;
  final TranslatorResponse? response;
  final String? error;
  final bool isSheetOpen;

  const TranslatorState({
    this.isLoading = false,
    this.response,
    this.error,
    this.isSheetOpen = false,
  });

  TranslatorState copyWith({
    bool? isLoading,
    TranslatorResponse? response,
    String? error,
    bool? isSheetOpen,
  }) {
    return TranslatorState(
      isLoading: isLoading ?? this.isLoading,
      response: response ?? this.response,
      error: error ?? this.error,
      isSheetOpen: isSheetOpen ?? this.isSheetOpen,
    );
  }
}

final translatorNotifierProvider =
    StateNotifierProvider<TranslatorNotifier, TranslatorState>((ref) {
  return TranslatorNotifier(ref);
});

class TranslatorNotifier extends StateNotifier<TranslatorState> {
  final Ref _ref;

  TranslatorNotifier(this._ref) : super(const TranslatorState());

  Future<void> translate({
    required String message,
    required String relationshipId,
    TranslatorContext? context,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final repository = _ref.read(translatorRepositoryProvider);
      final response = await repository.translate(
        message: message,
        relationshipId: relationshipId,
        context: context,
      );

      state = state.copyWith(
        isLoading: false,
        response: response,
        isSheetOpen: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void closeSheet() {
    state = state.copyWith(isSheetOpen: false);
  }

  void reset() {
    state = const TranslatorState();
  }

  Future<void> logUsage({
    required bool choseRewrite,
    required String coreNeedIdentified,
    required String rewriteConfidence,
    required int originalLength,
    required int rewriteLength,
  }) async {
    final repository = _ref.read(translatorRepositoryProvider);
    final relationshipId = await _ref.read(currentRelationshipIdProvider.future);
    final userId = _ref.read(currentUserIdProvider);

    if (relationshipId == null || userId == null) {
      return;
    }

    await repository.logTranslatorUsage(
      userId: userId,
      relationshipId: relationshipId,
      coreNeedIdentified: coreNeedIdentified,
      rewriteConfidence: rewriteConfidence,
      originalLength: originalLength,
      rewriteLength: rewriteLength,
      choseRewrite: choseRewrite,
    );

    final service = _ref.read(translator_patterns.translatorPatternServiceProvider);
    final surfacedRecently = await service.hasInsightBeenSurfacedRecently(
      relationshipId: relationshipId,
      userId: userId,
    );

    if (!surfacedRecently && await service.shouldSurfaceInsight(relationshipId: relationshipId)) {
      await service.surfaceInsight(
        userId: userId,
        relationshipId: relationshipId,
      );
    }
  }
}
