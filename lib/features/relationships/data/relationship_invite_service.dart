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

  /// A real https:// Universal/App Link — required so the QR code and
  /// shared link actually open (the stock iOS Camera app refuses to open
  /// custom schemes like attune://, and most share targets treat bare
  /// custom schemes as plain unclickable text). Opens the app directly via
  /// Associated Domains / App Links when installed; falls back to a web
  /// landing page (App Store / Play Store) otherwise. The association files
  /// this depends on live in the bars-opus/attune-invite-web repo; see
  /// main.dart's _handleDeepLink for the receiving side.
  String get deepLink => 'https://invite.attune.barsopus.com/i/$code';
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

  /// Returns the caller's current live pending invite (creating the first
  /// one if none exists) — safe to call on every load, per
  /// ATTUNE_MASTER_SPEC.md's "Invite codes are reusable until accepted or
  /// expired": it never mints a new code while one is still live.
  ///
  /// Pass [forceNew] only for the Day 7 pivot's "Invite someone else
  /// (doesn't cancel existing invite)" option — this always creates an
  /// additional pending invite instead of returning an existing one, up to
  /// the spec's cap of 3 concurrent pending invites per inviter (the
  /// function rejects a 4th with [RelationshipInviteException]).
  Future<RelationshipInvite> createInvite({bool forceNew = false}) async {
    final client = _safeClient;
    if (client == null) {
      // Never name the backend in a user-facing message (auth engine spec
      // §Failure Modes: no project refs / internal config in UI errors).
      throw const RelationshipInviteException(
        'Invites are unavailable right now. Please try again later.',
      );
    }

    try {
      final response = await client.functions
          .invoke('create-relationship-invite', body: {'force_new': forceNew})
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
      if (error is FunctionException && error.status == 409) {
        final details = error.details;
        final message = details is Map ? details['error'] as String? : null;
        // Two distinct 409s share this status: the spec's 3-concurrent-
        // pending-invites cap, and the newer already-active-relationship
        // guard (create-relationship-invite's own comment explains why
        // that check exists — a stale isPendingCouples flag on this
        // screen calling createInvite() right after a partner's
        // acceptance flipped this relationship to active). Callers need
        // to tell them apart: the cap is a real, showable error, but
        // "already active" means local state is stale and the fix is a
        // resync, not a message.
        throw RelationshipInviteException(
          message ?? 'You already have the maximum number of pending invites.',
          alreadyActiveRelationship:
              message?.toLowerCase().contains('already have an active') ??
              false,
        );
      }
      throw const RelationshipInviteException('Could not create invite.');
    }
  }

  Future<InviteAcceptance> acceptInvite(String inviteCode) async {
    final client = _safeClient;
    if (client == null) {
      // Never name the backend in a user-facing message (auth engine spec
      // §Failure Modes: no project refs / internal config in UI errors).
      throw const RelationshipInviteException(
        'Invites are unavailable right now. Please try again later.',
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
      // accept-invite/index.ts's handleError always replies with
      // {"error": "<message>"} plus a real status: 400 bad code, 404
      // invalid, 409 self-accept/already-accepted-by-someone-else, 410
      // expired. None of those are worth retrying with the same code, so
      // callers need to be able to tell them apart from a transient
      // network/timeout failure instead of showing "try again" for both.
      if (error is FunctionException) {
        final details = error.details;
        final message =
            details is Map ? details['error'] as String? : null;
        throw RelationshipInviteException(
          message ?? 'Could not accept invite.',
          retryable: error.status >= 500,
        );
      }
      throw const RelationshipInviteException(
        'Could not accept invite.',
        retryable: true,
      );
    }
  }

  Map<String, dynamic> _readMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const RelationshipInviteException('Unexpected invite response.');
  }
}

class RelationshipInviteException implements Exception {
  const RelationshipInviteException(
    this.message, {
    this.retryable = false,
    this.alreadyActiveRelationship = false,
  });

  final String message;

  /// False for the server's deterministic rejections (bad/expired/
  /// already-accepted/self-accept codes) — retrying acceptInvite with the
  /// same code cannot succeed, so callers should move the user forward
  /// instead of prompting them to try again. True for transient failures
  /// (network/timeout/5xx) where a retry might work.
  final bool retryable;

  /// True only for createInvite's "you already have an active
  /// relationship" 409 — see create-relationship-invite's own guard.
  /// Reaching this means the CALLER's local mode/pendingCouples state is
  /// stale (the relationship already went active server-side), not that
  /// the user did anything wrong, so UI callers should trigger a resync
  /// (relationshipModeResyncSignal) rather than show this as an error.
  final bool alreadyActiveRelationship;

  @override
  String toString() => message;
}
