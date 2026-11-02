// Spec 1 W4a (batch 3 carried items): Task 2's new answers (account:hold,
// invite:try_again, invite:try_later), preflight F-4 (a create failure with
// no kind is "try again", never RI-3's "We couldn't find that invite"), and
// the real service's reads of a malformed answer and the preview's limit.
import 'dart:convert';

import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

FunctionException _refusal(int status, String message, [String? code]) =>
    FunctionException(
      status: status,
      details: {'error': message, if (code != null) 'code': code},
    );

/// A service whose every HTTP call answers [status] with [body].
RelationshipInviteService _service(int status, Object? body) =>
    RelationshipInviteService(
      client: SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        httpClient: MockClient(
          (request) async => http.Response(
            body is String ? body : jsonEncode(body),
            status,
            headers: {
              'content-type':
                  body is String ? 'text/plain' : 'application/json',
            },
            request: request,
          ),
        ),
      ),
    );

void main() {
  final loc = lookupAppLocalizations(const Locale('en'));

  test('the codes Task 2 added are read as their kinds', () {
    expect(inviteRefusalKindOf('account:hold'), InviteRefusalKind.hold);
    expect(
      inviteRefusalKindOf('invite:try_again'),
      InviteRefusalKind.unavailable,
    );
    expect(inviteRefusalKindOf('invite:try_later'), InviteRefusalKind.tryLater);
    expect(inviteRefusalKindOf('invite:unknown'), isNull);
    expect(inviteRefusalKindOf(null), isNull);
  });

  test("account:hold (403) is the acceptor's own hold: not retryable", () {
    final hold = inviteAcceptFailure(
      _refusal(403, 'account:hold', 'account:hold'),
    );
    expect(hold.kind, InviteRefusalKind.hold);
    expect(hold.retryable, isFalse);
    expect(hold.alreadyInRelationship, isFalse);
    expect(inviteErrorCopy(loc, hold), loc.flow_holdTitle);
  });

  test('invite:try_again (503) is retryable', () {
    final again = inviteAcceptFailure(
      _refusal(503, 'invite:try_again', 'invite:try_again'),
    );
    expect(again.kind, InviteRefusalKind.unavailable);
    expect(again.retryable, isTrue);
    expect(inviteErrorCopy(loc, again), isNot(contains('invite:')));
  });

  test('invite:try_later (429) is retryable later, never permanent', () {
    final later = inviteAcceptFailure(
      _refusal(429, 'invite:try_later', 'invite:try_later'),
    );
    expect(later.kind, InviteRefusalKind.tryLater);
    expect(later.retryable, isTrue);
    expect(inviteErrorCopy(loc, later), loc.flow_joinTryLater);
  });

  test("invite:invalid is the uniform answer: nothing about the inviter", () {
    final invalid = inviteAcceptFailure(
      _refusal(404, 'Invite code is invalid', 'invite:invalid'),
    );
    expect(invalid.retryable, isFalse);
    final copy = inviteErrorCopy(loc, invalid);
    expect(copy, loc.flow_joinInvalid);
    for (final word in ['relationship', 'hold', 'paused', 'partner']) {
      expect(copy.toLowerCase(), isNot(contains(word)), reason: word);
    }
  });

  test('F-4: no kind on create is "try again", never "couldn\'t find"', () {
    for (final error in [
      inviteCreateFailure(_refusal(401, 'Invalid JWT')),
      inviteCreateFailure(_refusal(400, 'Bad request')),
      inviteCreateFailure(StateError('x')),
      inviteCreateFailure(const FunctionException(status: 500)),
    ]) {
      expect(error.kind, InviteRefusalKind.unavailable);
      expect(error.retryable, isTrue);
      expect(inviteErrorCopy(loc, error), loc.flow_inviteErrorTryAgain);
    }
  });

  test('F-4: R1/R3 never read "couldn\'t find" for a kind-less error', () {
    // inviteErrorCopy is R1's and R3's only (F-5); a kind-less refusal,
    // retryable or not, is "try again" there.
    for (final error in const [
      RelationshipInviteException('x'),
      RelationshipInviteException('Could not create invite.'),
      RelationshipInviteException('y', retryable: true),
    ]) {
      expect(inviteErrorCopy(loc, error), loc.flow_inviteErrorTryAgain);
    }
  });

  test(
    'F-4: a create answer that is not a map is unavailable, retryable',
    () async {
      for (final body in <Object>['not json', <Object>[]]) {
        try {
          await _service(200, body).createInvite();
          fail('created from $body');
        } on RelationshipInviteException catch (error) {
          expect(error.kind, InviteRefusalKind.unavailable, reason: '$body');
          expect(error.retryable, isTrue, reason: '$body');
          final copy = inviteErrorCopy(loc, error);
          expect(copy, loc.flow_inviteErrorTryAgain);
          expect(copy, isNot(loc.flow_joinInvalid));
        }
      }
    },
  );

  test(
    'the real service reads a 403 account:hold and a 429 try_later',
    () async {
      final cases = {
        'account:hold': (403, InviteRefusalKind.hold, false),
        'invite:try_later': (429, InviteRefusalKind.tryLater, true),
        'invite:try_again': (503, InviteRefusalKind.unavailable, true),
      };
      for (final MapEntry(key: code, value: (status, kind, retry))
          in cases.entries) {
        try {
          await _service(status, {
            'error': code,
            'code': code,
          }).acceptInvite('K7P2QM');
          fail('accepted past $code');
        } on RelationshipInviteException catch (error) {
          expect(error.kind, kind, reason: code);
          expect(error.retryable, retry, reason: code);
        }
      }
    },
  );

  test(
    "the preview: the server's limit is tryLater, anything else unavailable",
    () async {
      try {
        await _service(400, {
          'code': 'P0001',
          'message': 'invite:try_later',
          'details': null,
          'hint': null,
        }).previewInvite('K7P2QM');
        fail('previewed past the limit');
      } on RelationshipInviteException catch (error) {
        expect(error.kind, InviteRefusalKind.tryLater);
        expect(error.retryable, isTrue);
      }
      try {
        await _service(400, {
          'code': 'P0001',
          'message': 'boom',
        }).previewInvite('K7P2QM');
        fail('previewed on an error');
      } on RelationshipInviteException catch (error) {
        expect(error.kind, InviteRefusalKind.unavailable);
        expect(error.retryable, isTrue);
      }
      final ok = await _service(200, {
        'state': 'ok',
        'inviter_first_name': 'Yaw',
      }).previewInvite('K7P2QM');
      expect(ok.state, InvitePreviewState.ok);
      expect(ok.inviterFirstName, 'Yaw');
    },
  );

  // Batch-3 review #5: only a server's own failure (a 5xx, such as the
  // 503 invite:try_again) is a server error; a refusal or no connection
  // never is, so only the connection case says "when you're online".
  test('only a 5xx answer is the server\'s own failure', () {
    expect(
      inviteAcceptFailure(
        _refusal(503, 'invite:try_again', 'invite:try_again'),
      ).serverError,
      isTrue,
    );
    expect(inviteAcceptFailure(_refusal(500, 'boom')).serverError, isTrue);
    expect(
      inviteAcceptFailure(_refusal(503, 'flags:unavailable')).serverError,
      isTrue,
    );
    for (final refusal in [
      _refusal(404, 'Invite code is invalid', 'invite:invalid'),
      _refusal(428, 'invite:age_required', 'invite:age_required'),
      _refusal(429, 'invite:try_later', 'invite:try_later'),
    ]) {
      expect(
        inviteAcceptFailure(refusal).serverError,
        isFalse,
        reason: '${refusal.status}',
      );
    }
    expect(inviteAcceptFailure(Exception('socket')).serverError, isFalse);
  });

  // Batch 5 (carried item 3): the preview's invite:phone_required is the
  // server's answer for good, so RI-3 never keeps the code for ever; any
  // other refusal the server raised is its own failure (it answered).
  test('the preview: phone_required is for good; a server error says so', () async {
    try {
      await _service(400, {
        'code': 'P0001',
        'message': 'invite:phone_required',
        'details': null,
        'hint': null,
      }).previewInvite('K7P2QM');
      fail('previewed without a phone');
    } on RelationshipInviteException catch (error) {
      expect(error.kind, InviteRefusalKind.phoneRequired);
      expect(error.retryable, isFalse);
    }
    try {
      await _service(400, {
        'code': 'P0001',
        'message': 'boom',
      }).previewInvite('K7P2QM');
      fail('previewed on an error');
    } on RelationshipInviteException catch (error) {
      expect(error.serverError, isTrue);
      expect(error.retryable, isTrue);
    }
    try {
      await _service(400, {
        'code': 'P0001',
        'message': 'invite:try_later',
      }).previewInvite('K7P2QM');
      fail('previewed past the limit');
    } on RelationshipInviteException catch (error) {
      expect(error.serverError, isFalse);
    }
  });

  // Preflight F-13: nothing is being linked on R1 or R3, so an under-18
  // inviter's create refusal says "make", neutral, never "18".
  test("an inviter's create 403 not_possible: couldn't make (F-13)", () {
    final copy = inviteErrorCopy(
      loc,
      inviteCreateFailure(_refusal(403, 'invite:not_possible')),
    );
    expect(
      copy,
      "We couldn't make your invite. If you think this is wrong, contact support.",
    );
    expect(copy, isNot(contains('18')));
  });
}
