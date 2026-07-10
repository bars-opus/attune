// lib/features/safety/presentation/providers/safety_providers.dart

import 'dart:convert';

import 'package:attune/features/safety/data/services/safety_service.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final safetyConfigProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final raw = await rootBundle.loadString(
    'assets/config/safety_triggers.v1.json',
  );
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    return const <String, dynamic>{};
  }

  return decoded;
});

final safetyServiceProvider = Provider<SafetyService>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return SafetyService(supabase);
});

final quickExitProvider = Provider<void Function(BuildContext)>((ref) {
  return (BuildContext context) {
    QuickExitService.execute(context);
  };
});

final currentUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return supabase.auth.currentUser?.id;
});

final safetyEventsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) {
    return const <Map<String, dynamic>>[];
  }

  return ref.read(safetyServiceProvider).getMySafetyResourceEvents();
});
