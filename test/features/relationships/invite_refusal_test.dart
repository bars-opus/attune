// Spec 1 W4a/W4b (§4.5, P-7): the app reads accept-invite's W4a codes, the
// inviter's 428/403, and the preview; every failure has the app's own
// words, never the server's.
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

FunctionException _refusal(int status, String message, [String? code]) =>
    FunctionException(
      status: status,
      details: {'error': message, if (code != null) 'code': code},
    );

void main() {
  final loc = lookupAppLocalizations(const Locale('en'));

  test('every W4a accept code is read as its kind', () {
    final cases = <String, (int, String, InviteRefusalKind, bool)>{
      'invite:invalid': (
        404,
        'Invite code is invalid',
        InviteRefusalKind.invalid,
        false,
      ),
      'invite:own': (
        409,
        'You cannot accept your own invite',
        InviteRefusalKind.own,
        false,
      ),
      'invite:expired': (
        410,
        'Invite code has expired',
        InviteRefusalKind.expired,
        false,
      ),
      'invite:already_accepted': (
        409,
        'Invite has already been accepted',
        InviteRefusalKind.alreadyAccepted,
        false,
      ),
      'invite:phone_required': (
        403,
        'invite:phone_required',
        InviteRefusalKind.phoneRequired,
        false,
      ),
      'invite:age_required': (
        428,
        'invite:age_required',
        InviteRefusalKind.ageRequired,
        true,
      ),
      'invite:not_possible': (
        403,
        'invite:not_possible',
        InviteRefusalKind.notPossible,
        false,
      ),
    };
    for (final MapEntry(key: code, value: (status, message, kind, retry))
        in cases.entries) {
      final e = inviteAcceptFailure(_refusal(status, message, code));
      expect(e.kind, kind, reason: code);
      expect(e.retryable, retry, reason: code);
      expect(e.alreadyInRelationship, isFalse, reason: code);
    }
    final already = inviteAcceptFailure(
      _refusal(
        409,
        "You're already in a relationship on Attune. End it first to join a new one.",
        'invite:already_in_relationship',
      ),
    );
    expect(already.kind, InviteRefusalKind.alreadyInRelationship);
    expect(already.alreadyInRelationship, isTrue);
  });

  test('a refusal without a code is read as before (no kind for 4xx)', () {
    final selfAccept = inviteAcceptFailure(
      _refusal(409, 'You cannot accept your own invite'),
    );
    expect(selfAccept.kind, isNull);
    expect(selfAccept.retryable, isFalse);
    final down = inviteAcceptFailure(const FunctionException(status: 500));
    expect(down.kind, InviteRefusalKind.unavailable);
    expect(down.retryable, isTrue);
  });

  test("create: the inviter's 428 and 403, the cap, no account", () {
    final noDob = inviteCreateFailure(_refusal(428, 'invite:age_required'));
    expect(noDob.kind, InviteRefusalKind.ageRequired);
    expect(noDob.retryable, isTrue);
    expect(noDob.message, isNot(contains('invite:')));
    final minor = inviteCreateFailure(_refusal(403, 'invite:not_possible'));
    expect(minor.kind, InviteRefusalKind.notPossible);
    expect(minor.retryable, isFalse);
    final cap = inviteCreateFailure(
      _refusal(409, 'You already have the maximum number of pending invites'),
    );
    expect(cap.kind, InviteRefusalKind.cap);
    final active = inviteCreateFailure(
      _refusal(409, 'You already have an active relationship'),
    );
    expect(active.alreadyActiveRelationship, isTrue);
    expect(active.kind, isNull);
    final none = inviteCreateFailure(_refusal(409, 'signup:incomplete'));
    expect(none.signUpIncomplete, isTrue);
    expect(none.kind, InviteRefusalKind.signUpIncomplete);
  });

  test('the preview: a name only for ok and expired', () {
    final ok = invitePreviewFrom({
      'state': 'ok',
      'inviter_first_name': ' Yaw ',
    });
    expect(ok.state, InvitePreviewState.ok);
    expect(ok.inviterFirstName, 'Yaw');
    final expired = invitePreviewFrom({
      'state': 'expired',
      'inviter_first_name': 'Yaw',
    });
    expect(expired.inviterFirstName, 'Yaw');
    final own = invitePreviewFrom({
      'state': 'own',
      'inviter_first_name': 'Yaw',
    });
    expect(own.state, InvitePreviewState.own);
    expect(own.inviterFirstName, isNull);
    expect(
      invitePreviewFrom({'state': 'linked'}).state,
      InvitePreviewState.linked,
    );
    expect(
      invitePreviewFrom({'state': 'odd'}).state,
      InvitePreviewState.invalid,
    );
    expect(invitePreviewFrom(null).state, InvitePreviewState.invalid);
    expect(
      invitePreviewFrom({
        'state': 'ok',
        'inviter_first_name': '  ',
      }).inviterFirstName,
      isNull,
    );
  });

  test('every failure has the app\'s words, never the server\'s', () {
    final failures = [
      inviteAcceptFailure(
        _refusal(404, 'Invite code is invalid', 'invite:invalid'),
      ),
      inviteAcceptFailure(
        _refusal(409, 'You cannot accept your own invite', 'invite:own'),
      ),
      inviteAcceptFailure(
        _refusal(403, 'invite:not_possible', 'invite:not_possible'),
      ),
      inviteAcceptFailure(
        _refusal(428, 'invite:age_required', 'invite:age_required'),
      ),
      inviteCreateFailure(
        _refusal(409, 'You already have the maximum number of pending invites'),
      ),
      inviteCreateFailure(_refusal(503, 'flags:unavailable')),
      inviteCreateFailure(_refusal(409, 'signup:incomplete')),
      const RelationshipInviteException(
        'Could not check invite.',
        retryable: true,
        kind: InviteRefusalKind.tryLater,
      ),
    ];
    final english = {
      'Invite code is invalid',
      'You cannot accept your own invite',
      'You already have the maximum number of pending invites',
      'Could not create invite.',
      'Could not accept invite.',
    };
    for (final failure in failures) {
      final copy = inviteErrorCopy(loc, failure);
      expect(english, isNot(contains(copy)), reason: failure.message);
      expect(copy, isNot(contains('invite:')));
      expect(copy, isNot(contains('signup:')));
      expect(copy, isNot(contains('flags:')));
    }
    // Preflight F-13: inviteErrorCopy is R1's and R3's (making an invite).
    expect(
      inviteErrorCopy(loc, failures[2]),
      "We couldn't make your invite. If you think this is wrong, contact support.",
    );
    expect(
      inviteErrorCopy(loc, failures[4]),
      'You already have 3 invites waiting. Cancel one before you send another.',
    );
  });
}
