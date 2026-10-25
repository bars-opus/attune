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
        // Spec 1 W2 interim guard (review I-5): no account yet. The code is
        // never shown; finishing sign-up resolves it.
        if (message == kSignUpIncompleteError) {
          throw const RelationshipInviteException(
            'Could not create invite.',
            signUpIncomplete: true,
          );
        }
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

  /// How long the caller has been waiting on a partner: since their oldest
  /// never-accepted invite, expired ones included (Spec 5, plan review C3),
  /// so a fresh code never resets it. Null when there is none or the server
  /// cannot say.
  Future<Duration?> inviteAge() async {
    final client = _safeClient;
    if (client == null) return null;
    try {
      final seconds = await client.rpc('get_my_invite_age').timeout(timeout);
      return seconds is num ? Duration(seconds: seconds.toInt()) : null;
    } catch (error) {
      debugPrint('[relationship-invite] age failed: ${error.runtimeType}');
      return null;
    }
  }

  /// Day 7's "Use Attune on my own for now" (Spec 5, plan review C2):
  /// removes the caller's own never-accepted invites; the mode sync then
  /// resolves to personal mode.
  Future<void> withdrawPendingInvites() async {
    final client = _safeClient;
    if (client == null) {
      throw const RelationshipInviteException(
        'Invites are unavailable right now. Please try again later.',
      );
    }
    try {
      await client.rpc('withdraw_my_pending_invites').timeout(timeout);
    } catch (error) {
      debugPrint('[relationship-invite] withdraw failed: ${error.runtimeType}');
      throw const RelationshipInviteException('Could not update your invite.');
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
      throw inviteAcceptFailure(error);
    }
  }

  Map<String, dynamic> _readMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const RelationshipInviteException('Unexpected invite response.');
  }
}

/// accept-invite's refusal for someone already in an active or paused
/// relationship (sync audit I-8). Matched on its opening words, which the
/// server keeps fixed (supabase/functions/accept-invite/index.test.ts).
const kAlreadyInRelationshipPrefix = "You're already in a relationship";

/// Both invite functions' 409 for a signed-in caller with no account yet
/// under flow_signin_v2 (supabase/functions/_shared/sign_up_guard.ts).
const kSignUpIncompleteError = 'signup:incomplete';

/// Their 503 when the server can't read flow_signin_v2 (the guard fails
/// closed): retryable, and never shown.
const kFlagsUnavailableError = 'flags:unavailable';

/// What a failed acceptInvite call means. accept-invite's handleError
/// always replies with {"error": "<message>"} plus a real status: 400 bad
/// code, 404 invalid, 409 self-accept/already-accepted/already in a
/// relationship, 410 expired. None of those are worth retrying with the
/// same code, so callers can tell them apart from a transient
/// network/timeout failure instead of showing "try again" for both.
RelationshipInviteException inviteAcceptFailure(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    final message = details is Map ? details['error'] as String? : null;
    // Spec 1 W2 interim guard (review I-5): no account yet. Retryable, so
    // the stored invite is kept and accepted once sign-up is finished (an
    // unfinished account goes on from /home to /onboarding, whose consent
    // step sends it to /signup under flow_signin_v2).
    if (error.status == 409 && message == kSignUpIncompleteError) {
      return const RelationshipInviteException(
        'Could not accept invite.',
        retryable: true,
        signUpIncomplete: true,
      );
    }
    if (message == kFlagsUnavailableError) {
      return const RelationshipInviteException(
        'Could not accept invite.',
        retryable: true,
      );
    }
    return RelationshipInviteException(
      message ?? 'Could not accept invite.',
      retryable: error.status >= 500,
      alreadyInRelationship:
          error.status == 409 &&
          (message ?? '').startsWith(kAlreadyInRelationshipPrefix),
    );
  }
  return const RelationshipInviteException(
    'Could not accept invite.',
    retryable: true,
  );
}

class RelationshipInviteException implements Exception {
  const RelationshipInviteException(
    this.message, {
    this.retryable = false,
    this.alreadyActiveRelationship = false,
    this.alreadyInRelationship = false,
    this.signUpIncomplete = false,
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

  /// True for acceptInvite's 409 when the person is already in an active
  /// or paused relationship: tell them (showOpenRelationshipNotice) rather
  /// than drop the link silently.
  final bool alreadyInRelationship;

  /// True for either invite function's 409 signup:incomplete (Spec 1 W2
  /// interim guard, review I-5): under flow_signin_v2 the caller is signed
  /// in but has no account yet, which only finishing sign-up resolves.
  final bool signUpIncomplete;

  @override
  String toString() => message;
}
