// test/features/ai_assistant/ai_session_turn_model_test.dart
//
// Fixtures in this file are transcribed from the SERVER, not from the
// task brief, because the brief's sample JSON contradicts the edge
// function in three places (see the task-2 report). Specifically:
//
//   * `handleRead` (supabase/functions/ai-sessions/index.ts:3320)
//     projects FIVE keys per turn -- ordinal, role, kind, payload,
//     created_at -- so every fixture here carries created_at.
//   * The payloads are exactly what the two committing RPCs insert:
//     20260953070000_ai_session_commit_ideas_rpc.sql writes
//     jsonb_build_object('instruction', ...) for the user row and
//     jsonb_build_object('reply_text', ..., 'suggested_planning_item',
//     ...) for the Attune row, both at kind='ideas_answer';
//     20260953080000_ai_session_nearby_staging_rpcs.sql writes
//     jsonb_build_object('instruction', 'nearby') and
//     jsonb_build_object('reply_text', ..., 'sources', ...), both at
//     kind='nearby_result'.
//   * NO 'redirect' turn can exist. See the group of tests at the end.
import 'package:attune/features/ai_assistant/data/models/ai_session_turn_model.dart';
import 'package:attune/features/ai_assistant/data/models/assist_draft_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact key set `handleRead` projects per turn row, transcribed
/// from the edge function's response literal. Used as a denominator
/// guard: a fixture that drops one of these is not a server shape.
const Set<String> kReadTurnProjectedKeys = {
  'ordinal',
  'role',
  'kind',
  'payload',
  'created_at',
};

Map<String, dynamic> ideasUserTurn({int ordinal = 1}) => {
  'ordinal': ordinal,
  'role': 'user',
  'kind': 'ideas_answer',
  'payload': {'instruction': 'brainstorm date ideas'},
  'created_at': '2026-09-27T10:00:00.000Z',
};

Map<String, dynamic> ideasAttuneTurn({
  int ordinal = 2,
  Object? suggestedPlanningItem = const {
    'kind': 'event',
    'title': 'Picnic',
    'event_date': '2026-09-27',
  },
}) => {
  'ordinal': ordinal,
  'role': 'attune',
  'kind': 'ideas_answer',
  'payload': {
    'reply_text': 'Try a picnic this weekend.',
    'suggested_planning_item': suggestedPlanningItem,
  },
  'created_at': '2026-09-27T10:00:01.000Z',
};

Map<String, dynamic> nearbyUserTurn({int ordinal = 3}) => {
  'ordinal': ordinal,
  'role': 'user',
  // NOT 'ideas_answer'. publish_ai_session_nearby_result inserts the
  // USER row at kind='nearby_result' too.
  'kind': 'nearby_result',
  'payload': {'instruction': 'nearby'},
  'created_at': '2026-09-27T11:00:00.000Z',
};

Map<String, dynamic> nearbyAttuneTurn({int ordinal = 4}) => {
  'ordinal': ordinal,
  'role': 'attune',
  'kind': 'nearby_result',
  'payload': {
    'reply_text': 'A few places nearby.',
    'sources': [
      {
        'provider_id': 'p1',
        'name': 'Cafe One',
        'formatted_address': '1 Main St',
        'category': 'cafe',
        'map_url': 'https://www.mapbox.com/search/p1',
      },
    ],
  },
  'created_at': '2026-09-27T11:00:01.000Z',
};

void main() {
  group('the fixtures are server shapes', () {
    test('every fixture carries exactly handleRead\'s five projected keys', () {
      final fixtures = <String, Map<String, dynamic>>{
        'ideas user': ideasUserTurn(),
        'ideas attune': ideasAttuneTurn(),
        'nearby user': nearbyUserTurn(),
        'nearby attune': nearbyAttuneTurn(),
      };
      // Denominator guard: four fixtures, not "whatever this map holds".
      expect(fixtures, hasLength(4));
      expect(kReadTurnProjectedKeys, hasLength(5));
      for (final entry in fixtures.entries) {
        expect(
          entry.value.keys.toSet(),
          kReadTurnProjectedKeys,
          reason: 'the ${entry.key} fixture is not handleRead\'s projection',
        );
      }
    });
  });

  group('user turns', () {
    test('parses an Ideas user turn', () {
      final turn = AiSessionTurnModel.fromJson(ideasUserTurn());
      expect(turn, isA<AiSessionUserTurn>());
      final user = turn as AiSessionUserTurn;
      expect(user.instruction, 'brainstorm date ideas');
      expect(user.ordinal, 1);
      expect(user.kind, AiSessionTurnKind.ideasAnswer);
      expect(user.createdAt, DateTime.parse('2026-09-27T10:00:00.000Z'));
    });

    test(
      'parses a Nearby user turn, whose kind is nearby_result not '
      'ideas_answer and whose instruction is the literal "nearby"',
      () {
        // This is the shape publish_ai_session_nearby_result inserts:
        // jsonb_build_object('instruction', 'nearby'). A model that
        // keyed the user branch off kind=='ideas_answer' would throw
        // here, and a model that dropped `kind` from user turns could
        // not tell an Ideas exchange from a Nearby one.
        final turn = AiSessionTurnModel.fromJson(nearbyUserTurn());
        expect(turn, isA<AiSessionUserTurn>());
        final user = turn as AiSessionUserTurn;
        expect(user.kind, AiSessionTurnKind.nearbyResult);
        expect(user.instruction, 'nearby');
        expect(user.ordinal, 3);
      },
    );

    test('throws when a user turn payload has no instruction', () {
      expect(
        () => AiSessionTurnModel.fromJson({
          'ordinal': 1,
          'role': 'user',
          'kind': 'ideas_answer',
          'payload': {'reply_text': 'wrong role shape'},
          'created_at': '2026-09-27T10:00:00.000Z',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('instruction'),
          ),
        ),
      );
    });
  });

  group('attune turns', () {
    test('parses an ideas_answer turn with a suggested planning item', () {
      final turn = AiSessionTurnModel.fromJson(ideasAttuneTurn());
      expect(turn, isA<AiSessionIdeasAnswerTurn>());
      final ideas = turn as AiSessionIdeasAnswerTurn;
      expect(ideas.replyText, 'Try a picnic this weekend.');
      expect(ideas.suggestedPlanningItem?.title, 'Picnic');
      expect(
        ideas.suggestedPlanningItem?.kind,
        SuggestedPlanningItemKind.event,
      );
      expect(
        ideas.suggestedPlanningItem?.eventDate,
        DateTime.parse('2026-09-27'),
      );
      expect(ideas.ordinal, 2);
      expect(ideas.kind, AiSessionTurnKind.ideasAnswer);
    });

    test(
      'parses an ideas_answer turn whose suggested_planning_item is an '
      'explicit JSON null, which the commit RPC always writes',
      () {
        // commit_ai_session_ideas_turn does
        // jsonb_build_object('reply_text', .., 'suggested_planning_item',
        // p_proposal), so the KEY IS ALWAYS PRESENT and is JSON null
        // when there is no proposal. It is never absent.
        final turn =
            AiSessionTurnModel.fromJson(
                  ideasAttuneTurn(suggestedPlanningItem: null),
                )
                as AiSessionIdeasAnswerTurn;
        expect(turn.suggestedPlanningItem, isNull);
        expect(turn.replyText, 'Try a picnic this weekend.');
      },
    );

    test('parses a nearby_result turn with source cards', () {
      final turn = AiSessionTurnModel.fromJson(nearbyAttuneTurn());
      expect(turn, isA<AiSessionNearbyResultTurn>());
      final nearby = turn as AiSessionNearbyResultTurn;
      expect(nearby.replyText, 'A few places nearby.');
      expect(nearby.sources, hasLength(1));
      expect(nearby.sources.single.name, 'Cafe One');
      expect(nearby.sources.single.providerId, 'p1');
      expect(nearby.ordinal, 4);
      expect(nearby.kind, AiSessionTurnKind.nearbyResult);
    });

    test('parses a nearby_result turn with zero sources', () {
      // buildNearbySessionReplyText's own no-results branch: "Zero
      // results is a deterministic no-results card." An empty sources
      // array is a VALID server response, not a malformed one.
      final json = nearbyAttuneTurn();
      json['payload'] = {
        'reply_text': 'No cafe results came back nearby. '
            'Try a different category.',
        'sources': <dynamic>[],
      };
      final turn =
          AiSessionTurnModel.fromJson(json) as AiSessionNearbyResultTurn;
      expect(turn.sources, isEmpty);
      expect(turn.replyText, contains('No cafe results'));
    });

    test('an Ideas answer turn has no sources field at all', () {
      // The sealed-on-discriminant property AssistDraftModel documents:
      // there is no shared nullable field either branch could
      // accidentally populate for the other.
      final ideas = AiSessionTurnModel.fromJson(ideasAttuneTurn());
      expect(ideas, isNot(isA<AiSessionNearbyResultTurn>()));
      final nearby = AiSessionTurnModel.fromJson(nearbyAttuneTurn());
      expect(nearby, isNot(isA<AiSessionIdeasAnswerTurn>()));
    });

    test('throws when an attune ideas_answer turn has no reply_text', () {
      expect(
        () => AiSessionTurnModel.fromJson({
          'ordinal': 2,
          'role': 'attune',
          'kind': 'ideas_answer',
          'payload': {'suggested_planning_item': null},
          'created_at': '2026-09-27T10:00:01.000Z',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('reply_text'),
          ),
        ),
      );
    });

    test('throws when an attune nearby_result turn has no sources', () {
      expect(
        () => AiSessionTurnModel.fromJson({
          'ordinal': 4,
          'role': 'attune',
          'kind': 'nearby_result',
          'payload': {'reply_text': 'A few places nearby.'},
          'created_at': '2026-09-27T11:00:01.000Z',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('sources'),
          ),
        ),
      );
    });

    test('propagates a malformed source card rather than dropping it', () {
      // PlaceSourceModel.fromJson throws on a missing provider_id. A
      // turn with one bad card must not render as a turn with fewer
      // cards -- Plan C's own source-card validation is a flagged
      // follow-up, so the client is not entitled to assume well-formed
      // cards.
      final json = nearbyAttuneTurn();
      json['payload'] = {
        'reply_text': 'A few places nearby.',
        'sources': [
          {'name': 'Cafe One'},
        ],
      };
      expect(
        () => AiSessionTurnModel.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('provider_id'),
          ),
        ),
      );
    });
  });

  group('no redirect turn can be parsed', () {
    // THE SPEC WAS AMENDED. handleGenerate's redirect branch (index.ts
    // ~2788) records §5.3 as amended by Plan C Task 6 / Item B: "NO
    // redirect becomes a transcript pair. ALL redirects are
    // requester-only". The ai_session_turns kind CHECK still allows
    // 'redirect', but commit_ai_session_ideas_turn hardcodes
    // 'ideas_answer', publish_ai_session_nearby_result hardcodes
    // 'nearby_result', and share_ai_session_turn names 'redirect' only
    // to REJECT it -- so no code path can create one. A redirect is a
    // `generate` RESPONSE BODY ({kind, reason, offered,
    // show_safety_resources}), never a turn row.
    //
    // Modelling it as a turn subtype would be worse than redundant: a
    // durable redirect would be the safety side channel §8.1 forbids
    // (redirect and refusal share a reason set), so a client that
    // rendered one from a transcript would be rendering something the
    // server went out of its way never to persist.
    test('a redirect kind is rejected, not parsed into a turn', () {
      expect(
        () => AiSessionTurnModel.fromJson({
          'ordinal': 2,
          'role': 'attune',
          'kind': 'redirect',
          'payload': {'reason': 'unsupported', 'offered': ['ideas']},
          'created_at': '2026-09-27T10:00:01.000Z',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            // The message must name the KIND, not a missing payload
            // field. Mutation 1 (adding a `redirect` enum case) first
            // made this test fail on 'missing/invalid reply_text' --
            // the right verdict for the wrong reason. Requiring both
            // substrings means only a genuine kind-rejection passes.
            allOf(contains('redirect'), contains('kind')),
          ),
        ),
      );
    });

    test(
      'a redirect is rejected even when its payload would satisfy '
      'another branch',
      () {
        // The attributability case. A redirect payload that ALSO
        // carries reply_text and sources cannot fail for a missing
        // field, so this test can only pass if `kind` itself is
        // refused. Without it, a model that accepted 'redirect' and
        // fell through to the nearby_result branch would be caught only
        // by the enum-length assertion -- one test, and one that a
        // careless future edit could update in the same commit.
        expect(
          () => AiSessionTurnModel.fromJson({
            'ordinal': 2,
            'role': 'attune',
            'kind': 'redirect',
            'payload': {
              'reason': 'unsupported',
              'offered': ['ideas'],
              'reply_text': 'a redirect that looks like an answer',
              'sources': <dynamic>[],
              'suggested_planning_item': null,
            },
            'created_at': '2026-09-27T10:00:01.000Z',
          }),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('redirect'), contains('kind')),
            ),
          ),
        );
      },
    );

    test('a redirect is rejected for a USER role too', () {
      // No ordering accident: the role branch runs before the kind
      // switch in some parsers. This pins that a redirect is refused
      // whichever role carries it.
      expect(
        () => AiSessionTurnModel.fromJson({
          'ordinal': 1,
          'role': 'user',
          'kind': 'redirect',
          'payload': {'instruction': 'something'},
          'created_at': '2026-09-27T10:00:00.000Z',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('redirect'), contains('kind')),
          ),
        ),
      );
    });

    test('AiSessionTurnKind has exactly the two kinds read can return', () {
      // Denominator guard. The table's CHECK allows three values; only
      // two are reachable through read. If a future migration makes
      // redirect reachable, this fails and forces the decision to be
      // taken deliberately rather than by a parser silently coping.
      expect(AiSessionTurnKind.values, hasLength(2));
      expect(AiSessionTurnKind.values.map((k) => k.wireValue).toSet(), {
        'ideas_answer',
        'nearby_result',
      });
    });
  });

  group('envelope validation', () {
    test('throws for an unrecognized kind rather than returning null', () {
      expect(
        () => AiSessionTurnModel.fromJson({
          'ordinal': 1,
          'role': 'attune',
          'kind': 'nonsense',
          'payload': <String, dynamic>{},
          'created_at': '2026-09-27T10:00:00.000Z',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('nonsense'),
          ),
        ),
      );
    });

    test('throws for an unrecognized role', () {
      expect(
        () => AiSessionTurnModel.fromJson({
          'ordinal': 1,
          'role': 'system',
          'kind': 'ideas_answer',
          'payload': {'instruction': 'x'},
          'created_at': '2026-09-27T10:00:00.000Z',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('system'),
          ),
        ),
      );
    });

    test('throws for a missing ordinal', () {
      final json = ideasUserTurn()..remove('ordinal');
      expect(
        () => AiSessionTurnModel.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('ordinal'),
          ),
        ),
      );
    });

    test('throws for a missing payload', () {
      final json = ideasUserTurn()..remove('payload');
      expect(
        () => AiSessionTurnModel.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('payload'),
          ),
        ),
      );
    });

    test('throws for a missing created_at', () {
      final json = ideasUserTurn()..remove('created_at');
      expect(
        () => AiSessionTurnModel.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('created_at'),
          ),
        ),
      );
    });

    test('rejects an ordinal outside the table CHECK of 1..20', () {
      // ai_session_turns: CHECK (ordinal BETWEEN 1 AND 20). §5.2's
      // twenty-ordinal cap. A 0 or a 21 is not a value the server can
      // have written, so it is a malformed response.
      for (final bad in [0, 21, -1]) {
        expect(
          () => AiSessionTurnModel.fromJson(ideasUserTurn(ordinal: bad)),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('ordinal'),
            ),
          ),
          reason: 'ordinal $bad is outside the table CHECK',
        );
      }
      // And the boundaries themselves are accepted.
      expect(
        AiSessionTurnModel.fromJson(ideasUserTurn(ordinal: 1)).ordinal,
        1,
      );
      expect(
        AiSessionTurnModel.fromJson(ideasUserTurn(ordinal: 20)).ordinal,
        20,
      );
    });
  });

  group('AiSessionTranscript', () {
    test('parses handleRead\'s turns array in order', () {
      final transcript = AiSessionTranscript.fromJson({
        'turns': [
          ideasUserTurn(ordinal: 1),
          ideasAttuneTurn(ordinal: 2),
        ],
      });
      expect(transcript.turns.map((t) => t.ordinal), [1, 2]);
      expect(transcript.turns.first, isA<AiSessionUserTurn>());
      expect(transcript.turns.last, isA<AiSessionIdeasAnswerTurn>());
    });

    test(
      'accepts NON-CONTIGUOUS ordinals -- a failed attempt leaves a gap',
      () {
        // Plan B: the ordinal pair for attempt n is exactly (2n-1, 2n),
        // and the attempt counter advances on a FAILED attempt too, so
        // attempt 1 failing and attempt 2 committing yields (3, 4) with
        // no 1 or 2 in the table. Measured in Plan B as exactly that.
        // A transcript that assumed contiguity -- indexing by ordinal,
        // asserting turns[i].ordinal == i + 1, or computing attempt
        // count from length -- would be wrong here.
        final transcript = AiSessionTranscript.fromJson({
          'turns': [
            ideasUserTurn(ordinal: 3),
            ideasAttuneTurn(ordinal: 4),
            ideasUserTurn(ordinal: 7),
            ideasAttuneTurn(ordinal: 8),
          ],
        });
        expect(transcript.turns.map((t) => t.ordinal), [3, 4, 7, 8]);
        // The SPECIFIC property: the first turn's ordinal is not 1, and
        // there is a gap of more than one between the pairs.
        expect(transcript.turns.first.ordinal, 3);
        expect(
          transcript.turns[2].ordinal - transcript.turns[1].ordinal,
          3,
          reason: 'attempts 3 and 4 both failed, leaving ordinals 5 and 6 unused',
        );
      },
    );

    test(
      'an empty turns array parses to an empty transcript and asserts '
      'NOTHING about whether the session exists',
      () {
        // handleRead returns HTTP 200 with turns: [] for EVERY
        // unauthorized outcome -- unknown session, non-member, withdrawn
        // consent, an unapproved shared session, an expired staging row
        // -- and also for a perfectly healthy session with no committed
        // turns yet. Its header says a partner's zero rows and a
        // stranger's zero rows must be byte-identical, precisely so the
        // RPC cannot become an existence oracle.
        //
        // So there is DELIBERATELY no `isGone`, `isEmpty`-as-terminal,
        // `exists` or `isUnavailable` on this type. The assertions below
        // pin that absence: they are the proof a caller CANNOT conclude
        // "session gone" from this model.
        final transcript = AiSessionTranscript.fromJson({
          'turns': <dynamic>[],
        });
        expect(transcript.turns, isEmpty);
        expect(transcript.staged, isNull);
      },
    );

    test(
      'AiSessionTranscript exposes no member that could mean "gone"',
      () {
        // A behavioural guard, not a comment: the type has exactly two
        // members, so a later task cannot add `isGone` without this
        // failing. Dart has no reflection in this test context, so the
        // guard is the documented-and-asserted shape below plus the
        // analyzer's exhaustiveness on the sealed turn type.
        final transcript = AiSessionTranscript.fromJson({
          'turns': <dynamic>[],
        });
        // Emptiness carries no verdict: the SAME empty transcript is
        // the legitimate "no turns committed yet" state, so any code
        // reading a verdict out of it is reading one that is not there.
        expect(
          transcript.turns.isEmpty,
          isTrue,
          reason: 'empty is a legitimate state, never a terminal one',
        );
      },
    );

    test('staged is absent when no request_id was asked for', () {
      // handleRead: `staged` is undefined (absent) rather than [] when
      // the caller did not supply a request_id, "so a client can tell
      // 'I did not ask' from 'I asked and there is nothing'".
      final transcript = AiSessionTranscript.fromJson({
        'turns': [ideasUserTurn()],
      });
      expect(transcript.staged, isNull);
    });

    test('staged is an EMPTY LIST when asked for and there is nothing', () {
      // The distinction above, from the other side. Null and empty mean
      // different things here, and collapsing them would destroy the one
      // distinction handleRead deliberately preserves.
      final transcript = AiSessionTranscript.fromJson({
        'turns': <dynamic>[],
        'staged': <dynamic>[],
      });
      expect(transcript.staged, isNotNull);
      expect(transcript.staged, isEmpty);
    });

    test('parses a staged Nearby result', () {
      final transcript = AiSessionTranscript.fromJson({
        'turns': <dynamic>[],
        'staged': [
          {
            'request_id': '11111111-1111-4111-8111-111111111111',
            'reply_text': 'A few places nearby.',
            'sources': [
              {
                'provider_id': 'p1',
                'name': 'Cafe One',
                'formatted_address': '1 Main St',
                'category': 'cafe',
                'map_url': 'https://www.mapbox.com/search/p1',
              },
            ],
            'expires_at': '2026-09-27T11:02:00.000Z',
          },
        ],
      });
      final staged = transcript.staged!.single;
      expect(staged.requestId, '11111111-1111-4111-8111-111111111111');
      expect(staged.replyText, 'A few places nearby.');
      expect(staged.sources.single.name, 'Cafe One');
      expect(staged.expiresAt, DateTime.parse('2026-09-27T11:02:00.000Z'));
    });

    test('a staged result carries NO confirmation nonce', () {
      // Gate 4: the Nearby confirmation_nonce is DECORATIVE -- there is
      // no issuing RPC, column or table. read_ai_session_staging
      // projects four fields (request_id, reply_text, sources,
      // expires_at) and none of them is a nonce. A model carrying one
      // would present a confirmation the server never issued.
      final transcript = AiSessionTranscript.fromJson({
        'turns': <dynamic>[],
        'staged': [
          {
            'request_id': '11111111-1111-4111-8111-111111111111',
            'reply_text': 'x',
            'sources': <dynamic>[],
            'expires_at': '2026-09-27T11:02:00.000Z',
            // An extra key the server does not send. It must be IGNORED
            // on the way in, not surfaced -- the client must not grow a
            // field for a control that does not exist.
            'confirmation_nonce': 'deadbeef',
          },
        ],
      });
      expect(transcript.staged!.single.requestId, isNotEmpty);
      // The proof is structural: AiSessionStagedNearbyResult has no
      // nonce member, so this fixture's extra key cannot be read back.
      // Asserted via the only surface that exists.
      expect(
        AiSessionStagedNearbyResult.wireKeys,
        {'request_id', 'reply_text', 'sources', 'expires_at'},
      );
      expect(AiSessionStagedNearbyResult.wireKeys, hasLength(4));
      expect(
        AiSessionStagedNearbyResult.wireKeys,
        isNot(contains('confirmation_nonce')),
      );
    });

    test('throws when the turns key is missing entirely', () {
      // handleRead ALWAYS sends `turns`. Its absence is a malformed
      // response, which must not be read as an empty transcript --
      // that would be exactly the "empty means gone" inference in
      // reverse, manufacturing a benign empty state out of a broken one.
      expect(
        () => AiSessionTranscript.fromJson(<String, dynamic>{}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('turns'),
          ),
        ),
      );
    });
  });
}
