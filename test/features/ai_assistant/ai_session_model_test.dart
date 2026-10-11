// test/features/ai_assistant/ai_session_model_test.dart
//
// Fixtures transcribed from the edge function's own response literals,
// not from the task brief:
//
//   * handleReviewContext (supabase/functions/ai-sessions/index.ts
//     ~1150) returns TWELVE keys.
//   * handleApprove (~3200, and the APPROVAL_REQUIRED branch at ~3182)
//     returns THREE: {approved, activated, state}.
import 'package:attune/features/ai_assistant/data/models/ai_session_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// A valid digest: 64 lowercase hex characters, matching
/// `handleApprove`'s own `/^[0-9a-f]{64}$/` guard. Spelled out as a
/// literal because a default parameter value must be a compile-time
/// constant and `'a' * 64` is not one.
const String kDigestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String kDigestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// `handleReviewContext`'s exact response key set.
const Set<String> kReviewContextResponseKeys = {
  'session_id',
  'revision',
  'policy_version',
  'kind',
  'visibility',
  'include_window',
  'utc_offset_minutes',
  'civil_day_start_utc',
  'window',
  'target',
  'digest',
};

Map<String, dynamic> reviewContextResponse({
  bool includeWindow = true,
  Object? target = const {'content': 'the message you picked'},
  List<Map<String, dynamic>>? window,
  String digest = kDigestA,
  String kind = 'ideas',
  String visibility = 'shared',
  int revision = 3,
}) => {
  'session_id': '11111111-1111-4111-8111-111111111111',
  'revision': revision,
  'policy_version': 'v3',
  'kind': kind,
  'visibility': visibility,
  'include_window': includeWindow,
  'utc_offset_minutes': 60,
  'civil_day_start_utc': '2026-09-26T23:00:00.000Z',
  'window':
      window ??
      [
        {'content': 'a window message', 'truncated': false},
        {'content': 'another, clipped', 'truncated': true},
      ],
  'target': target,
  'digest': digest,
};

void main() {
  group('the fixture is a server shape', () {
    test('carries exactly handleReviewContext\'s eleven keys', () {
      expect(kReviewContextResponseKeys, hasLength(11));
      expect(
        reviewContextResponse().keys.toSet(),
        kReviewContextResponseKeys,
      );
    });
  });

  group('AiSessionContextReview — the renderable half', () {
    test('parses the snippets, the toggle state and the offset', () {
      final review = AiSessionContextReview.fromJson(
        reviewContextResponse(),
      );
      expect(review.sessionId, '11111111-1111-4111-8111-111111111111');
      expect(review.kind, AiSessionKind.ideas);
      expect(review.visibility, AiSessionVisibility.shared);
      expect(review.includeWindow, isTrue);
      expect(review.utcOffsetMinutes, 60);
      // The target carries ONLY `content` — handleReviewContext sends
      // `{content}` for it while sending `{content, truncated}` for
      // every window message. The two are therefore different types
      // here; giving the target a `truncated` field would mean
      // inventing a value the server never sends.
      expect(review.target?.content, 'the message you picked');
      expect(review.window, hasLength(2));
      expect(review.window.first.content, 'a window message');
      expect(review.window.first.truncated, isFalse);
      expect(review.window.last.truncated, isTrue);
    });

    test(
      'the target and window snippet types are ASYMMETRIC, matching the '
      'server: only window messages carry `truncated`',
      () {
        // handleReviewContext sends `target: {content}` and
        // `window: [{content, truncated}]`. The asymmetry is real, not
        // an omission: the target's text is the STORED
        // approved_clipped_text, clipped once at prepare time, whereas a
        // window snippet is clipped by selectSharedWindow's live
        // 2,400-scalar TOTAL budget and so can be re-clipped per call.
        // That is the same asymmetry that makes digest recomputation
        // impossible (gate 2), so flattening the two into one type with
        // a nullable `truncated` would erase the evidence of it.
        expect(AiSessionWindowSnippet.wireKeys, {'content', 'truncated'});
        expect(AiSessionWindowSnippet.wireKeys, hasLength(2));
        expect(AiSessionTargetSnippet.wireKeys, {'content'});
        expect(AiSessionTargetSnippet.wireKeys, hasLength(1));
        expect(
          AiSessionTargetSnippet.wireKeys,
          isNot(contains('truncated')),
        );
      },
    );

    test('a null target parses to null, not to an empty snippet', () {
      // handleReviewContext sends `target: null` when prepare attached
      // no message. An empty-string snippet would render as a blank
      // quote card, which is not the same thing as no quote card.
      final review = AiSessionContextReview.fromJson(
        reviewContextResponse(target: null),
      );
      expect(review.target, isNull);
    });

    test('an empty window with include_window true parses as empty', () {
      // selectSharedWindow can legitimately return zero eligible
      // messages. That is not a malformed response and not a toggle
      // that failed to apply.
      final review = AiSessionContextReview.fromJson(
        reviewContextResponse(window: const []),
      );
      expect(review.includeWindow, isTrue);
      expect(review.window, isEmpty);
    });

    test('include_window false parses with an empty window', () {
      final review = AiSessionContextReview.fromJson(
        reviewContextResponse(includeWindow: false, window: const []),
      );
      expect(review.includeWindow, isFalse);
      expect(review.window, isEmpty);
    });

    test('throws for an unrecognized kind', () {
      expect(
        () => AiSessionContextReview.fromJson(
          reviewContextResponse(kind: 'nonsense'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('nonsense'),
          ),
        ),
      );
    });

    test('throws for an unrecognized visibility', () {
      expect(
        () => AiSessionContextReview.fromJson(
          reviewContextResponse(visibility: 'public'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('public'),
          ),
        ),
      );
    });
  });

  group('GATE 2 — the digest and its inputs are never on one type', () {
    // Plan C MEASURED that recomputing the digest from stored rows is
    // impossible: selectSharedWindow's 2,400-scalar TOTAL budget
    // re-clips the final snippet, and review_context hashes the TARGET
    // snippet as stored text while hashing WINDOW snippets as the live
    // selection produced them. So a client that compared a recomputed
    // digest against the server's would see a spurious mismatch, which
    // renders to the user as "my partner changed the context".
    //
    // handleReviewContext's ONE response nevertheless contains the
    // digest AND almost every pre-image input: the snippets
    // (`window[].content`, `target.content` — these ARE
    // computeApprovalDigest's `displayedSnippets`), `policy_version`,
    // `kind`, `visibility`, `revision` (its `contextRevision`) and
    // `session_id`. Only `participants` is withheld, and that is not a
    // deliberate withholding — the digest also no longer binds the
    // offset at all (Ruling 35 / N3), though `utc_offset_minutes` and
    // `civil_day_start_utc` are still echoed.
    //
    // THIS IS AWKWARD AND I AM SAYING SO RATHER THAN HIDING IT: the
    // SERVER hands a client everything it would need to attempt a
    // recomputation. The client cannot change that. What a model CAN
    // do is refuse to be the type that makes the attempt convenient,
    // and that is what these tests pin.
    test(
      'AiSessionContextReview carries the snippets and NO digest',
      () {
        final review = AiSessionContextReview.fromJson(
          reviewContextResponse(),
        );
        expect(review.window.first.content, isNotEmpty);
        expect(review.target?.content, isNotEmpty);
        // The behavioural proof: the renderable half's own transcribed
        // field list does not include the digest, the policy version or
        // the revision, so there is no member to read one from.
        expect(
          AiSessionContextReview.wireKeysRead,
          {
            'session_id',
            'kind',
            'visibility',
            'include_window',
            'utc_offset_minutes',
            'window',
            'target',
          },
        );
        expect(AiSessionContextReview.wireKeysRead, hasLength(7));
        expect(
          AiSessionContextReview.wireKeysRead,
          isNot(contains('digest')),
        );
        expect(
          AiSessionContextReview.wireKeysRead,
          isNot(contains('policy_version')),
        );
        expect(
          AiSessionContextReview.wireKeysRead,
          isNot(contains('civil_day_start_utc')),
        );
      },
    );

    test('AiSessionApprovalTicket carries the digest and NO snippets', () {
      final ticket = AiSessionApprovalTicket.fromJson(
        reviewContextResponse(),
      );
      expect(ticket.digest, kDigestA);
      expect(ticket.revision, 3);
      expect(ticket.policyVersion, 'v3');
      // Same behavioural proof from the other side: the ticket's
      // transcribed field list contains no snippet-bearing key and no
      // civil-day value, so there is nothing to compare a recomputation
      // against.
      expect(
        AiSessionApprovalTicket.wireKeysRead,
        {'session_id', 'revision', 'policy_version', 'digest'},
      );
      expect(AiSessionApprovalTicket.wireKeysRead, hasLength(4));
      for (final forbidden in const [
        'window',
        'target',
        'civil_day_start_utc',
        'utc_offset_minutes',
        'kind',
        'visibility',
      ]) {
        expect(
          AiSessionApprovalTicket.wireKeysRead,
          isNot(contains(forbidden)),
          reason:
              '$forbidden is a digest pre-image input or a selection '
              'input; carrying it beside the digest invites recomputation',
        );
      }
    });

    test(
      'the two halves\' field sets are DISJOINT apart from session_id',
      () {
        // The one overlap is the session id, which is an addressing
        // value rather than a pre-image input a caller could vary.
        // Asserting disjointness-but-for-it is what makes "the digest
        // never travels with its inputs" a checkable property rather
        // than a claim.
        final overlap = AiSessionContextReview.wireKeysRead.intersection(
          AiSessionApprovalTicket.wireKeysRead,
        );
        expect(overlap, {'session_id'});
        expect(overlap, hasLength(1));
      },
    );

    test(
      'the two halves plus the explicitly-dropped set account for every '
      'key the server sends',
      () {
        // The denominator guard that stops this split from being a way
        // to silently DROP a field. Eleven keys in, eleven accounted
        // for. This test FAILED on first run and found a real gap:
        // `civil_day_start_utc` was read by neither half. Rather than
        // weaken the assertion, the drop is now explicit and reasoned
        // on the model (wireKeysDeliberatelyDropped) — it is a
        // civil-day value, exactly the class gate 2 says must not sit
        // beside the digest, and Ruling 35 removed it from the
        // pre-image anyway.
        final read = AiSessionContextReview.wireKeysRead.union(
          AiSessionApprovalTicket.wireKeysRead,
        );
        final dropped =
            AiSessionContextReview.wireKeysDeliberatelyDropped;
        expect(dropped, {'civil_day_start_utc'});
        expect(dropped, hasLength(1));
        // Dropped means dropped: neither half may also read it.
        expect(read.intersection(dropped), isEmpty);
        expect(read.union(dropped), kReviewContextResponseKeys);
        expect(read.union(dropped), hasLength(11));
      },
    );

    test('the ticket rejects a digest that is not 64 lowercase hex', () {
      // handleApprove's own guard: /^[0-9a-f]{64}$/, bounded by SHAPE
      // not merely by length, because "a client that sends a truncated
      // or re-cased digest must be refused here rather than storing a
      // value activate_ai_session will later compare unequal, which
      // would read to the user as 'my partner changed the context'".
      // Validating client-side too means a mangled digest fails at the
      // model boundary with a clear cause instead of as a server
      // INVALID_INPUT the UI must guess at.
      for (final bad in [
        'A' * 64, // uppercase
        'a' * 63, // short
        'a' * 65, // long
        'g' * 64, // non-hex
        '',
      ]) {
        expect(
          () => AiSessionApprovalTicket.fromJson(
            reviewContextResponse(digest: bad),
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('digest'),
            ),
          ),
          reason: 'digest "${bad.length} chars" must be refused',
        );
      }
    });

    test('the ticket exposes no way to derive or rebuild a digest', () {
      // There is no `computeDigest`, no `expectedDigest`, no
      // `matchesSnippets`, and the field is a plain String the caller
      // can only echo. The assertion is on the ONE operation the type
      // supports: round-tripping the pair into approve's body.
      final ticket = AiSessionApprovalTicket.fromJson(
        reviewContextResponse(),
      );
      expect(ticket.toApproveBody(), {
        'session_id': '11111111-1111-4111-8111-111111111111',
        'revision': 3,
        'digest': kDigestA,
        'policy_version': 'v3',
      });
    });

    test(
      'toApproveBody\'s key set equals handleApprove\'s allowlist minus '
      'command, so an added key fails rather than being dropped',
      () {
        // Ruling 4. handleApprove's own `allowed` set, transcribed:
        // {command, session_id, revision, digest, policy_version}. The
        // body this model builds is everything but `command`, which the
        // repository's _invoke adds. Every branch rejects unknown keys
        // strictly, so an extra key here is an INVALID_INPUT on every
        // call rather than a harmless extra.
        const serverAllowlist = {
          'command',
          'session_id',
          'revision',
          'digest',
          'policy_version',
        };
        expect(serverAllowlist, hasLength(5));
        final body = AiSessionApprovalTicket.fromJson(
          reviewContextResponse(),
        ).toApproveBody();
        expect(body.keys.toSet(), serverAllowlist.difference({'command'}));
        expect(body.keys.toSet(), hasLength(4));
      },
    );

    test('toApproveBody carries no actor-naming field', () {
      // The actor comes from the verified user on every branch. The
      // envelope validator rejects 11 actor-naming spellings; this
      // guard is the stronger substring form Task 1 adopted, which
      // killed a 12th unlisted spelling the server's list omits.
      final body = AiSessionApprovalTicket.fromJson(
        reviewContextResponse(),
      ).toApproveBody();
      for (final key in body.keys) {
        expect(
          key.contains('actor') || key.contains('user'),
          isFalse,
          reason: '"$key" names an actor; the server resolves it itself',
        );
      }
    });
  });

  group('AiSessionApprovalResult — approve returns THREE fields', () {
    test('a sole approver who activated', () {
      final result = AiSessionApprovalResult.fromJson({
        'approved': true,
        'activated': true,
        'state': 'active',
      });
      expect(result.approved, isTrue);
      expect(result.activated, isTrue);
      expect(result.state, AiSessionState.active);
      expect(result.isWaitingForPartner, isFalse);
    });

    test(
      'a shared session\'s FIRST approver: activated false, state '
      'preparing — a SUCCESS, not an error',
      () {
        // handleApprove's APPROVAL_REQUIRED branch returns HTTP 200
        // with exactly this body: "NOT an error: this caller approved
        // successfully and is waiting for its partner ... reporting it
        // here would tell a partner who did everything right that they
        // failed."
        final result = AiSessionApprovalResult.fromJson({
          'approved': true,
          'activated': false,
          'state': 'preparing',
        });
        expect(result.approved, isTrue);
        expect(result.activated, isFalse);
        expect(result.state, AiSessionState.preparing);
        expect(result.isWaitingForPartner, isTrue);
      },
    );

    test('an already-active session retried after a dropped response', () {
      // handleApprove's `row.state === 'active'` early return: "a
      // client retrying its own approve after a dropped response must
      // not be told its session is unavailable".
      final result = AiSessionApprovalResult.fromJson({
        'approved': true,
        'activated': true,
        'state': 'active',
      });
      expect(result.state, AiSessionState.active);
      expect(result.isWaitingForPartner, isFalse);
    });

    test(
      'state is REQUIRED, so waiting-ness is never inferred from '
      '!activated',
      () {
        // RULING 1. Inferring waiting-ness from `activated: false` is
        // the same shape of mistake as inferring an error from an HTTP
        // status: it happens to agree on today's two bodies and would
        // silently diverge the moment a third disposition exists. The
        // model therefore THROWS on a missing state rather than
        // defaulting it, which is what makes the inference
        // unavailable rather than merely discouraged.
        expect(
          () => AiSessionApprovalResult.fromJson({
            'approved': true,
            'activated': false,
          }),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('state'),
            ),
          ),
        );
      },
    );

    test('throws for a state outside approve\'s two values', () {
      // handleApprove can only return "preparing" or "active" (every
      // other state is §3.1's indistinguishable UNAVAILABLE error, and
      // never a 200 body). A third value is a malformed response.
      expect(
        () => AiSessionApprovalResult.fromJson({
          'approved': true,
          'activated': false,
          'state': 'ended',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('ended'),
          ),
        ),
      );
    });

    test('isWaitingForPartner reads STATE, not activated', () {
      // The specific proof that the convenience getter is not a
      // re-introduction of the inference. A hypothetical body with
      // state 'active' but activated false must NOT read as waiting:
      // the state is the rendered truth.
      final impossible = AiSessionApprovalResult.fromJson({
        'approved': true,
        'activated': false,
        'state': 'active',
      });
      expect(
        impossible.isWaitingForPartner,
        isFalse,
        reason: 'state active means active, whatever activated says',
      );
    });

    test('AiSessionState has exactly the two values approve can return', () {
      expect(AiSessionState.values, hasLength(2));
      expect(AiSessionState.values.map((s) => s.wireValue).toSet(), {
        'preparing',
        'active',
      });
    });
  });

  group('the window toggle rides on review_context', () {
    // RULING 3 / Plan C Ruling 17 / Item A1. `set_include_window` is an
    // OPTIONAL field on review_context, not a tenth command: "the
    // toggle invalidates approvals and bumps the revision, so the ONLY
    // useful thing to do after it is re-read the context -- which is
    // what review_context does. Making it a separate command would
    // guarantee a client that toggled and then approved against the
    // stale revision it still held."
    test('the review_context body allowlist has FOUR keys', () {
      const serverAllowlist = {
        'command',
        'session_id',
        'utc_offset_minutes',
        'set_include_window',
      };
      expect(serverAllowlist, hasLength(4));
      expect(
        AiSessionContextReview.reviewCommandBodyKeys,
        serverAllowlist.difference({'command'}),
      );
      expect(AiSessionContextReview.reviewCommandBodyKeys, hasLength(3));
      expect(
        AiSessionContextReview.reviewCommandBodyKeys,
        contains('set_include_window'),
        reason:
            'a review_context modelled as read-only would miss the '
            'window toggle entirely',
      );
    });

    test(
      'a toggle bumps the revision, so a ticket taken before one is '
      'STALE and the model makes that visible',
      () {
        // handleReviewContext re-reads the row after a toggle and
        // computes the digest over "the state the toggle LEFT behind,
        // not the state it found", because "the toggle bumps the
        // revision and clears approvals, so a digest computed before it
        // would bind a revision the client could never approve at".
        //
        // Two reviews, before and after a toggle, therefore yield
        // different revisions AND different digests, and the pair must
        // travel together. The assertion is that the ticket binds both
        // as one unit — not that a caller remembers to.
        final before = AiSessionApprovalTicket.fromJson(
          reviewContextResponse(revision: 3, digest: kDigestA),
        );
        final after = AiSessionApprovalTicket.fromJson(
          reviewContextResponse(revision: 4, digest: kDigestB),
        );
        expect(before.revision, 3);
        expect(after.revision, 4);
        expect(before.digest, isNot(after.digest));
        // The pair is inseparable: there is no setter for either, so a
        // caller cannot send the new revision with the old digest.
        expect(after.toApproveBody()['revision'], 4);
        expect(after.toApproveBody()['digest'], kDigestB);
      },
    );

    test(
      'include_window on the response is the STORED setting the digest '
      'was computed under, so a toggle\'s effect is readable',
      () {
        // "The STORED setting the digest was computed under, so a
        // client can see whether its toggle took effect without a
        // second read." A client that asked for true and reads false
        // back has learnt its toggle did not apply (a private or Nearby
        // session cannot have a window at all), which is a different
        // state from an error.
        final applied = AiSessionContextReview.fromJson(
          reviewContextResponse(includeWindow: true),
        );
        final notApplied = AiSessionContextReview.fromJson(
          reviewContextResponse(includeWindow: false, window: const []),
        );
        expect(applied.includeWindow, isTrue);
        expect(notApplied.includeWindow, isFalse);
      },
    );
  });

  group('no model lets a caller conclude a session is gone', () {
    test(
      'AiSessionState cannot express ended, expired or unavailable',
      () {
        // The ai_sessions.state column has more values than these two,
        // but approve is the only command that returns a state in a 200
        // body and it can only return these two — every other state is
        // §3.1's deliberately indistinguishable UNAVAILABLE *error*.
        // So there is no enum case a caller could switch on to render
        // "gone", and the only way to learn it is the error code, which
        // is AiSessionError's job (Task 1).
        final wireValues = AiSessionState.values
            .map((s) => s.wireValue)
            .toSet();
        for (final absent in const [
          'ended',
          'expired',
          'unavailable',
          'gone',
          'failed',
        ]) {
          expect(
            wireValues,
            isNot(contains(absent)),
            reason: '"$absent" is an error code\'s job, not a state\'s',
          );
        }
      },
    );

    test('an empty window is not a terminal state', () {
      // The §7.2 silence trap in its review_context form: zero eligible
      // window messages and a toggle the server narrowed to false look
      // identical in `window: []`, and neither means the session is
      // gone. include_window is the field that distinguishes them, and
      // neither value is terminal.
      final review = AiSessionContextReview.fromJson(
        reviewContextResponse(window: const [], target: null),
      );
      expect(review.window, isEmpty);
      expect(review.target, isNull);
      // Nothing on the type says otherwise, and the proof is that the
      // field list has no terminal-state member.
      for (final absent in const [
        'state',
        'ended',
        'available',
        'exists',
      ]) {
        expect(
          AiSessionContextReview.wireKeysRead,
          isNot(contains(absent)),
          reason:
              'review_context does not report session liveness in its '
              '200 body; it reports UNAVAILABLE as an error',
        );
      }
    });
  });
}
