// Spec 1 W9e test support: a journey, the Healing functions and the
// repository, without Supabase.
import 'dart:async';

import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/data/repositories/healing_repository.dart';
import 'package:attune/features/healing/services/healing_generation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const supportCardText =
    "If things feel heavy right now, you don't have to carry it alone. Support is here if you want it.";

User testUser(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-04T00:00:00Z',
);

HealingJourney testJourney({
  String id = 'j1',
  String userId = 'ama',
  int stage = 2,
  String postMortemStatus = 'not_started',
  String? postMortemObservation,
  String portraitStatus = 'not_started',
  String? portraitText,
}) => HealingJourney.fromJson({
  'id': id,
  'user_id': userId,
  'relationship_id': null,
  'breakup_at': '2026-10-01T00:00:00Z',
  'breakup_at_source': 'user_reported',
  'status': 'active',
  'current_stage': stage,
  'reflection_answers': <String, dynamic>{},
  'reflection_completed_at': '2026-10-02T00:00:00Z',
  'post_mortem_status': postMortemStatus,
  'post_mortem_observation': postMortemObservation,
  'post_mortem_confidence': postMortemObservation == null ? null : 'low',
  'post_mortem_reflection_prompt': null,
  'portrait_status': portraitStatus,
  'portrait_text': portraitText,
  'portrait_prompt': null,
  'created_at': '2026-10-02T00:00:00Z',
  'updated_at': '2026-10-02T00:00:00Z',
});

/// The two functions: each call takes the next answer; [gate], when set,
/// holds every answer until it completes.
class FakeHealingGeneration implements HealingGenerationService {
  FakeHealingGeneration(this.answers);

  final List<Map<String, dynamic>?> answers;
  final calls = <String>[];
  Completer<void>? gate;

  Future<Map<String, dynamic>?> _next(String what) async {
    calls.add(what);
    await gate?.future;
    return answers.isEmpty ? null : answers.removeAt(0);
  }

  @override
  Future<Map<String, dynamic>?> generatePostMortem({
    required String journeyId,
  }) => _next('post_mortem:$journeyId');

  @override
  Future<Map<String, dynamic>?> generatePortrait({required String journeyId}) =>
      _next('portrait:$journeyId');
}

/// Records what a stage screen saves; [latest] answers each account's
/// journey, and [hold] keeps the next account's read open.
class FakeHealingRepository implements HealingRepository {
  final saved = <String>[];
  final latest = <String, HealingJourney?>{};
  String account = 'ama';
  Completer<void>? hold;

  @override
  Future<void> completePostMortem({
    required String journeyId,
    required String status,
    String? observation,
    String? confidence,
    String? reflectionPrompt,
  }) async => saved.add('post_mortem:$status');

  @override
  Future<void> completePortrait({
    required String journeyId,
    required String status,
    String? portraitText,
    String? portraitReflection,
    String? reflectionPrompt,
  }) async => saved.add('portrait:$status');

  @override
  Future<HealingJourney?> getLatestJourney() async {
    final who = account;
    if (who != 'ama') await hold?.future;
    return latest[who];
  }

  @override
  Future<Map<String, dynamic>?> getStartableRelationship() async => null;

  @override
  Future<Map<String, dynamic>?> getLatestReadinessAttempt(
    String journeyId,
  ) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
