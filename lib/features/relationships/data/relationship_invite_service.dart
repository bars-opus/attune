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
  String get deepLink => linkFor(code);

  /// The invite link for [code] (R1's message before and after the invite
  /// is made).
  static String linkFor(String code) =>
      'https://invite.attune.barsopus.com/i/$code';
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

/// What preview_relationship_invite says about a code (Spec 1 §4.3 W4a).
enum InvitePreviewState { ok, expired, invalid, own, linked }

/// RI-3's read: the state and, for ok and expired only, the inviter's
/// first name (never a phone number; null when there is none).
class InvitePreview {
  const InvitePreview({required this.state, this.inviterFirstName});

  final InvitePreviewState state;
  final String? inviterFirstName;
}

/// What an invite refusal is (Spec 1 W4a codes). The app's words are chosen
/// from this, never from the server's text (W4 plan P-7).
enum InviteRefusalKind {
  invalid,
  own,
  expired,
  alreadyAccepted,
  alreadyInRelationship,
  phoneRequired,
  ageRequired,
  notPossible,
  cap,
  signUpIncomplete,
  tryLater,

  /// The acceptor's own open account hold (accept-invite 403
  /// account:hold): H1, never retried with the same code. An inviter's hold
  /// is the uniform invalid (never told apart).
  hold,
  unavailable,
}

/// The kind for a W4a server code, or null for anything else.
/// invite:try_again (503, a second deadlock abort: nothing was written) is
/// unavailable; invite:try_later (429, past the shared attempt budget) is
/// tryLater, retried later.
InviteRefusalKind? inviteRefusalKindOf(String? code) => switch (code) {
  'invite:invalid' => InviteRefusalKind.invalid,
  'invite:own' => InviteRefusalKind.own,
  'invite:expired' => InviteRefusalKind.expired,
  'invite:already_accepted' => InviteRefusalKind.alreadyAccepted,
  'invite:already_in_relationship' => InviteRefusalKind.alreadyInRelationship,
  'invite:phone_required' => InviteRefusalKind.phoneRequired,
  'invite:age_required' => InviteRefusalKind.ageRequired,
  'invite:not_possible' => InviteRefusalKind.notPossible,
  'invite:try_later' => InviteRefusalKind.tryLater,
  'invite:try_again' => InviteRefusalKind.unavailable,
  'account:hold' => InviteRefusalKind.hold,
  _ => null,
};

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
        retryable: true,
        kind: InviteRefusalKind.unavailable,
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
      throw inviteCreateFailure(error);
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
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
    try {
      await client.rpc('withdraw_my_pending_invites').timeout(timeout);
    } catch (error) {
      debugPrint('[relationship-invite] withdraw failed: ${error.runtimeType}');
      throw const RelationshipInviteException(
        'Could not update your invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
  }

  /// RI-3 (Spec 1 W4a): who sent [inviteCode], for a signed-in caller.
  /// Throws a retryable [RelationshipInviteException]: kind tryLater past
  /// the server's limit (10 an hour, 30 a day), unavailable otherwise
  /// (a [RelationshipInviteException.serverError] when the server answered
  /// with its own failure); invite:phone_required is for good (batch 5).
  Future<InvitePreview> previewInvite(String inviteCode) async {
    final client = _safeClient;
    if (client == null) {
      throw const RelationshipInviteException(
        'Could not check invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
    try {
      final data = await client
          .rpc('preview_relationship_invite', params: {'p_code': inviteCode})
          .timeout(timeout);
      return invitePreviewFrom(data);
    } on PostgrestException catch (error) {
      debugPrint('[relationship-invite] preview refused: ${error.code}');
      // No phone on the account: the same answer every time, so the code
      // is never kept for a retry that can't work.
      if (error.message == 'invite:phone_required') {
        throw const RelationshipInviteException(
          'Could not check invite.',
          kind: InviteRefusalKind.phoneRequired,
        );
      }
      final tryLater = error.message == 'invite:try_later';
      throw RelationshipInviteException(
        'Could not check invite.',
        retryable: true,
        kind:
            tryLater
                ? InviteRefusalKind.tryLater
                : InviteRefusalKind.unavailable,
        serverError: !tryLater,
      );
    } catch (error) {
      debugPrint('[relationship-invite] preview failed: ${error.runtimeType}');
      throw const RelationshipInviteException(
        'Could not check invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
  }

  Future<InviteAcceptance> acceptInvite(String inviteCode) async {
    final client = _safeClient;
    if (client == null) {
      // Never name the backend in a user-facing message (auth engine spec
      // §Failure Modes: no project refs / internal config in UI errors).
      throw const RelationshipInviteException(
        'Invites are unavailable right now. Please try again later.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
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
    // Preflight F-4: a malformed answer is transient, never "no such
    // invite" on R1 or R3.
    throw const RelationshipInviteException(
      'Unexpected invite response.',
      retryable: true,
      kind: InviteRefusalKind.unavailable,
    );
  }
}

/// preview_relationship_invite's answer; an unknown state reads as invalid.
InvitePreview invitePreviewFrom(Object? data) {
  final map = data is Map ? data : const {};
  final state = switch (map['state']) {
    'ok' => InvitePreviewState.ok,
    'expired' => InvitePreviewState.expired,
    'own' => InvitePreviewState.own,
    'linked' => InvitePreviewState.linked,
    _ => InvitePreviewState.invalid,
  };
  final raw = map['inviter_first_name'];
  final name = raw is String ? raw.trim() : '';
  final named =
      state == InvitePreviewState.ok || state == InvitePreviewState.expired;
  return InvitePreview(
    state: state,
    inviterFirstName: named && name.isNotEmpty ? name : null,
  );
}

/// accept-invite's refusal for someone already in an active or paused
/// relationship (sync audit I-8). Matched on its opening words, which the
/// server keeps fixed (supabase/functions/accept-invite/accept.test.ts).
const kAlreadyInRelationshipPrefix = "You're already in a relationship";

/// Both invite functions' 409 for a signed-in caller with no account yet
/// under flow_signin_v2 (supabase/functions/_shared/sign_up_guard.ts).
const kSignUpIncompleteError = 'signup:incomplete';

/// Their 503 when the server can't read flow_signin_v2 (the guard fails
/// closed): retryable, and never shown.
const kFlagsUnavailableError = 'flags:unavailable';

/// What a failed createInvite call means. create-relationship-invite
/// replies {"error": message}: 409 for no account yet
/// (signup:incomplete), the pending-invite cap or an already active
/// relationship; since W4a 428 invite:age_required (no date of birth) and
/// 403 invite:not_possible (under 18); 503 flags:unavailable.
RelationshipInviteException inviteCreateFailure(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    final message = details is Map ? details['error'] as String? : null;
    if (error.status == 409) {
      // Spec 1 W2 interim guard (review I-5): no account yet. The code is
      // never shown; finishing sign-up resolves it.
      if (message == kSignUpIncompleteError) {
        return const RelationshipInviteException(
          'Could not create invite.',
          signUpIncomplete: true,
          kind: InviteRefusalKind.signUpIncomplete,
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
      final alreadyActive =
          message?.toLowerCase().contains('already have an active') ?? false;
      return RelationshipInviteException(
        message ?? 'You already have the maximum number of pending invites.',
        alreadyActiveRelationship: alreadyActive,
        kind: alreadyActive ? null : InviteRefusalKind.cap,
      );
    }
    final kind = inviteRefusalKindOf(message);
    if (kind == InviteRefusalKind.ageRequired ||
        kind == InviteRefusalKind.notPossible) {
      return RelationshipInviteException(
        'Could not create invite.',
        retryable: kind == InviteRefusalKind.ageRequired,
        kind: kind,
      );
    }
    if (message == kFlagsUnavailableError || error.status >= 500) {
      return const RelationshipInviteException(
        'Could not create invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
  }
  return const RelationshipInviteException(
    'Could not create invite.',
    retryable: true,
    kind: InviteRefusalKind.unavailable,
  );
}

/// What a failed acceptInvite call means. accept-invite's handleError
/// always replies with {"error": "<message>"} plus a real status: 400 bad
/// code, 404 invalid, 409 self-accept/already-accepted/already in a
/// relationship, 410 expired; since W4a also 403 (account:hold too), 428,
/// 429 invite:try_later and 503 invite:try_again, and a "code" the app
/// reads first. None of the refusals are worth retrying with the same code
/// except a missing date of birth (added, then joined) and the attempt
/// limit (later), so callers can tell them apart from a transient
/// network/timeout failure instead of showing "try again" for both.
RelationshipInviteException inviteAcceptFailure(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    final message = details is Map ? details['error'] as String? : null;
    final code = details is Map ? details['code'] as String? : null;
    // Spec 1 W2 interim guard (review I-5): no account yet. Retryable, so
    // the stored invite is kept and accepted once sign-up is finished (an
    // unfinished account goes on from /home to /onboarding, whose consent
    // step sends it to /signup under flow_signin_v2).
    if (error.status == 409 && message == kSignUpIncompleteError) {
      return const RelationshipInviteException(
        'Could not accept invite.',
        retryable: true,
        signUpIncomplete: true,
        kind: InviteRefusalKind.signUpIncomplete,
      );
    }
    if (message == kFlagsUnavailableError) {
      return const RelationshipInviteException(
        'Could not accept invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
        serverError: true,
      );
    }
    final kind = inviteRefusalKindOf(code);
    final alreadyIn =
        kind == InviteRefusalKind.alreadyInRelationship ||
        (error.status == 409 &&
            (message ?? '').startsWith(kAlreadyInRelationshipPrefix));
    return RelationshipInviteException(
      message ?? 'Could not accept invite.',
      retryable:
          error.status >= 500 ||
          kind == InviteRefusalKind.ageRequired ||
          kind == InviteRefusalKind.tryLater,
      alreadyInRelationship: alreadyIn,
      kind:
          alreadyIn
              ? InviteRefusalKind.alreadyInRelationship
              : kind ??
                  (error.status >= 500 ? InviteRefusalKind.unavailable : null),
      serverError: error.status >= 500,
    );
  }
  return const RelationshipInviteException(
    'Could not accept invite.',
    retryable: true,
    kind: InviteRefusalKind.unavailable,
  );
}

class RelationshipInviteException implements Exception {
  const RelationshipInviteException(
    this.message, {
    this.retryable = false,
    this.alreadyActiveRelationship = false,
    this.alreadyInRelationship = false,
    this.signUpIncomplete = false,
    this.kind,
    this.serverError = false,
  });

  /// The server's or service's own words, for logs and today's flag-off
  /// screens. W4b screens show [kind]'s copy instead (inviteErrorCopy).
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

  /// Which refusal this is, when known (Spec 1 W4a).
  final InviteRefusalKind? kind;

  /// True when the server answered with its own failure (a 5xx, such as
  /// accept's 503 invite:try_again): the person is online, so the words
  /// never blame the connection (batch-3 review #5).
  final bool serverError;

  @override
  String toString() => message;
}
