// Spec 1 W2 interim invite guard (batch 5 review I-5): under
// flow_signin_v2, accept-invite and create-relationship-invite answer a
// signed-in caller who has no account yet with 409 signup:incomplete. The
// stored invite must survive that answer (HomeScreen and OnboardingGate
// drop a code only on a refusal that can never succeed), so it is accepted
// once sign-up is finished; and the code itself is never shown to anyone.
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _incomplete = FunctionException(
  status: 409,
  details: {'error': 'signup:incomplete'},
);

class _Functions extends Fake implements FunctionsClient {
  _Functions(this.error);

  final Object error;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #invoke) {
      return Future<FunctionResponse>.error(error);
    }
    return super.noSuchMethod(invocation);
  }
}

class _Client extends Fake implements SupabaseClient {
  _Client(this.functions);

  @override
  final FunctionsClient functions;
}

void main() {
  test('accept: the invite is kept for after sign-up, never dropped', () {
    final e = inviteAcceptFailure(_incomplete);
    expect(e.signUpIncomplete, isTrue);
    expect(
      e.retryable,
      isTrue,
      reason: 'a non-retryable refusal makes the caller delete the code',
    );
    expect(e.alreadyInRelationship, isFalse);
    expect(e.message, isNot(contains('signup:')));
  });

  test('accept: an unreadable flag (503) keeps the invite too', () {
    // The guard fails closed: flags:unavailable, retryable.
    final e = inviteAcceptFailure(
      const FunctionException(
        status: 503,
        details: {'error': 'flags:unavailable'},
      ),
    );
    expect(
      e.retryable,
      isTrue,
      reason: 'a non-retryable refusal makes the caller delete the code',
    );
    expect(e.signUpIncomplete, isFalse);
    expect(e.alreadyInRelationship, isFalse);
    expect(e.message, isNot(contains('flags:')));
  });

  test('create: an unreadable flag (503) shows no code', () async {
    final service = RelationshipInviteService(
      client: _Client(
        _Functions(
          const FunctionException(
            status: 503,
            details: {'error': 'flags:unavailable'},
          ),
        ),
      ),
    );
    await expectLater(
      service.createInvite(),
      throwsA(
        isA<RelationshipInviteException>().having(
          (e) => e.message,
          'message',
          isNot(contains('flags:')),
        ),
      ),
    );
  });

  test('accept: every other refusal is read as before', () {
    final selfAccept = inviteAcceptFailure(
      const FunctionException(
        status: 409,
        details: {'error': 'You cannot accept your own invite'},
      ),
    );
    expect(selfAccept.signUpIncomplete, isFalse);
    expect(selfAccept.retryable, isFalse);
    expect(selfAccept.message, 'You cannot accept your own invite');
    final expired = inviteAcceptFailure(
      const FunctionException(
        status: 410,
        details: {'error': 'signup:incomplete'},
      ),
    );
    expect(expired.signUpIncomplete, isFalse, reason: 'only the 409 is it');
    expect(expired.retryable, isFalse);
  });

  test('create: the refusal is recognised and its code never shown', () async {
    final service = RelationshipInviteService(
      client: _Client(_Functions(_incomplete)),
    );
    await expectLater(
      service.createInvite(),
      throwsA(
        isA<RelationshipInviteException>()
            .having((e) => e.signUpIncomplete, 'signUpIncomplete', isTrue)
            .having(
              (e) => e.alreadyActiveRelationship,
              'alreadyActiveRelationship',
              isFalse,
            )
            .having((e) => e.message, 'message', isNot(contains('signup:'))),
      ),
    );
  });

  test('create: the pending-invite cap still reads as before', () async {
    const cap = 'You already have the maximum number of pending invites';
    final service = RelationshipInviteService(
      client: _Client(
        _Functions(
          const FunctionException(status: 409, details: {'error': cap}),
        ),
      ),
    );
    await expectLater(
      service.createInvite(),
      throwsA(
        isA<RelationshipInviteException>()
            .having((e) => e.signUpIncomplete, 'signUpIncomplete', isFalse)
            .having((e) => e.message, 'message', cap),
      ),
    );
  });
}
