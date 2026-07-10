import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RelationshipInvite {
  const RelationshipInvite({
    required this.relationshipId,
    required this.code,
    required this.expiresAt,
  });

  final String relationshipId;
  final String code;
  final DateTime expiresAt;

  String get deepLink => 'attune://invite?code=$code';
}

class InviteAcceptance {
  const InviteAcceptance({
    required this.relationshipId,
    required this.status,
    required this.idempotent,
  });

  final String relationshipId;
  final String status;
  final bool idempotent;
}

class RelationshipInviteService {
  RelationshipInviteService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static const timeout = Duration(seconds: 30);

  SupabaseClient? get _safeClient {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => _safeClient != null;

  Future<RelationshipInvite> createInvite() async {
    final client = _safeClient;
    if (client == null) {
      throw const RelationshipInviteException(
        'Supabase is not configured for this local run.',
      );
    }

    try {
      final response = await client.functions
          .invoke('create-relationship-invite')
          .timeout(timeout);
      final data = _readMap(response.data);

      return RelationshipInvite(
        relationshipId: data['relationship_id'] as String,
        code: data['invite_code'] as String,
        expiresAt: DateTime.parse(data['invite_expires_at'] as String),
      );
    } catch (error) {
      debugPrint('[relationship-invite] create failed: ${error.runtimeType}');
      if (error is RelationshipInviteException) rethrow;
      throw const RelationshipInviteException('Could not create invite.');
    }
  }

  Future<InviteAcceptance> acceptInvite(String inviteCode) async {
    final client = _safeClient;
    if (client == null) {
      throw const RelationshipInviteException(
        'Supabase is not configured for this local run.',
      );
    }

    try {
      final response = await client.functions
          .invoke('accept-invite', body: {'invite_code': inviteCode})
          .timeout(timeout);
      final data = _readMap(response.data);

      return InviteAcceptance(
        relationshipId: data['relationship_id'] as String,
        status: data['status'] as String,
        idempotent: data['idempotent'] as bool? ?? false,
      );
    } catch (error) {
      debugPrint('[relationship-invite] accept failed: ${error.runtimeType}');
      if (error is RelationshipInviteException) rethrow;
      throw const RelationshipInviteException('Could not accept invite.');
    }
  }

  Map<String, dynamic> _readMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const RelationshipInviteException('Unexpected invite response.');
  }
}

class RelationshipInviteException implements Exception {
  const RelationshipInviteException(this.message);

  final String message;

  @override
  String toString() => message;
}
