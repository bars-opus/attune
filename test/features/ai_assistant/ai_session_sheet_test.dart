// Tests for AiSessionController and AiSessionSheet (AI Assistant spec
// §3-§8): preparation, approval, the live transcript, and the
// instruction field.
//
// ## What this file is PROVING, beyond "the sheet works"
//
// Four ledger rulings land in this file, and three of them are
// properties a widget is the easiest place in the whole plan to
// destroy:
//
//  - **RULING 6** — `generate` returns TWO `kind: "redirect"` shapes
//    that deliberately share the kind AND the reason set: a safety
//    refusal with a server-rendered `copy` and an EMPTY `offered`, and
//    the model's ordinary redirect with NO `copy`. §8.1 forbids
//    disclosing which detector fired, to either party. Task 4 closed
//    the MODEL surface structurally (`_copy` is private, reachable only
//    through a total `resolveCopy`), but **a different widget tree for
//    the two shapes is a visible oracle to anyone watching the
//    screen** — which no model-level test can catch. The
//    `RULING 6` group below renders both and compares the trees.
//  - **RULING 9** — `staged`'s null-vs-empty distinction. `null` means
//    no read asked; `[]` means a read asked and there is nothing. The
//    first `?? []` at a call site destroys it, and a sheet feeding a
//    `ListView` is exactly where that gets written.
//  - **RULING 12** — the `reviewContext` record must be DESTRUCTURED at
//    its call site, because the field names carry gate 2's
//    compile-time proof.
//  - **RULING 15** — resolved in this task: `publish_nearby` can answer
//    a redirect at HTTP 200, and it renders through the same slot and
//    the same widget as a `generate` redirect.
//
// ## Design decisions this file locks in (the spec leaves the UX open)
//
//  - A redirect renders as a NEUTRAL INLINE NOTICE, never a bubble
//    styled as if Attune said something conversational — §1's "not a
//    conversational AI persona" framing, applied inside the session's
//    own UI.
//  - `activated: false` renders "waiting for your partner", read from
//    the server's `state` rather than inferred from `!activated`.
//  - A `CONTEXT_CHANGED` offers RE-REVIEW, never a retry: a client
//    cannot recompute the digest (gate 2), so there is no local path
//    back to a valid approval.
//  - An EMPTY transcript renders as an empty transcript, never as
//    "this session has ended" — §7.2's silence requirement.
import 'dart:io';

import 'package:attune/features/ai_assistant/data/models/ai_session_model.dart';
import 'package:attune/features/ai_assistant/data/models/ai_session_turn_model.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_error.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_repository.dart';
import 'package:attune/features/ai_assistant/data/services/ai_session_capabilities.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_session_provider.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ai_session_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

// ---------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------

/// Routes one `ai-sessions` call per `command`, so a test states what
/// each command answers and nothing else.
///
/// A real edge-function call always crosses an await boundary later than
/// the next frame; the delay keeps a "no premature render" assertion
/// from being vacuous, which is the same reasoning
/// `assist_sheet_test.dart`'s own fake records.
class _FakeSessionGateway implements AiAssistantGateway {
  _FakeSessionGateway(this.handlers);

  final Map<String, Object? Function(Map<String, dynamic> body)> handlers;
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    bodies.add(Map<String, dynamic>.from(body ?? const <String, dynamic>{}));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final command = body?['command'] as String?;
    final handler = handlers[command];
    if (handler == null) {
      throw StateError('no fake handler for command "$command"');
    }
    return handler(Map<String, dynamic>.from(body!));
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------
// Server-shaped fixtures, transcribed from the handlers
// ---------------------------------------------------------------------

const String _sessionId = '11111111-2222-4333-8444-555555555555';
const String _requestId = '66666666-7777-4888-8999-aaaaaaaaaaaa';
const String _messageId = 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff';

Map<String, dynamic> _prepareResponse({int revision = 1}) =>
    <String, dynamic>{
      'session_id': _sessionId,
      'revision': revision,
      'created': true,
    };

/// `handleReviewContext`'s own flat body, which the repository splits
/// into the review half and the approval ticket. `civil_day_start_utc`
/// is present and read by neither half, on purpose.
Map<String, dynamic> _reviewResponse({
  int revision = 1,
  bool includeWindow = false,
  String kind = 'ideas',
  String visibility = 'private',
  List<Map<String, dynamic>>? window,
}) => <String, dynamic>{
  'session_id': _sessionId,
  'kind': kind,
  'visibility': visibility,
  'include_window': includeWindow,
  'utc_offset_minutes': 0,
  'window': window ?? <Map<String, dynamic>>[],
  'target': null,
  'revision': revision,
  'policy_version': 'v1',
  // 64 lowercase hex: the shape `AiSessionApprovalTicket.fromJson`
  // enforces. It is an opaque SHA-256 the client cannot recompute
  // (gate 2), so a human-readable stand-in is not a legal digest and
  // the model rejects one — which this fixture originally learned the
  // hard way.
  'digest': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1',
  'civil_day_start_utc': '2026-10-11T00:00:00.000Z',
};

/// `{approved, activated, state}` — THREE fields. `activated: false`
/// with `state: "preparing"` is a 200 SUCCESS meaning "waiting for your
/// partner", never `APPROVAL_REQUIRED`.
Map<String, dynamic> _approveResponse({required bool activated}) =>
    <String, dynamic>{
      'approved': true,
      'activated': activated,
      'state': activated ? 'active' : 'preparing',
    };

Map<String, dynamic> _turn({
  required int ordinal,
  required String role,
  String kind = 'ideas_answer',
  Map<String, dynamic>? payload,
}) => <String, dynamic>{
  'ordinal': ordinal,
  'role': role,
  'kind': kind,
  'payload': payload ??
      (role == 'user'
          ? <String, dynamic>{'instruction': 'what should we do friday'}
          : <String, dynamic>{'reply_text': 'A few ideas for Friday.'}),
  'created_at': '2026-10-11T10:00:00.000Z',
};

/// THE SAFETY REFUSAL, transcribed verbatim from
/// `safetyRefusalResponse` (index.ts:2144): a server-rendered `copy`
/// and an EMPTY `offered`.
Map<String, dynamic> _safetyRefusal({String reason = 'unsafe_to_assist'}) =>
    <String, dynamic>{
      'kind': 'redirect',
      'reason': reason,
      'copy': 'I am not able to help with this. Support resources are '
          'available if you want them.',
      'show_safety_resources': true,
      'offered': <dynamic>[],
    };

/// `handleReadState`'s body: `{revision, state}`, both always present.
/// A `state: null` is the SILENT answer (zero rows from the RPC), which
/// the repository maps to a null snapshot -- "no answer", never "ended".
Map<String, dynamic> _readStateResponse({int? revision, String? state}) =>
    <String, dynamic>{'revision': revision, 'state': state};

/// THE ORDINARY MODEL REDIRECT (index.ts:2707/:2806): the SAME `kind`,
/// a reason from the SAME set, and NO `copy`.
Map<String, dynamic> _ordinaryRedirect({
  String reason = 'unsafe_to_assist',
  List<String> offered = const <String>[],
}) => <String, dynamic>{
  'kind': 'redirect',
  'reason': reason,
  'offered': offered,
  'show_safety_resources': true,
};

Map<String, dynamic> _ideasAnswer({
  int userOrdinal = 1,
  int attuneOrdinal = 2,
  int sessionRevision = 2,
}) => <String, dynamic>{
  'kind': 'answer',
  'user_ordinal': userOrdinal,
  'attune_ordinal': attuneOrdinal,
  'reply_text': 'A few ideas for Friday.',
  'suggested_planning_item': null,
  'session_revision': sessionRevision,
};

Map<String, dynamic> _stagedNearby() => <String, dynamic>{
  'kind': 'nearby_result',
  'staged': true,
  'request_id': _requestId,
  'reply_text': 'Two places near you.',
  'sources': <Map<String, dynamic>>[
    <String, dynamic>{
      // `provider_id` is REQUIRED by PlaceSourceModel and spec §5.2's
      // field list. A fixture without it does not parse — which this
      // file learned by watching `pendingStage` come back null.
      'provider_id': 'place-1',
      'name': 'The Corner Cafe',
      'formatted_address': '12 Main St',
    },
  ],
  'show_safety_resources': true,
};

// ---------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------

ProviderContainer _container(AiAssistantGateway gateway) {
  final container = ProviderContainer(
    overrides: [
      aiSessionRepositoryProvider.overrideWithValue(
        AiSessionRepository(gateway),
      ),
    ],
  );
  addTearDown(container.dispose);
  // KEEPS THE AUTODISPOSE PROVIDER ALIVE FOR THE TEST'S DURATION.
  // Without a listener, `.autoDispose` tears the notifier down the
  // moment each `read` returns, so a `read(provider)` after a
  // `read(provider.notifier)` observes a FRESH instance whose state is
  // the initial one — the controller's work really happened (the
  // gateway bodies prove it) but on an instance nothing held.
  //
  // This is the provider's `.autoDispose` contract doing exactly what
  // §1 wants it to in production, where the SHEET is the listener. The
  // subscription makes the test hold the reference the widget would.
  container.listen(
    aiSessionControllerProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return container;
}

/// Everything on, so a capability test is the one that turns things
/// off rather than every other test having to turn them on.
const AiSessionCapabilities _allOn = AiSessionCapabilities(
  assist: true,
  sessionsPrivate: true,
  sessionsShared: true,
  sessionsRecentWindow: true,
  sessionsNearby: true,
);

Future<void> _pumpSheet(
  WidgetTester tester,
  _FakeSessionGateway gateway, {
  AiSessionCapabilities capabilities = _allOn,
  AiSessionKind kind = AiSessionKind.ideas,
}) async {
  // A FRESH ProviderScope per pump, keyed so a second `_pumpSheet` in
  // one test tears the previous `.autoDispose` controller down instead
  // of inheriting its phase. Without the key, Flutter reuses the
  // element, the controller survives, and the second render starts
  // already past `choosing` — which is how the RULING 6 comparison
  // first failed, on a finder for a button the first render had
  // already left behind.
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        aiSessionRepositoryProvider.overrideWithValue(
          AiSessionRepository(gateway),
        ),
        aiSessionCapabilitiesProvider.overrideWith(
          (ref) => Future<AiSessionCapabilities>.value(capabilities),
        ),
      ],
      child: MaterialApp(
        home: AiSessionSheet(
          relationshipId: 'rel-1',
          initialKind: kind,
          utcOffsetMinutes: 0,
          onShared: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ===================================================================
  // AiSessionController
  // ===================================================================

  group('AiSessionController: prepare', () {
    test(
      'prepare moves from idle to a real session id and a reviewed '
      'context, reading the id from the RESPONSE rather than the key',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(revision: 4),
          'review_context': (_) => _reviewResponse(revision: 4),
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        expect(
          container.read(aiSessionControllerProvider).phase,
          AiSessionPhase.choosing,
        );
        expect(container.read(aiSessionControllerProvider).sessionId, isNull);

        await controller.prepare(
          idempotencyKey: 'a-key-the-client-generated',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );

        final state = container.read(aiSessionControllerProvider);
        // The SERVER's id, not the key: a replay returns the ORIGINAL
        // session, so a controller that assumed key == id would key its
        // own state to a session that is not the one it got.
        expect(state.sessionId, _sessionId);
        expect(state.sessionId, isNot('a-key-the-client-generated'));
        expect(state.revision, 4);
        expect(state.phase, AiSessionPhase.reviewing);
        expect(state.review, isNotNull);
        expect(state.busy, isFalse);
        expect(state.error, isNull);
      },
    );

    test(
      'prepare sends the displayed utc offset and review_context sends it '
      'again — both commands require it on EVERY call',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
        });
        final container = _container(gateway);

        await container
            .read(aiSessionControllerProvider.notifier)
            .prepare(
              idempotencyKey: 'key',
              relationshipId: 'rel-1',
              kind: AiSessionKind.ideas,
              visibility: AiSessionVisibility.private,
              // A real offset, not zero: a sheet that dropped the field
              // or sent a constant would still pass against 0.
              utcOffsetMinutes: 330,
            );

        final prepare = gateway.bodies.firstWhere(
          (b) => b['command'] == 'prepare',
        );
        final review = gateway.bodies.firstWhere(
          (b) => b['command'] == 'review_context',
        );
        expect(prepare['utc_offset_minutes'], 330);
        expect(review['utc_offset_minutes'], 330);
        // `isValidUtcOffsetMinutes` refuses an absent value with
        // INVALID_INPUT rather than clamping, so the key's PRESENCE is
        // as load-bearing as its value.
        expect(review.containsKey('utc_offset_minutes'), isTrue);
      },
    );

    test('a §10 error from prepare lands in the state by CODE', () async {
      final gateway = _FakeSessionGateway({
        'prepare': (_) => throw _functionError('SESSION_LIMIT_REACHED', 409),
      });
      final container = _container(gateway);

      await container
          .read(aiSessionControllerProvider.notifier)
          .prepare(
            idempotencyKey: 'key',
            relationshipId: 'rel-1',
            kind: AiSessionKind.ideas,
            visibility: AiSessionVisibility.private,
            utcOffsetMinutes: 0,
          );

      final state = container.read(aiSessionControllerProvider);
      // The SPECIFIC subtype, not "an error": five §10 codes share 409,
      // so asserting `isA<AiSessionError>()` would pass for a mapper
      // that read the status.
      expect(state.error, isA<AiSessionLimitReachedError>());
      expect(state.phase, AiSessionPhase.choosing);
      expect(state.busy, isFalse);
    });
  });

  group('AiSessionController: approve', () {
    test(
      'activated: false with state "preparing" is a SUCCESS — '
      'waitingForPartner, not an error',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) =>
              _reviewResponse(visibility: 'shared'),
          'approve': (_) => _approveResponse(activated: false),
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.shared,
          utcOffsetMinutes: 0,
        );
        await controller.approve();

        final state = container.read(aiSessionControllerProvider);
        expect(state.phase, AiSessionPhase.waitingForPartner);
        // THE POINT: not an error. APPROVAL_REQUIRED belongs to a
        // caller that tried to GENERATE without approval; reporting it
        // here "would tell a partner who did everything right that they
        // failed".
        expect(state.error, isNull);
        // And no `read` was issued — a preparing session has no
        // transcript to fetch.
        expect(
          gateway.bodies.where((b) => b['command'] == 'read'),
          isEmpty,
        );
      },
    );

    test(
      'activated: true activates and reads the transcript',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{
            'turns': <Map<String, dynamic>>[
              _turn(ordinal: 1, role: 'user'),
              _turn(ordinal: 2, role: 'attune'),
            ],
          },
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );
        await controller.approve();

        final state = container.read(aiSessionControllerProvider);
        expect(state.phase, AiSessionPhase.active);
        expect(state.turns, hasLength(2));
        expect(state.turns.first.ordinal, 1);
      },
    );

    test(
      'the phase is read from the server STATE, not inferred from '
      '!activated — a disagreeing body follows `state`',
      () async {
        // A body the server does not send, used as a PROBE: if the
        // controller inferred waiting-ness from `!activated` it would
        // report waitingForPartner here, and if it reads `state` it
        // reports active. Only one of those can be true of a given
        // implementation, so this test distinguishes them.
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => <String, dynamic>{
            'approved': true,
            'activated': false,
            'state': 'active',
          },
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );
        await controller.approve();

        expect(
          container.read(aiSessionControllerProvider).phase,
          AiSessionPhase.active,
        );
      },
    );

    test(
      'GATE 2: approve sends the ticket WHOLE — exactly handleApprove\'s '
      'four keys, and the digest is never spelled at the call site',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(revision: 7),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );
        await controller.approve();

        final approve = gateway.bodies.firstWhere(
          (b) => b['command'] == 'approve',
        );
        // RULING 4: `handleApprove`'s allowlist, transcribed.
        expect(approve.keys.toSet(), {
          'command',
          'session_id',
          'revision',
          'digest',
          'policy_version',
        });
        // The digest is the SERVER's, carried opaquely — never derived.
        expect(approve['digest'], 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1');
        // The POST-review revision, which is what makes the ticket
        // approvable as returned.
        expect(approve['revision'], 7);
      },
    );

    test(
      'GATE 2: the view state has NO digest field — a widget cannot see '
      'one, proved from the declarations',
      () {
        // Structural, read from source, for the reason Task 4's M1b
        // established: a hand-written name list only catches a mutation
        // whose author updates the list. `flutter_test` has no
        // reflection, so this reads the class's own declarations — the
        // technique test/features/games/community_entry_test.dart and
        // test/core/android_manifest_test.dart already use here.
        final source = File(
          'lib/features/ai_assistant/presentation/providers/'
          'ai_session_provider.dart',
        ).readAsStringSync();

        const declaration = 'class AiSessionViewState {';
        final start = source.indexOf(declaration);
        expect(
          start,
          isNonNegative,
          reason: 'AiSessionViewState moved or was renamed — re-point this '
              'test rather than deleting it',
        );
        final nextTopLevel = source.indexOf('\nclass ', start + 1);
        expect(nextTopLevel, isNonNegative);
        final body = source.substring(start, nextTopLevel);
        // Anti-vacuity: the slice really is this class.
        expect(body, contains('final AiSessionPhase phase;'));
        expect(body, contains('copyWith'));
        expect(body.length, lessThan(source.length));

        final stripped = body
            .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
            .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
            .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
        // THE STRIPPER WORKS, proved on a phrase that appears in this
        // class ONLY inside a comment. Without this the assertions
        // below would be reading prose as code — the trap this effort
        // has recorded three times, which fired on this very test when
        // its first probe turned out to live in a DIFFERENT class's
        // doc comment and the `contains` therefore failed outright.
        expect(
          body,
          contains('another name'),
          reason: 'the probe should be present BEFORE stripping — it '
              'appears only inside this class\'s own doc comments',
        );
        expect(
          stripped,
          isNot(contains('another name')),
          reason: 'comment stripping failed, so every assertion below '
              'would be reading prose as code',
        );

        // No declaration mentions a digest, a ticket or a policy
        // version. Gate 2's client-side half is that a widget holding
        // the review half has no digest in scope.
        expect(stripped.toLowerCase(), isNot(contains('digest')));
        expect(stripped.toLowerCase(), isNot(contains('ticket')));
        expect(stripped.toLowerCase(), isNot(contains('policyversion')));
      },
    );

    test(
      'a CONTEXT_CHANGED is remedied by RE-REVIEW, and the re-review '
      'yields a new ticket that approves',
      () async {
        var approveCalls = 0;
        var reviewCalls = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(revision: 1),
          'review_context': (_) {
            reviewCalls++;
            // The second review reports the MOVED revision and a new
            // digest, which is the only way back to a valid approval.
            return reviewCalls == 1
                ? _reviewResponse(revision: 1)
                : <String, dynamic>{
                    ..._reviewResponse(revision: 2),
                    'digest': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2',
                  };
          },
          'approve': (_) {
            approveCalls++;
            if (approveCalls == 1) {
              throw _functionError('CONTEXT_CHANGED', 409);
            }
            return _approveResponse(activated: true);
          },
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );
        await controller.approve();
        expect(
          container.read(aiSessionControllerProvider).error,
          isA<AiSessionContextChangedError>(),
        );

        // THE REMEDY: re-review, then approve the digest IT returned.
        // Never recompute-and-retry — a client cannot recompute the
        // digest at all (gate 2).
        await controller.refreshContext(utcOffsetMinutes: 0);
        await controller.approve();

        expect(
          container.read(aiSessionControllerProvider).phase,
          AiSessionPhase.active,
        );
        expect(container.read(aiSessionControllerProvider).error, isNull);
        final secondApprove = gateway.bodies
            .where((b) => b['command'] == 'approve')
            .last;
        // The SECOND digest, from the SECOND review. A retry that
        // resent the first would have been the recompute-and-retry the
        // gate forbids.
        expect(secondApprove['digest'], 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2');
        expect(secondApprove['revision'], 2);
      },
    );
  });

  group('AiSessionController: read', () {
    test(
      '§7.2: an EMPTY transcript is NOT evidence the session is gone — no '
      'error, no phase change',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          // 200-with-empty-array, which `handleRead` returns for a
          // stranger, a non-approver AND a healthy session with no
          // committed turn, all byte-identical.
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );
        await controller.approve();

        final state = container.read(aiSessionControllerProvider);
        expect(state.turns, isEmpty);
        expect(state.error, isNull);
        // Specifically NOT `ended`: emptiness carries no verdict.
        expect(state.phase, AiSessionPhase.active);
        expect(state.phase, isNot(AiSessionPhase.ended));
      },
    );

    test(
      'NON-CONTIGUOUS ordinals survive the round trip unrenumbered — 3/4 '
      'with no 1/2 is a legal transcript',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{
            // A failed first attempt advanced the counter, so the
            // committed pair is 3/4. Measured in Plan B as exactly
            // this.
            'turns': <Map<String, dynamic>>[
              _turn(ordinal: 3, role: 'user'),
              _turn(ordinal: 4, role: 'attune'),
            ],
          },
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );
        await controller.approve();

        final turns = container.read(aiSessionControllerProvider).turns;
        // NOT renumbered to 1/2, and NOT padded with placeholders for
        // the missing 1/2: a gap is a FAILED ATTEMPT, and the turns it
        // would have written do not exist.
        expect(turns.map((t) => t.ordinal).toList(), <int>[3, 4]);
        expect(turns, hasLength(2));
        // And the length is not an attempt count: two turns here are
        // attempt TWO.
        expect(turns.length, isNot(4));
      },
    );
  });

  // ===================================================================
  // RULING 9 — staged's null-vs-empty distinction
  // ===================================================================

  group('RULING 9: staged null vs empty', () {
    test(
      'a read with NO request_id leaves stagedResults NULL — "I did not '
      'ask", and the request_id key is OMITTED rather than sent null',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          // `handleRead` sends `staged` ABSENT when no request_id was
          // supplied — not as `[]`.
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.nearby,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );
        await controller.approve();

        expect(
          container.read(aiSessionControllerProvider).stagedResults,
          isNull,
        );
        final read = gateway.bodies.firstWhere(
          (b) => b['command'] == 'read',
        );
        // "I did not ask" stays LITERAL on the wire: the key is absent,
        // not present-and-null.
        expect(read.containsKey('request_id'), isFalse);
      },
    );

    test(
      'a read WITH a request_id and an EMPTY staged array leaves '
      'stagedResults EMPTY, not null — "I asked and there is nothing"',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (body) => body.containsKey('request_id')
              // ASKED, and the staging row is gone or expired.
              ? <String, dynamic>{
                  'turns': <dynamic>[],
                  'staged': <dynamic>[],
                }
              : <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.nearby,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );
        await controller.approve();
        await controller.refresh(requestId: _requestId);

        final staged =
            container.read(aiSessionControllerProvider).stagedResults;
        // THE DISTINCTION, both legs in one group. `?? []` anywhere on
        // this path would make the previous test's null read as empty
        // and this one indistinguishable from it.
        expect(staged, isNotNull);
        expect(staged, isEmpty);
      },
    );

    test(
      'the distinction is TWO-WAY: a later read that does not ask puts '
      'stagedResults BACK to null',
      () async {
        // THE LEG A `copyWith` WITHOUT A CLEAR FLAG CANNOT DO. With
        // only `stagedResults ?? this.stagedResults`, a null response
        // would leave the PREVIOUS value in place — so once anything
        // asked, the field could never return to "I did not ask", and
        // the sheet would keep offering Publish/Discard for a staging
        // row no read has confirmed.
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (body) => body.containsKey('request_id')
              ? <String, dynamic>{
                  'turns': <dynamic>[],
                  'staged': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'request_id': _requestId,
                      'reply_text': 'Two places near you.',
                      'sources': <dynamic>[],
                      'expires_at': '2026-10-11T11:00:00.000Z',
                    },
                  ],
                }
              : <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.nearby,
          visibility: AiSessionVisibility.private,
          utcOffsetMinutes: 0,
        );
        await controller.approve();

        await controller.refresh(requestId: _requestId);
        expect(
          container.read(aiSessionControllerProvider).stagedResults,
          hasLength(1),
        );

        await controller.refresh();
        expect(
          container.read(aiSessionControllerProvider).stagedResults,
          isNull,
        );
      },
    );

    test(
      'no `?? []` appears on the staged path — and the hits are READ, '
      'not counted',
      () {
        // A bare `grep -c` is not evidence on this codebase: four times
        // in this effort a count has been inflated by a comment naming
        // exactly what the author deliberately omitted. So this reads
        // the matching LINES and asserts each is a comment.
        for (final path in <String>[
          'lib/features/ai_assistant/presentation/providers/'
              'ai_session_provider.dart',
          'lib/features/ai_assistant/presentation/screens/'
              'ai_session_sheet.dart',
        ]) {
          final lines = File(path).readAsLinesSync();
          final hits = <String>[];
          // STRENGTHENED AFTER MUTATION M4 EVADED THE FIRST VERSION.
          // That version matched the literal strings `?? []` and
          // `?? <`, and the mutation wrote `?? const []` — which is the
          // same defect and matched neither. A regex over `??` followed
          // by any amount of whitespace, an optional `const`, and
          // either `[` or `<` covers every spelling of an empty-list
          // fallback, which is what the ruling is about rather than one
          // way of typing it.
          final emptyListFallback = RegExp(r'\?\?\s*(const\s+)?[\[<]');
          for (final line in lines) {
            if (emptyListFallback.hasMatch(line)) hits.add(line.trim());
          }
          // ANTI-VACUITY: the regex really does match the idiom. Proved
          // against a literal rather than by trusting the pattern —
          // otherwise a regex that matched nothing would make this
          // whole test pass for the wrong reason, which is this
          // codebase's most frequent finding family.
          expect(
            emptyListFallback.hasMatch('final x = y ?? [];'),
            isTrue,
          );
          expect(
            emptyListFallback.hasMatch('final x = y ?? const [];'),
            isTrue,
          );
          expect(
            emptyListFallback.hasMatch('final x = y ?? <String>[];'),
            isTrue,
          );
          for (final hit in hits) {
            expect(
              hit.startsWith('//') || hit.startsWith('///'),
              isTrue,
              reason: 'RULING 9: `$hit` in $path is CODE, not a comment. '
                  'The first `?? []` on the staged path destroys the only '
                  'distinction the server deliberately draws.',
            );
          }
        }
      },
    );
  });

  // ===================================================================
  // RULING 12 — the record is destructured at its call site
  // ===================================================================

  group('RULING 12: reviewContext\'s record is destructured, not held', () {
    test(
      'the call site destructures with the FIELD NAMES, which is gate '
      '2\'s compile-time proof',
      () {
        // ACCEPTED-AS-STRUCTURAL, the way Ruling 12 itself records it:
        // the guard is enforced by the COMPILER (a third record field
        // is a compile error at a destructuring call site), and
        // loosening it to `final result = await ...` would silently
        // remove the guard without failing any runtime assertion. So
        // this test asserts the SHAPE of the call site from source,
        // because that is the only runtime evidence available for a
        // compile-time property.
        final source = File(
          'lib/features/ai_assistant/presentation/providers/'
          'ai_session_provider.dart',
        ).readAsStringSync();

        expect(
          source,
          contains('final (:review, :ticket) = await _repository.reviewContext('),
          reason: 'RULING 12: the record must be DESTRUCTURED with its field '
              'names at the call site. `final result = await ...` compiles '
              'identically today and loses the proof.',
        );
        // AND THE LOOSENED FORM IS ABSENT. This cannot be written as
        // "does not contain `= await _repository.reviewContext(`",
        // because the destructured form contains exactly that substring
        // — the first version of this assertion did, and it failed on
        // the correct implementation. So the check is that EVERY
        // `reviewContext(` call site is preceded by the destructuring
        // pattern, which is the property Ruling 12 actually asks for.
        final callSites = RegExp(
          r'[^\n]*_repository\.reviewContext\(',
        ).allMatches(source);
        expect(
          callSites,
          hasLength(1),
          reason: 'a second reviewContext call site needs its own '
              'destructuring, and this test re-pointed',
        );
        expect(
          callSites.first.group(0),
          contains('final (:review, :ticket) ='),
          reason: 'RULING 12: this call site holds the record instead of '
              'destructuring it, which loses gate 2\'s compile-time proof',
        );
      },
    );

    test(
      'the ticket never reaches the view state — only the review half '
      'does, so a widget has no digest in scope',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(includeWindow: true),
        });
        final container = _container(gateway);

        await container
            .read(aiSessionControllerProvider.notifier)
            .prepare(
              idempotencyKey: 'key',
              relationshipId: 'rel-1',
              kind: AiSessionKind.ideas,
              visibility: AiSessionVisibility.shared,
              utcOffsetMinutes: 0,
            );

        final state = container.read(aiSessionControllerProvider);
        // The review half IS visible — it is what a UI renders.
        expect(state.review, isNotNull);
        expect(state.review!.includeWindow, isTrue);
        expect(state.review!.sessionId, _sessionId);
        // The structural test above proves no digest/ticket field
        // exists at all; this is the behavioural half, confirming the
        // review half is populated without one.
      },
    );

    test(
      'setIncludeWindow(false) is a REAL WRITE and sends the key; a plain '
      'refresh OMITS it',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        await controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.shared,
          utcOffsetMinutes: 0,
        );
        // The FIRST review, from prepare: a pure read, so no toggle key.
        expect(
          gateway.bodies
              .firstWhere((b) => b['command'] == 'review_context')
              .containsKey('set_include_window'),
          isFalse,
        );

        await controller.refreshContext(utcOffsetMinutes: 0);
        // Still a pure read. `false` here would be a real write that
        // bumps the revision and clears BOTH partners' approvals — so
        // defaulting it would silently invalidate a partner on every
        // re-read.
        expect(
          gateway.bodies.last.containsKey('set_include_window'),
          isFalse,
        );

        await controller.setIncludeWindow(include: false, utcOffsetMinutes: 0);
        expect(gateway.bodies.last['set_include_window'], isFalse);
        expect(gateway.bodies.last.containsKey('set_include_window'), isTrue);
      },
    );
  });

  // ===================================================================
  // generate / publish / share
  // ===================================================================

  group('AiSessionController: generate', () {
    test(
      'an answer re-READS the transcript rather than appending locally — '
      'the server numbered the ordinals',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _ideasAnswer(
            userOrdinal: 3,
            attuneOrdinal: 4,
            sessionRevision: 11,
          ),
          'read': (_) => <String, dynamic>{
            'turns': <Map<String, dynamic>>[
              _turn(ordinal: 3, role: 'user'),
              _turn(ordinal: 4, role: 'attune'),
            ],
          },
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activate(controller);

        await controller.generate(
          requestId: _requestId,
          userInstruction: 'what should we do friday',
        );

        final state = container.read(aiSessionControllerProvider);
        expect(state.turns.map((t) => t.ordinal).toList(), <int>[3, 4]);
        // GATE 1: the revision came from the RESPONSE, which is the only
        // place this actor can read it. It was not incremented locally.
        expect(state.revision, 11);
        expect(state.redirect, isNull);
      },
    );

    test(
      'generate sends the revision the controller LAST SAW, not an '
      'argument a caller invented',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(revision: 5),
          'review_context': (_) => _reviewResponse(revision: 5),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _ideasAnswer(sessionRevision: 6),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activate(controller);

        await controller.generate(
          requestId: _requestId,
          userInstruction: 'ideas',
        );

        final generate = gateway.bodies.firstWhere(
          (b) => b['command'] == 'generate',
        );
        expect(generate['expected_revision'], 5);
        // GATE 4: no confirmation nonce anywhere. None exists to send.
        expect(generate.containsKey('confirmation_nonce'), isFalse);
      },
    );

    test(
      'a REPLAY sends no session_revision, and null means "this response '
      'carried none" rather than zero',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(revision: 5),
          'review_context': (_) => _reviewResponse(revision: 5),
          'approve': (_) => _approveResponse(activated: true),
          // `replayAdmittedRequest` — NO `kind` key at all, and no
          // `session_revision`.
          'generate': (_) => <String, dynamic>{
            'user_ordinal': 1,
            'attune_ordinal': 2,
            'reply_text': 'A few ideas for Friday.',
            'suggested_planning_item': null,
            'replayed': true,
          },
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activate(controller);

        await controller.generate(
          requestId: _requestId,
          userInstruction: 'ideas',
        );

        // The LAST KNOWN revision stands. Gate 1: there is nothing to
        // fall back to, so a controller that wrote `?? 0` here would
        // then send 0 as `expected_revision` and get CONTEXT_CHANGED
        // forever.
        expect(container.read(aiSessionControllerProvider).revision, 5);
        expect(
          container.read(aiSessionControllerProvider).revision,
          isNot(0),
        );
      },
    );

    test(
      'a staged Nearby generation does NOT re-read the transcript — '
      'nothing is committed and the partner can see nothing',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(kind: 'nearby'),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _stagedNearby(),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activate(controller);
        final readsBefore =
            gateway.bodies.where((b) => b['command'] == 'read').length;

        await controller.generate(
          requestId: _requestId,
          userInstruction: 'coffee',
          requesterLocation: (latitude: 5.6, longitude: -0.2, accuracyM: 30),
          locationCapturedAt: DateTime.utc(2026, 10, 11, 10),
        );

        final state = container.read(aiSessionControllerProvider);
        expect(state.pendingStage, isNotNull);
        expect(state.pendingStage!.requestId, _requestId);
        expect(state.pendingStage!.sources, hasLength(1));
        // NO new read: re-reading would show the requester their own
        // staged content as though it were in the transcript, which it
        // is not until publishNearby.
        expect(
          gateway.bodies.where((b) => b['command'] == 'read').length,
          readsBefore,
        );
        expect(state.turns, isEmpty);
      },
    );

    test(
      'the location is sent with captured_at in UTC — a local-time '
      'string would be read as the wrong moment',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(kind: 'nearby'),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _stagedNearby(),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activate(controller);

        await controller.generate(
          requestId: _requestId,
          userInstruction: 'coffee',
          requesterLocation: (latitude: 5.6, longitude: -0.2, accuracyM: 30),
          locationCapturedAt: DateTime.utc(2026, 10, 11, 10),
        );

        final location =
            (gateway.bodies.firstWhere((b) => b['command'] == 'generate')
                    ['requester_location'] as Map)
                .cast<String, Object?>();
        // §4.1's freshness window is TWO MINUTES, measured server-side
        // against this. A string with no offset is read as the SERVER's
        // local time — wrong by the device's offset, which "would have
        // passed in Accra and failed across most of the world".
        expect(location['captured_at'], endsWith('Z'));
        expect(location['captured_at'], '2026-10-11T10:00:00.000Z');
        expect(location.containsKey('confirmation_nonce'), isFalse);
      },
    );
  });

  group('AiSessionController: publish and share', () {
    test(
      'RULING 15: a publish-time redirect lands in the SAME redirect '
      'slot and KEEPS the staged result — nothing was committed',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(revision: 2),
          'review_context': (_) => _reviewResponse(revision: 2, kind: 'nearby'),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _stagedNearby(),
          'publish_nearby': (_) => _safetyRefusal(),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activate(controller);
        await controller.generate(
          requestId: _requestId,
          userInstruction: 'coffee',
          requesterLocation: (latitude: 5.6, longitude: -0.2, accuracyM: 30),
          locationCapturedAt: DateTime.utc(2026, 10, 11, 10),
        );

        await controller.publishStaged(_requestId);

        final state = container.read(aiSessionControllerProvider);
        // ONE slot for both commands' redirects. A `publishRedirect`
        // field beside `redirect` would be `wasBlockedBySafety` by
        // another name, because a publish-path redirect is ALWAYS a
        // safety refusal.
        expect(state.redirect, isNotNull);
        expect(state.redirect!.runtimeType, AiSessionGeneratedRedirect);
        // The staged row is UNTOUCHED server-side, so it is kept here:
        // the requester may still discard it.
        expect(state.pendingStage, isNotNull);
        // The revision did NOT move, so there is nothing for a partner
        // to poll and notice.
        expect(state.revision, 2);
        expect(state.error, isNull);
      },
    );

    test(
      'a successful publish clears the staged result and reads the pair',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(revision: 2),
          'review_context': (_) => _reviewResponse(revision: 2, kind: 'nearby'),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _stagedNearby(),
          'publish_nearby': (_) => <String, dynamic>{
            'committed': true,
            'user_ordinal': 3,
            'attune_ordinal': 4,
            'session_revision': 7,
          },
          'read': (_) => <String, dynamic>{
            'turns': <Map<String, dynamic>>[
              _turn(
                ordinal: 3,
                role: 'user',
                kind: 'nearby_result',
                payload: <String, dynamic>{'instruction': 'nearby'},
              ),
              _turn(
                ordinal: 4,
                role: 'attune',
                kind: 'nearby_result',
                payload: <String, dynamic>{
                  'reply_text': 'Two places near you.',
                  'sources': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'provider_id': 'place-1',
                      'name': 'The Corner Cafe',
                      'formatted_address': '12 Main St',
                    },
                  ],
                },
              ),
            ],
          },
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activate(controller);
        await controller.generate(
          requestId: _requestId,
          userInstruction: 'coffee',
          requesterLocation: (latitude: 5.6, longitude: -0.2, accuracyM: 30),
          locationCapturedAt: DateTime.utc(2026, 10, 11, 10),
        );

        await controller.publishStaged(_requestId);

        final state = container.read(aiSessionControllerProvider);
        expect(state.pendingStage, isNull);
        expect(state.redirect, isNull);
        expect(state.revision, 7);
        expect(state.turns, hasLength(2));
        // ROLE AND KIND ARE ORTHOGONAL: the USER row of a Nearby pair
        // is `kind: 'nearby_result'`, so a renderer keying the user
        // branch off `ideas_answer` could not read this at all.
        expect(state.turns.first, isA<AiSessionUserTurn>());
        expect(state.turns.first.kind, AiSessionTurnKind.nearbyResult);
        expect(state.turns.last, isA<AiSessionNearbyResultTurn>());
      },
    );

    test(
      'shareAnswer passes the SERVER\'s ordinal through unchanged',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{
            'turns': <Map<String, dynamic>>[
              _turn(ordinal: 3, role: 'user'),
              _turn(ordinal: 4, role: 'attune'),
            ],
          },
          'share_answer': (_) => <String, dynamic>{'message_id': _messageId},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activate(controller);

        final messageId = await controller.shareAnswer(4);

        expect(messageId, _messageId);
        final share = gateway.bodies.firstWhere(
          (b) => b['command'] == 'share_answer',
        );
        // FOUR, the server's own number — not 2, which is what
        // renumbering a two-element rendered list to 1..n would send,
        // and which would share the WRONG turn.
        expect(share['ordinal'], 4);
        expect(share['ordinal'], isNot(2));
      },
    );

    test(
      'discardStaged clears the stage; it is terminal and COUNTED, never '
      'a free undo',
      () async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(kind: 'nearby'),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _stagedNearby(),
          'discard_nearby': (_) => <String, dynamic>{'discarded': true},
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activate(controller);
        await controller.generate(
          requestId: _requestId,
          userInstruction: 'coffee',
          requesterLocation: (latitude: 5.6, longitude: -0.2, accuracyM: 30),
          locationCapturedAt: DateTime.utc(2026, 10, 11, 10),
        );

        await controller.discardStaged(_requestId);

        expect(
          container.read(aiSessionControllerProvider).pendingStage,
          isNull,
        );
        final discard = gateway.bodies.firstWhere(
          (b) => b['command'] == 'discard_nearby',
        );
        expect(discard.keys.toSet(), {'command', 'request_id'});
      },
    );
  });

  // ===================================================================
  // AiSessionSheet — the widget
  // ===================================================================

  group('AiSessionSheet: preparation', () {
    testWidgets('offers the kind and visibility choice, then Start', (
      tester,
    ) async {
      final gateway = _FakeSessionGateway({
        'prepare': (_) => _prepareResponse(),
        'review_context': (_) => _reviewResponse(),
      });
      await _pumpSheet(tester, gateway);

      // Scoped to the CHOICE CHIPS, because the AppBar title renders the
      // same kind label — a bare `find.text(kAiSessionIdeasLabel)` finds
      // two and the assertion would be about the wrong widget.
      Finder chip(String label) => find.descendant(
        of: find.byType(ChoiceChip),
        matching: find.text(label),
      );
      expect(chip(kAiSessionIdeasLabel), findsOneWidget);
      expect(chip(kAiSessionNearbyLabel), findsOneWidget);
      expect(chip(kAiSessionPrivateLabel), findsOneWidget);
      expect(chip(kAiSessionSharedLabel), findsOneWidget);
      expect(find.text(kAiSessionStartLabel), findsOneWidget);
      // Nothing was requested on mount.
      expect(gateway.bodies, isEmpty);
    });

    testWidgets(
      'the capability is read through the SERVICE, and a disabled kind is '
      'not offered',
      (tester) async {
        final gateway = _FakeSessionGateway({});
        await _pumpSheet(
          tester,
          gateway,
          // Nearby OFF, private ON. §12's subcapability independence:
          // a UI must never infer one capability from another.
          capabilities: const AiSessionCapabilities(
            assist: true,
            sessionsPrivate: true,
            sessionsShared: false,
            sessionsRecentWindow: false,
            sessionsNearby: false,
          ),
        );

        Finder chip(String label) => find.descendant(
          of: find.byType(ChoiceChip),
          matching: find.text(label),
        );
        expect(chip(kAiSessionIdeasLabel), findsOneWidget);
        // Nearby's flag is OFF, so the chip is not drawn at all — and
        // §12's subcapability independence means Ideas being on says
        // nothing about Nearby.
        expect(chip(kAiSessionNearbyLabel), findsNothing);
        expect(chip(kAiSessionPrivateLabel), findsOneWidget);
        expect(chip(kAiSessionSharedLabel), findsNothing);
      },
    );

    testWidgets(
      'with EVERY capability off the sheet offers nothing to start — the '
      'flags are OFF everywhere today, so this is the live behaviour',
      (tester) async {
        final gateway = _FakeSessionGateway({});
        await _pumpSheet(
          tester,
          gateway,
          capabilities: AiSessionCapabilities.unavailable,
        );

        expect(find.text(kAiSessionStartLabel), findsNothing);
        expect(find.text(kAiSessionUnavailableMessage), findsOneWidget);
        expect(gateway.bodies, isEmpty);
      },
    );

    testWidgets('Start prepares, reviews, then shows the approval step', (
      tester,
    ) async {
      final gateway = _FakeSessionGateway({
        'prepare': (_) => _prepareResponse(),
        'review_context': (_) => _reviewResponse(
          visibility: 'shared',
          includeWindow: true,
          window: <Map<String, dynamic>>[
            <String, dynamic>{
              'content': 'are you free friday',
              'truncated': true,
            },
          ],
        ),
      });
      await _pumpSheet(tester, gateway);

      await tester.tap(find.text(kAiSessionSharedLabel));
      await tester.pump();
      await tester.tap(find.text(kAiSessionStartLabel));
      await tester.pumpAndSettle();

      expect(find.text(kAiSessionApproveLabel), findsOneWidget);
      expect(find.text('are you free friday'), findsOneWidget);
      // `truncated` is SHOWN rather than implied: `selectSharedWindow`
      // clips against a 2,400-scalar TOTAL budget across the window, so
      // whether a given message was clipped depends on the others.
      expect(find.text(kAiSessionTruncatedLabel), findsOneWidget);
    });

    testWidgets(
      'a shared session\'s first approver sees "waiting for your partner" '
      'with a refresh, not an error',
      (tester) async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(visibility: 'shared'),
          'approve': (_) => _approveResponse(activated: false),
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionSharedLabel));
        await tester.pump();
        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kAiSessionApproveLabel));
        await tester.pumpAndSettle();

        expect(find.text(kAiSessionWaitingForPartnerMessage), findsOneWidget);
        // NOT an error surface.
        expect(find.byIcon(Icons.error_outline), findsNothing);
        // A MANUAL refresh, because gate 1 means the partner cannot
        // read a revision move — Task 8 owns the polling problem, and
        // nothing here assumes a partner sees one.
        expect(find.text(kAiSessionRefreshLabel), findsOneWidget);
      },
    );

    testWidgets(
      'a CONTEXT_CHANGED offers RE-REVIEW, never a retry of the same '
      'approval',
      (tester) async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => throw _functionError('CONTEXT_CHANGED', 409),
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kAiSessionApproveLabel));
        await tester.pumpAndSettle();

        expect(find.text(kAiSessionContextChangedMessage), findsOneWidget);
        // The remedy is to RE-REVIEW. A client cannot recompute the
        // digest (gate 2), so there is no local path back to a valid
        // approval and a "Retry" would resend a digest the server has
        // already rejected.
        expect(find.text(kAiSessionReReviewLabel), findsOneWidget);
        expect(find.text(kAiSessionRetryLabel), findsNothing);
      },
    );
  });

  group('AiSessionSheet: the live transcript', () {
    testWidgets(
      'a user turn, an ideas answer and its Share action render; the '
      'answer carries the SERVER\'s ordinal',
      (tester) async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{
            'turns': <Map<String, dynamic>>[
              _turn(ordinal: 3, role: 'user'),
              _turn(ordinal: 4, role: 'attune'),
            ],
          },
          'share_answer': (_) => <String, dynamic>{'message_id': _messageId},
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kAiSessionApproveLabel));
        await tester.pumpAndSettle();

        expect(find.text('what should we do friday'), findsOneWidget);
        expect(find.text('A few ideas for Friday.'), findsOneWidget);

        await tester.tap(find.text(kAiSessionShareLabel));
        await tester.pumpAndSettle();

        final share = gateway.bodies.firstWhere(
          (b) => b['command'] == 'share_answer',
        );
        // FOUR. Renumbering the rendered list would send 2.
        expect(share['ordinal'], 4);
      },
    );

    testWidgets(
      'an empty transcript renders as EMPTY, never as "this session has '
      'ended"',
      (tester) async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kAiSessionApproveLabel));
        await tester.pumpAndSettle();

        expect(find.text(kAiSessionEmptyTranscriptMessage), findsOneWidget);
        // §7.2: `read` returns 200-with-empty-array for a stranger, a
        // non-approver AND a healthy session with no committed turn.
        // Rendering "ended" would turn silence into a verdict.
        expect(find.text(kAiSessionEndedMessage), findsNothing);
        // And the instruction field is still live.
        expect(find.byType(TextField), findsOneWidget);
      },
    );

    testWidgets(
      'the instruction field submits through generate and the new turn '
      'appears',
      (tester) async {
        var reads = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _ideasAnswer(),
          'read': (_) {
            reads++;
            return reads == 1
                ? <String, dynamic>{'turns': <dynamic>[]}
                : <String, dynamic>{
                    'turns': <Map<String, dynamic>>[
                      _turn(ordinal: 1, role: 'user'),
                      _turn(ordinal: 2, role: 'attune'),
                    ],
                  };
          },
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kAiSessionApproveLabel));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'ideas for friday');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        final generate = gateway.bodies.firstWhere(
          (b) => b['command'] == 'generate',
        );
        expect(generate['user_instruction'], 'ideas for friday');
        expect(find.text('A few ideas for Friday.'), findsOneWidget);
      },
    );

    testWidgets(
      'a Nearby result renders its SOURCE CARDS with name and address',
      (tester) async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(kind: 'nearby'),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{
            'turns': <Map<String, dynamic>>[
              _turn(
                ordinal: 1,
                role: 'user',
                kind: 'nearby_result',
                payload: <String, dynamic>{'instruction': 'nearby'},
              ),
              _turn(
                ordinal: 2,
                role: 'attune',
                kind: 'nearby_result',
                payload: <String, dynamic>{
                  'reply_text': 'Two places near you.',
                  'sources': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'provider_id': 'place-1',
                      'name': 'The Corner Cafe',
                      'formatted_address': '12 Main St',
                    },
                  ],
                },
              ),
            ],
          },
        });
        await _pumpSheet(tester, gateway, kind: AiSessionKind.nearby);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kAiSessionApproveLabel));
        await tester.pumpAndSettle();

        expect(find.text('Two places near you.'), findsOneWidget);
        expect(find.text('The Corner Cafe'), findsOneWidget);
        expect(find.text('12 Main St'), findsOneWidget);
        // GATE 4: no confirmation control is presented. The Nearby
        // `confirmation_nonce` is decorative — no issuing RPC, column
        // or table — so a "confirmed" badge would claim a control the
        // server never issued.
        expect(find.text('Confirmed'), findsNothing);
      },
    );
  });

  // ===================================================================
  // RULING 6 — THE TWO REDIRECT SHAPES RENDER IDENTICALLY
  // ===================================================================

  group('RULING 6: the two redirect shapes are indistinguishable ON SCREEN', () {
    /// Renders a session whose `generate` answers with [response], and
    /// returns a description of the resulting widget tree.
    ///
    /// The description is what the comparison is made on, so it has to
    /// capture everything a watcher could see: the widget TYPES, the
    /// ICONS, the layout (alignment, padding, decoration colour) and the
    /// text. The server's own `copy` is the ONE thing excluded — it is
    /// §5.3's verbatim string, so the two shapes legitimately show
    /// different words, and the whole point of Ruling 6 is that nothing
    /// ELSE may differ. Including it would make the comparison trivially
    /// fail and prove nothing.
    Future<List<String>> renderRedirect(
      WidgetTester tester,
      Map<String, dynamic> response, {
      String command = 'generate',
    }) async {
      final gateway = _FakeSessionGateway({
        'prepare': (_) => _prepareResponse(),
        'review_context': (_) => _reviewResponse(kind: 'nearby'),
        'approve': (_) => _approveResponse(activated: true),
        'generate': (_) =>
            command == 'generate' ? response : _stagedNearby(),
        'publish_nearby': (_) => response,
        'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
      });
      await _pumpSheet(tester, gateway, kind: AiSessionKind.nearby);
      await tester.tap(find.text(kAiSessionStartLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kAiSessionApproveLabel));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'an instruction');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      if (command == 'publish_nearby') {
        await tester.tap(find.text(kAiSessionPublishLabel));
        await tester.pumpAndSettle();
      }

      final notice = find.byType(AiSessionRedirectNotice);
      expect(
        notice,
        findsOneWidget,
        reason: 'the redirect must render through ONE widget for both '
            'shapes and both commands',
      );

      // Every descendant, described structurally. `Text` widgets
      // contribute their TYPE but not their string, except for the
      // generic/structural labels, so the server's verbatim copy does
      // not make two identical trees look different.
      final descriptions = <String>[];
      for (final element in find
          .descendant(of: notice, matching: find.byWidgetPredicate((_) => true))
          .evaluate()) {
        final widget = element.widget;
        final parts = <String>[widget.runtimeType.toString()];
        if (widget is Icon) {
          parts.add('icon=${widget.icon?.codePoint}');
          parts.add('iconColor=${widget.color}');
          parts.add('iconSize=${widget.size}');
        }
        if (widget is Container) {
          parts.add('decoration=${widget.decoration}');
          parts.add('padding=${widget.padding}');
        }
        if (widget is Padding) parts.add('padding=${widget.padding}');
        if (widget is Align) parts.add('alignment=${widget.alignment}');
        if (widget is Column) {
          parts.add('cross=${widget.crossAxisAlignment}');
          parts.add('main=${widget.mainAxisAlignment}');
        }
        if (widget is Row) {
          parts.add('cross=${widget.crossAxisAlignment}');
          parts.add('main=${widget.mainAxisAlignment}');
        }
        if (widget is Text) {
          parts.add('style=${widget.style}');
          parts.add('align=${widget.textAlign}');
        }
        if (widget is DecoratedBox) parts.add('decoration=${widget.decoration}');
        descriptions.add(parts.join('|'));
      }
      return descriptions;
    }

    testWidgets(
      'THE CORE PROOF: a SAFETY REFUSAL and an ORDINARY REDIRECT produce '
      'the SAME widget tree — same types, same icons, same layout',
      (tester) async {
        // Same reason on both, and `offered: []` on BOTH — which an
        // ordinary redirect may legally send
        // (`validateSessionTurnOutput` accepts an empty array) — so any
        // residual difference must come from the ONE field that
        // genuinely differs on the wire: `copy`.
        final refusalTree = await renderRedirect(
          tester,
          _safetyRefusal(reason: 'unsupported'),
        );
        final ordinaryTree = await renderRedirect(
          tester,
          _ordinaryRedirect(reason: 'unsupported'),
        );

        // Anti-vacuity: the description really captured a tree.
        expect(refusalTree, isNotEmpty);
        expect(refusalTree.length, greaterThan(3));
        expect(refusalTree.join(), contains('Icon'));
        expect(refusalTree.join(), contains('Text'));

        // THE ASSERTION. A different icon, a different alignment, a
        // different container colour, an extra badge, a changed text
        // style — any of them is a VISIBLE ORACLE to anyone watching
        // the screen, which is the disclosure §8.1 forbids and which no
        // model-level test can catch.
        expect(
          ordinaryTree,
          refusalTree,
          reason: 'RULING 6: the two redirect shapes rendered DIFFERENT '
              'widget trees. A safety refusal and an ordinary redirect '
              'share the kind AND the reason set deliberately; a '
              'layout/icon difference reconstructs the fact that a '
              'detector fired, to anyone looking at the screen.',
        );
      },
    );

    testWidgets(
      'the REFUSAL shape and an ordinary redirect WITH offered entries '
      'differ ONLY by the entries themselves — no icon, container or '
      'layout difference rides along',
      (tester) async {
        // ADDED BECAUSE MUTATION M1 SURVIVED THIS GROUP'S CORE PROOF.
        // That proof holds `offered: []` on BOTH fixtures in order to
        // isolate `copy`, which means an `offered.isEmpty ? shieldIcon :
        // infoIcon` mutation produced the SAME icon on both and the
        // comparison passed. Only the structural test killed it.
        //
        // So this test crosses the other way: a refusal (always `[]`)
        // against an ordinary redirect WITH entries — the realistic
        // pair, and the one where an emptiness branch becomes visible.
        // The comparison therefore excludes the entry labels themselves
        // (they legitimately differ) and asserts everything STRUCTURAL
        // around them is identical.
        final refusalTree = await renderRedirect(
          tester,
          _safetyRefusal(reason: 'unsupported'),
        );
        final offeringTree = await renderRedirect(
          tester,
          _ordinaryRedirect(
            reason: 'unsupported',
            offered: const <String>['ideas', 'nearby'],
          ),
        );

        // The offering tree has MORE nodes — two entry labels — so the
        // trees are not equal, and asserting equality would be wrong.
        expect(offeringTree.length, greaterThan(refusalTree.length));

        // THE ASSERTION: every node type the refusal draws, the
        // offering draws too, and the ICON nodes are identical. An
        // `offered.isEmpty` branch on the icon, the container colour or
        // the padding would break one of these even though the trees
        // legitimately differ in length.
        String iconsOf(List<String> tree) => tree
            .where((node) => node.startsWith('Icon|'))
            .join(';');
        expect(iconsOf(refusalTree), isNotEmpty);
        expect(
          iconsOf(offeringTree),
          iconsOf(refusalTree),
          reason: 'RULING 6: the icon differs between a refusal (which '
              'always sends `offered: []`) and an ordinary redirect with '
              'entries. `offered.isEmpty` is a strong detector oracle even '
              'though an ordinary redirect may legally send [] too.',
        );
        String containersOf(List<String> tree) => tree
            .where((node) => node.startsWith('Container|'))
            .join(';');
        expect(containersOf(refusalTree), isNotEmpty);
        expect(
          containersOf(offeringTree),
          containersOf(refusalTree),
          reason: 'RULING 6: the notice container differs between the two '
              'shapes, which is visible to anyone looking at the screen.',
        );
      },
    );

    testWidgets(
      'RULING 15 x RULING 6: a PUBLISH-time refusal renders the SAME tree '
      'as a generate redirect',
      (tester) async {
        final generateTree = await renderRedirect(
          tester,
          _safetyRefusal(reason: 'unsupported'),
        );
        final publishTree = await renderRedirect(
          tester,
          _safetyRefusal(reason: 'unsupported'),
          command: 'publish_nearby',
        );

        expect(publishTree, isNotEmpty);
        // A publish-path redirect is ALWAYS a safety refusal, so a
        // publish-SPECIFIC notice would announce "a detector fired"
        // outright. Rendering through the same widget is what stops
        // that, and is why the controller has one redirect slot.
        expect(
          publishTree,
          generateTree,
          reason: 'RULING 15 x RULING 6: the publish-time refusal rendered '
              'a different tree from a generate redirect. On the publish '
              'path a redirect is always a refusal, so a publish-specific '
              'notice IS the detector signal.',
        );
      },
    );

    testWidgets(
      'the server\'s copy is shown VERBATIM when present and the generic '
      'copy otherwise — resolved WITHOUT asking which arrived',
      (tester) async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _safetyRefusal(),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        await _pumpSheet(tester, gateway);
        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kAiSessionApproveLabel));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'probing instruction');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        // §5.3: "server-rendered fixed copy from allowlisted reason",
        // shown verbatim. Nothing is interpolated into it.
        expect(
          find.text(
            'I am not able to help with this. Support resources are '
            'available if you want them.',
          ),
          findsOneWidget,
        );
        expect(find.text(kAiSessionGenericRedirectCopy), findsNothing);
      },
    );

    testWidgets('an ORDINARY redirect shows the GENERIC copy', (tester) async {
      final gateway = _FakeSessionGateway({
        'prepare': (_) => _prepareResponse(),
        'review_context': (_) => _reviewResponse(),
        'approve': (_) => _approveResponse(activated: true),
        'generate': (_) => _ordinaryRedirect(),
        'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
      });
      await _pumpSheet(tester, gateway);
      await tester.tap(find.text(kAiSessionStartLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kAiSessionApproveLabel));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'news today');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text(kAiSessionGenericRedirectCopy), findsOneWidget);
    });

    testWidgets(
      'a redirect is a NEUTRAL INLINE NOTICE, never an Attune bubble — §1 '
      '"not a conversational AI persona"',
      (tester) async {
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'generate': (_) => _ordinaryRedirect(),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        });
        await _pumpSheet(tester, gateway);
        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kAiSessionApproveLabel));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'news today');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        expect(find.byType(AiSessionRedirectNotice), findsOneWidget);
        // Not styled as if Attune "said" something conversational, and
        // specifically not a transcript turn — §5.3 was amended so NO
        // redirect becomes a transcript pair, precisely because a
        // durable redirect is a safety side channel.
        expect(find.byType(AiSessionAttuneBubble), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AiSessionRedirectNotice),
            matching: find.byType(AiSessionAttuneBubble),
          ),
          findsNothing,
        );
      },
    );

    test(
      'the redirect notice reads the SOURCE and has no shape-dependent '
      'branch — proved from the declarations',
      () {
        // Structural, for the Task 4 M1b reason: a behavioural
        // comparison of two rendered trees is strong but it can only
        // catch a difference the FIXTURES exercise. This catches the
        // forbidden branch whatever its shape and whether or not a test
        // exercises it.
        final source = File(
          'lib/features/ai_assistant/presentation/screens/'
          'ai_session_sheet.dart',
        ).readAsStringSync();

        const declaration = 'class AiSessionRedirectNotice';
        final start = source.indexOf(declaration);
        expect(
          start,
          isNonNegative,
          reason: 'AiSessionRedirectNotice moved or was renamed',
        );
        final nextTopLevel = source.indexOf('\nclass ', start + 1);
        expect(nextTopLevel, isNonNegative);
        final body = source.substring(start, nextTopLevel);
        // Anti-vacuity.
        expect(body, contains('resolveCopy'));
        expect(body.length, lessThan(source.length));

        final stripped = body
            .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
            .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
            .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
        // THE STRIPPER WORKS, proved on a phrase that appears in this
        // widget's body ONLY inside a comment. The probe is chosen from
        // INSIDE the slice: an earlier version used a phrase from the
        // class's leading doc comment, which the slice (starting at
        // `class`) does not contain, so the `contains` failed outright
        // — right verdict for the wrong reason.
        expect(
          body,
          contains('the proxy'),
          reason: 'the probe should be present BEFORE stripping',
        );
        expect(
          stripped,
          isNot(contains('the proxy')),
          reason: 'comment stripping failed, so the assertions below would '
              'be reading prose as code',
        );

        // NO shape-dependent branch of any spelling. `copy` is private
        // on the model so `copy != null` cannot even compile, but
        // `offered.isEmpty` CAN, and it is a strong oracle: a refusal
        // always sends `[]`.
        expect(stripped, isNot(contains('offered.isEmpty')));
        expect(stripped, isNot(contains('offered.isNotEmpty')));
        expect(stripped, isNot(contains('isSafetyRefusal')));
        expect(stripped, isNot(contains('wasBlocked')));
        // `resolveCopy` is reached with the generic copy REQUIRED, so
        // the call site cannot discover the server's string by
        // comparing against a known default.
        expect(stripped, contains('genericRedirectCopy:'));
      },
    );
  });

  group('AiSessionSheet: end', () {
    testWidgets('End ends the session and shows the terminal state', (
      tester,
    ) async {
      final gateway = _FakeSessionGateway({
        'prepare': (_) => _prepareResponse(),
        'review_context': (_) => _reviewResponse(),
        'approve': (_) => _approveResponse(activated: true),
        'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
        'end': (_) => <String, dynamic>{'ended': true},
      });
      await _pumpSheet(tester, gateway);
      await tester.tap(find.text(kAiSessionStartLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kAiSessionApproveLabel));
      await tester.pumpAndSettle();

      await tester.tap(find.text(kAiSessionEndLabel));
      await tester.pumpAndSettle();

      expect(find.text(kAiSessionEndedMessage), findsOneWidget);
      final end = gateway.bodies.firstWhere((b) => b['command'] == 'end');
      expect(end.keys.toSet(), {'command', 'session_id'});
      // §5.4 forbids disclosing WHO ended a session, and nothing here
      // could: the body has no actor field.
      expect(end.containsKey('actor_id'), isFalse);
    });
  });

  group('AiSessionSheet: errors are branched on the CODE, not the status', () {
    testWidgets(
      'five codes share HTTP 409 and produce five DISTINCT messages',
      (tester) async {
        // Any mapper that read the status would show one message for
        // all five.
        const codesAt409 = <String>[
          'CONTEXT_CHANGED',
          'SESSION_BUSY',
          'REQUEST_CONFLICT',
          'SESSION_LIMIT_REACHED',
          'APPROVAL_REQUIRED',
        ];
        final messages = <String>{};
        for (final code in codesAt409) {
          final gateway = _FakeSessionGateway({
            'prepare': (_) => throw _functionError(code, 409),
          });
          await _pumpSheet(tester, gateway);
          await tester.tap(find.text(kAiSessionStartLabel));
          await tester.pumpAndSettle();

          final notice = find.byType(AiSessionErrorNotice);
          expect(notice, findsOneWidget, reason: '$code showed no notice');
          messages.add(
            (find
                        .descendant(of: notice, matching: find.byType(Text))
                        .evaluate()
                        .first
                        .widget
                    as Text)
                .data!,
          );
        }
        // FIVE distinct messages from five codes at one status.
        expect(messages, hasLength(5));
      },
    );
  });

  // ===================================================================
  // THE POLL (spec §6.1 as amended, §6.2, §7.2) — Task 8
  //
  // ## THE BRIEF'S MECHANISM WAS SUPERSEDED, NOT MERELY MIS-SPELLED
  //
  // Task 8's brief specified a Realtime Broadcast subscription on an
  // `ai_session_hint:<user id>` private channel, and its Step 1 sample
  // called `.channel(..., opts: RealtimeChannelConfig(private: true))
  // .onBroadcast(...)`. **That channel does not exist and will never be
  // built.** Plan C's Task 6 never created it, and the §6.1 decision was
  // ruled the other way: polling `session_revision` IS the sanctioned
  // invalidation mechanism, Realtime Broadcast is explicitly out of
  // scope, and direct Postgres Changes publication of the transcript,
  // staging and source tables remains forbidden.
  //
  // Re-verified against the database rather than taken on trust: the
  // `realtime` schema holds ZERO policies of this database's 158, so
  // `private: true` would be asking the server to authorize against an
  // empty policy set. The client's own usage agrees from the other side
  // — 14 `.onPostgresChanges` call sites against 2 `.onBroadcast`,
  // neither of the latter in an AI surface. So there is no fake channel
  // to build here, because there is no channel.
  //
  // ## WHAT THESE TESTS PROVE
  //
  //  - the poll's CADENCE and LIFECYCLE: when it starts, that it fires
  //    on the interval, that ticks do not overlap, and that four
  //    different things stop it;
  //  - RULING 6: the polled value does NOT move across a safety
  //    refusal, with a precondition proving the refusal happened;
  //  - RULING 9: `staged`'s null-vs-empty distinction survives a
  //    poll-driven refresh, which is exactly where a refresh loses it;
  //  - §7.2: silence is not evidence the session is gone.
  // ===================================================================
  group('Task 8: the poll — cadence and lifecycle', () {
    testWidgets(
      'the poll does NOT start before there is a session, fires once '
      'per 5 seconds once armed, and stops on stopPolling',
      (tester) async {
        var reads = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
          'read_state': (_) {
            reads++;
            return _readStateResponse(revision: 1, state: 'active');
          },
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );

        // BEFORE a session exists, arming is refused — there is nothing
        // to poll and a tick would have no session id to send.
        controller.startPolling();
        expect(
          controller.isPolling,
          isFalse,
          reason: 'the poll must not arm before prepare() reported a '
              'session id — a tick would have nothing to ask about',
        );

        await _activateUnderFakeAsync(tester, controller);
        controller.startPolling();
        expect(controller.isPolling, isTrue);

        // Not yet fired: `Timer.periodic` fires AFTER the first
        // interval, so arming alone must cost no round trip.
        expect(
          reads,
          0,
          reason: 'arming the poll must not itself issue a read_state',
        );

        // SPECIFIC CADENCE, not merely "it fires". The sub-interval leg
        // comes FIRST, while the clock is still at a known offset from
        // the arm: four seconds is less than one interval and must
        // produce NOTHING. Without this leg a one-second poll would pass
        // every other assertion here.
        //
        // Each settle pump below advances the fake clock by 100ms (the
        // tick's own round trip sits behind the fake gateway's 5ms
        // delay, so a zero-duration pump cannot settle it), which is why
        // the budget is tracked rather than assumed: 4s + 0.1s is still
        // inside the first 5s interval.
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          reads,
          0,
          reason: 'a sub-interval pump must not tick — the cadence is '
              '5 seconds, and a faster poll is a different contract',
        );

        // Crossing the first boundary: 4.1s + 1s = 5.1s.
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 100));
        expect(reads, 1, reason: 'exactly one tick after one interval');

        // And the next: 5.2s + 5s = 10.2s, one further boundary only.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        expect(reads, 2, reason: 'one tick per interval, not a burst');

        controller.stopPolling();
        expect(controller.isPolling, isFalse);
        await tester.pump(const Duration(seconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          reads,
          2,
          reason: 'STOP 1: stopPolling must really cancel the timer, not '
              'merely flip a flag the tick ignores',
        );
      },
    );

    testWidgets(
      'ticks do not overlap: a slow round trip is not joined by a '
      'second request on the next interval',
      (tester) async {
        var inFlight = 0;
        var maxConcurrent = 0;
        final gateway = _SlowStateGateway(
          onReadState: () {
            inFlight++;
            maxConcurrent =
                inFlight > maxConcurrent ? inFlight : maxConcurrent;
          },
          onReadStateDone: () => inFlight--,
        );
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activateUnderFakeAsync(tester, controller);
        controller.startPolling();

        // The fake holds read_state for 12 seconds — longer than two
        // intervals — so an overlapping implementation would have two or
        // three requests open at once.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          maxConcurrent,
          1,
          reason: 'two concurrent read_state calls can apply out of '
              'order, so a later tick could overwrite a newer revision '
              'with an older one',
        );

        controller.stopPolling();
        await tester.pump(const Duration(seconds: 30));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'STOP 3: an explicit `closed` ends the session and stops the '
      'poll — and it is the ONLY thing that concludes ending',
      (tester) async {
        var reads = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
          'read_state': (_) {
            reads++;
            return _readStateResponse(revision: 9, state: 'closed');
          },
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activateUnderFakeAsync(tester, controller);
        controller.startPolling();

        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          container.read(aiSessionControllerProvider).phase,
          AiSessionPhase.ended,
          reason: 'an EXPLICIT closed is how a partner learns the '
              'session ended — end_ai_session bumps the revision in the '
              'same statement precisely so a poller can observe it',
        );
        expect(
          controller.isPolling,
          isFalse,
          reason: 'a closed session is terminal: its revision cannot '
              'move again, so polling on is pure waste',
        );

        final after = reads;
        await tester.pump(const Duration(seconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
        expect(reads, after, reason: 'no ticks after closed');
      },
    );

    testWidgets(
      '§7.2 SILENCE IS NOT EVIDENCE: a null snapshot leaves the phase '
      'alone, sets no error, and keeps polling',
      (tester) async {
        var reads = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
          // The SILENT answer: the RPC returned zero rows. Produced by
          // an unknown session, a non-member, withdrawn consent, an
          // expiry AND a never-approved shared session —
          // byte-identically, which is why none of them may be inferred.
          'read_state': (_) {
            reads++;
            return _readStateResponse(revision: null, state: null);
          },
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activateUnderFakeAsync(tester, controller);
        controller.startPolling();

        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));

        final state = container.read(aiSessionControllerProvider);
        expect(
          state.phase,
          AiSessionPhase.active,
          reason: 'silence must NOT be read as "ended" — a stranger, a '
              'withdrawal and an expiry all produce the identical empty '
              'answer, so concluding anything from it is a guess',
        );
        expect(
          state.error,
          isNull,
          reason: 'a silent poll is not an error to show the user',
        );
        expect(
          controller.isPolling,
          isTrue,
          reason: 'silence must not stop the poll — only an explicit '
              'closed does',
        );
        expect(reads, 2, reason: 'it kept polling through the silence');

        controller.stopPolling();
        await tester.pump(const Duration(seconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    test(
      'the REPOSITORY maps a silent response to a null snapshot rather '
      'than throwing — silence is an answer, not a malformed body',
      () async {
        // WHY THIS TEST EXISTS: mutation M-D9 SURVIVED the widget-level
        // silence test above. Replacing the repository's null mapping
        // with a bare `AiSessionStateSnapshot.fromJson` makes a silent
        // `{revision: null, state: null}` throw a FormatException, which
        // `_invoke` converts to AiSessionInternalError and `_pollTick`'s
        // catch-all swallows — so the phase stayed active, no error was
        // set and the poll kept running, satisfying every assertion up
        // there BY ACCIDENT, through a thrown-and-swallowed exception
        // rather than a clean null.
        //
        // The two are NOT equivalent: one burns an exception on every
        // tick for the lifetime of the sheet, and the repository's
        // documented contract ("returns null for no answer") would be
        // unenforced, so any future caller that does NOT wrap the call
        // in a catch-all — a foreground refresh, a retry button — gets a
        // spurious INTERNAL_ERROR in the user's face for a perfectly
        // ordinary authorization outcome. So the mutant is killed HERE,
        // at the layer whose contract it actually breaks.
        final gateway = _FakeSessionGateway({
          'read_state': (_) =>
              _readStateResponse(revision: null, state: null),
        });
        final repository = AiSessionRepository(gateway);

        // Returns, rather than throwing. `expect(..., isNull)` alone
        // would not distinguish the two: a throw fails the test before
        // the matcher runs, which is the point.
        final snapshot = await repository.readState(_sessionId);
        expect(
          snapshot,
          isNull,
          reason: 'a silent RPC answer is "no answer" and must surface '
              'as null — it is what an unknown session, a non-member, a '
              'withdrawal, an expiry and a never-approved shared session '
              'ALL produce, byte-identically (§7.2), so it is the most '
              'ordinary outcome this command has and cannot be an error',
        );

        // And the non-silent body still parses, so the leg above is not
        // passing because the method returns null unconditionally.
        final live = AiSessionRepository(
          _FakeSessionGateway({
            'read_state': (_) =>
                _readStateResponse(revision: 7, state: 'active'),
          }),
        );
        final parsed = await live.readState(_sessionId);
        expect(parsed, isNotNull);
        expect(parsed!.revision, 7);
        expect(parsed.state, AiSessionPolledState.active);
      },
    );

    test(
      'a MALFORMED read_state body is still an error — a missing '
      'revision beside a non-null state is not silence',
      () async {
        // The boundary the mapping must not blur. Silence is BOTH keys
        // null; a `state` with no `revision` is a broken server, and
        // turning that into a benign null would manufacture a healthy
        // empty state out of a malformed one — the same inference as
        // "empty means gone", run in reverse.
        final gateway = _FakeSessionGateway({
          'read_state': (_) =>
              <String, dynamic>{'revision': null, 'state': 'active'},
        });
        final repository = AiSessionRepository(gateway);

        await expectLater(
          repository.readState(_sessionId),
          throwsA(isA<AiSessionInternalError>()),
        );
      },
    );

    testWidgets(
      'a polled bump the partner did not cause re-reads the transcript, '
      'and the revision is COMPARED rather than derived',
      (tester) async {
        var reads = 0;
        var transcriptReads = 0;
        final bodies = <Map<String, dynamic>>[];
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(revision: 4),
          'review_context': (_) => _reviewResponse(revision: 4),
          'approve': (_) => _approveResponse(activated: true),
          'read': (body) {
            transcriptReads++;
            bodies.add(body);
            return <String, dynamic>{
              'turns': <Map<String, dynamic>>[
                <String, dynamic>{
                  'ordinal': 7,
                  'role': 'attune',
                  'kind': 'ideas_answer',
                  'payload': <String, dynamic>{'reply_text': 'partner turn'},
                  'created_at': '2026-10-11T10:00:00.000Z',
                },
              ],
            };
          },
          'read_state': (_) {
            reads++;
            // The partner committed a turn: 4 -> 5. This actor made no
            // call that could have told them.
            return _readStateResponse(revision: 5, state: 'active');
          },
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activateUnderFakeAsync(tester, controller);
        final before = transcriptReads;
        controller.startPolling();

        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));

        final state = container.read(aiSessionControllerProvider);
        expect(
          state.revision,
          5,
          reason: 'the revision is ASSIGNED FROM THE SERVER, never '
              'incremented locally — gate 1 leaves nothing to fall back '
              'to and gate 2 means a client cannot recompute a digest',
        );
        expect(
          transcriptReads,
          before + 1,
          reason: 'a bump re-reads the transcript through the AUTHORIZED '
              'read path; the poll itself carries no turn text',
        );
        expect(
          state.turns.single.ordinal,
          7,
          reason: "the server's own ordinal, passed through — ordinals "
              'are 2n-1/2n and may be non-contiguous',
        );
        // The poll-driven read did NOT ask about a request.
        expect(bodies.last.containsKey('request_id'), isFalse);

        // AND AN UNCHANGED REVISION DOES NOT RE-READ. Without this leg a
        // poll that re-read on EVERY tick would pass everything above
        // while hammering the transcript endpoint every five seconds.
        final afterBump = transcriptReads;
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          transcriptReads,
          afterBump,
          reason: 'the revision is unchanged on the second tick, so '
              'there is nothing to re-read — the comparison is what '
              'makes the poll cheap',
        );
        expect(reads, 2);

        controller.stopPolling();
        await tester.pump(const Duration(seconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'the waitingForPartner wait TERMINATES: a polled `active` moves '
      'the phase and reads the transcript',
      (tester) async {
        var stateReads = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(visibility: 'shared'),
          // THIS ACTOR APPROVED FIRST: a 200 success with
          // activated: false. Nothing will ever tell them the partner
          // approved — which is the entire reason the poll exists.
          'approve': (_) => _approveResponse(activated: false),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
          'read_state': (_) {
            stateReads++;
            // The partner has now approved and the server activated.
            return _readStateResponse(revision: 1, state: 'active');
          },
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        final prepared = controller.prepare(
          idempotencyKey: 'key',
          relationshipId: 'rel-1',
          kind: AiSessionKind.ideas,
          visibility: AiSessionVisibility.shared,
          utcOffsetMinutes: 0,
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await prepared;
        final approved = controller.approve();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await approved;

        expect(
          container.read(aiSessionControllerProvider).phase,
          AiSessionPhase.waitingForPartner,
          reason: 'precondition: the first approver waits, and this is a '
              '200 SUCCESS rather than an error',
        );

        controller.startPolling();
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          container.read(aiSessionControllerProvider).phase,
          AiSessionPhase.active,
          reason: 'the poll is the ONLY way this actor can learn their '
              "partner approved — `read` cannot serve it, because "
              "read_ai_session_turns' gate refuses a non-active session "
              'and so reports nothing during the whole wait',
        );
        expect(stateReads, 1);

        controller.stopPolling();
        await tester.pump(const Duration(seconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });

  group('Task 8: the sheet wires and unwires the poll', () {
    testWidgets(
      'the sheet TEARS DOWN cleanly — dispose stops the poll without '
      'touching `ref`, which throws once the element is unmounted',
      (tester) async {
        // REGRESSION TEST FOR A BUG I SHIPPED INTO MY OWN FIRST DRAFT.
        // `dispose` reached the controller through the `_controller`
        // getter, which is `ref.read(...)`. Riverpod throws
        // `Bad state: Cannot use "ref" after the widget was disposed`
        // at that point, so EVERY teardown of this sheet crashed — and it
        // took 18 previously-passing widget tests in this file down with
        // it, each reporting a StateError "while finalizing the widget
        // tree" rather than anything about the poll.
        //
        // IT WAS INVISIBLE TO A SCOPED RUN. `--plain-name "Task 8"` never
        // instantiates the sheet widget, so the poll tests all passed
        // while the file was broken. That is why this test renders the
        // real sheet and disposes it, rather than asserting on the
        // controller alone.
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
          'read_state': (_) =>
              _readStateResponse(revision: 1, state: 'active'),
        });

        await _pumpSheet(tester, gateway);
        // Replacing the tree disposes the sheet. If `dispose` touches
        // `ref`, this pump throws and the test fails here.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'disposing the sheet must not throw. `dispose` has to '
              'use a notifier captured in initState, because `ref` is '
              'unusable once the element is unmounted — and the '
              'controller outlives the widget anyway, being owned by the '
              'provider container',
        );
      },
    );

    testWidgets(
      'no timer survives the sheet: a disposed sheet leaves nothing '
      'pending for the test binding to complain about',
      (tester) async {
        // `testWidgets` fails a test that leaves a timer pending, so
        // this reaching its end IS the assertion — but it is made
        // explicit because the failure mode it guards is a leaked
        // `Timer.periodic` calling into a disposed notifier, which
        // throws on its first write to `state` and would otherwise
        // surface as an unrelated-looking crash in whatever test ran
        // next.
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
          'read_state': (_) =>
              _readStateResponse(revision: 1, state: 'active'),
        });

        await _pumpSheet(tester, gateway);
        await tester.pumpWidget(const SizedBox.shrink());
        // Well past several poll intervals. A surviving timer would fire
        // here, against a torn-down notifier.
        await tester.pump(const Duration(seconds: 30));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Task 8: RULING 6 — the polled value does not move on a refusal',
      () {
    testWidgets(
      'a safety refusal leaves the polled revision UNCHANGED, and the '
      'poll issues no transcript re-read because of it',
      (tester) async {
        // The server's behaviour, transcribed: a refusal settles the
        // REQUEST row and returns. It never reaches
        // commit_ai_session_ideas_turn, so `revision = revision + 1`
        // never runs. MEASURED on a live database for this task:
        // across a refusal, revision 1 -> 1 while attempt_count 0 -> 1
        // and last_admitted_at NULL -> a timestamp. That is exactly why
        // those two fields are not on this surface.
        var polledRevision = 3;
        var transcriptReads = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(revision: 3),
          'review_context': (_) => _reviewResponse(revision: 3),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) {
            transcriptReads++;
            return <String, dynamic>{'turns': <dynamic>[]};
          },
          // THE REFUSAL. Note it carries NO `session_revision`: nothing
          // was committed, so there is no bump to report.
          'generate': (_) => _safetyRefusal(),
          'read_state': (_) =>
              _readStateResponse(revision: polledRevision, state: 'active'),
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activateUnderFakeAsync(tester, controller);
        controller.startPolling();

        // Settle the pre-refusal baseline through a real tick.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        final revisionBefore =
            container.read(aiSessionControllerProvider).revision;
        final readsBefore = transcriptReads;
        expect(
          revisionBefore,
          3,
          reason: 'baseline, so the comparison below is against a real '
              'value rather than a null',
        );

        // Drive the refusal.
        final refusal = controller.generate(
          requestId: _requestId,
          userInstruction: 'something refused',
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await refusal;

        // *** THE PRECONDITION: the refusal really happened. *** Without
        // this the whole test could pass because nothing occurred at
        // all — which is the shape of a vacuous Ruling 6 test.
        final afterRefusal = container.read(aiSessionControllerProvider);
        expect(
          afterRefusal.redirect,
          isNotNull,
          reason: 'PRECONDITION: a redirect must be in the state, or no '
              'refusal occurred and "the revision did not move" is '
              'vacuous',
        );
        expect(
          afterRefusal.redirect!.reason,
          'unsafe_to_assist',
          reason: 'PRECONDITION: and it is the SAFETY reason '
              'specifically',
        );

        // *** THE ASSERTION: the polled value has not moved. ***
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        final afterPoll = container.read(aiSessionControllerProvider);
        expect(
          afterPoll.revision,
          revisionBefore,
          reason: 'RULING 6: a refusal must leave the revision '
              'untouched. A revision that moved on a refusal would let a '
              'partner polling it detect that a refusal occurred — the '
              'disclosure §8.1 forbids, and the reason the two '
              'kind:"redirect" shapes share a reason set at all',
        );
        expect(
          transcriptReads,
          readsBefore,
          reason: 'nothing was committed, so there is nothing to '
              're-read; a re-read here would itself be a signal that '
              'something happened',
        );

        // THE CONTROL that stops the above from being vacuous: this same
        // polled value DOES move when the server really bumps it.
        // Without this, a poll that had silently stopped reading the
        // revision at all would pass every assertion above.
        polledRevision = 4;
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          container.read(aiSessionControllerProvider).revision,
          4,
          reason: 'VACUITY CHECK: the polled revision must be capable of '
              'moving, or "unchanged across a refusal" measured a value '
              'that never changes',
        );

        controller.stopPolling();
        await tester.pump(const Duration(seconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });

  group('Task 8: RULING 9 — staged survives a poll-driven refresh', () {
    testWidgets(
      'a poll-driven refresh puts stagedResults BACK to null — "I did '
      'not ask" — rather than preserving a stale non-null',
      (tester) async {
        // THE RULING 9 TRAP, AND A POLL IS WHERE IT GETS LOST. Task 7
        // found that without an explicit clear flag the field can only
        // ever move AWAY from null. A poll refreshes state on a timer,
        // so if its refresh could not write a null back, then once
        // anything asked about a request the sheet would keep offering
        // Publish/Discard forever — for a staging row no read has
        // confirmed, and which may have expired two minutes ago.
        var polledRevision = 1;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (body) => body.containsKey('request_id')
              // ASKED: a real staged row.
              ? <String, dynamic>{
                  'turns': <dynamic>[],
                  'staged': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'request_id': _requestId,
                      'reply_text': 'Two places near you.',
                      'sources': <dynamic>[],
                      'expires_at': '2026-10-11T11:00:00.000Z',
                    },
                  ],
                }
              // DID NOT ASK: `staged` ABSENT, not `[]`.
              : <String, dynamic>{'turns': <dynamic>[]},
          'read_state': (_) =>
              _readStateResponse(revision: polledRevision, state: 'active'),
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activateUnderFakeAsync(tester, controller);

        // Ask, and hold a real staged result.
        final asked = controller.refresh(requestId: _requestId);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await asked;
        expect(
          container.read(aiSessionControllerProvider).stagedResults,
          isNotNull,
          reason: 'precondition: there is something to lose',
        );
        expect(
          container.read(aiSessionControllerProvider).stagedResults,
          hasLength(1),
        );

        // Now a poll observes a bump and refreshes WITHOUT a request_id.
        controller.startPolling();
        polledRevision = 2;
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          container.read(aiSessionControllerProvider).stagedResults,
          isNull,
          reason: 'RULING 9: the poll did not ask about any request, so '
              'stagedResults must read as "I did not ask" (null) — not '
              'as a preserved stale list. `clearStagedResults` is what '
              'lets the null actually be WRITTEN rather than merely not '
              'overwritten, and a `?? []` anywhere on this path would '
              'collapse the distinction in one character',
        );

        controller.stopPolling();
        await tester.pump(const Duration(seconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'a poll does NOT touch pendingStage — this actor\'s own '
      'un-published generation is not the poll\'s business',
      (tester) async {
        var polledRevision = 1;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(kind: 'nearby'),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{'turns': <dynamic>[]},
          'generate': (_) => _stagedNearby(),
          'read_state': (_) =>
              _readStateResponse(revision: polledRevision, state: 'active'),
        });
        final container = _container(gateway);
        final controller = container.read(
          aiSessionControllerProvider.notifier,
        );
        await _activateUnderFakeAsync(tester, controller);
        final staging = controller.generate(
          requestId: _requestId,
          userInstruction: 'coffee near me',
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await staging;
        expect(
          container.read(aiSessionControllerProvider).pendingStage,
          isNotNull,
          reason: 'precondition: a staged generation this actor holds',
        );

        controller.startPolling();
        polledRevision = 2;
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          container.read(aiSessionControllerProvider).pendingStage,
          isNotNull,
          reason: 'pendingStage is known ONLY from this actor\'s own '
              'generate response and is requester-private until they '
              'publish; a poll has no authority over it and clearing it '
              'would silently discard a result the user can still '
              'publish — while the quota was already consumed',
        );

        controller.stopPolling();
        await tester.pump(const Duration(seconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });

  // ===================================================================
  // THE TWO ROOT-CAUSE TEST SHAPES
  //
  // The final whole-branch review found three defects and named ONE
  // structural cause for all three:
  //
  //   > No test pumps a PARTIAL capability set (every sheet test uses
  //   > `_allOn`), and no test's gateway fails `prepare` or `generate`
  //   > on the first call — so the second tap is never exercised
  //   > anywhere in the branch.
  //
  // Both groups below exist to close that, not merely to pin the two
  // fixes. Every test here drives a capability set in which the
  // DEFAULTED field is the disabled one, or a gateway that refuses the
  // FIRST call and answers the SECOND.
  // ===================================================================

  group('FINDING 2: the idempotency key is STABLE across a retry', () {
    testWidgets(
      'FIRST-CALL FAILURE: prepare fails, the user taps Start again, and '
      'the SAME key is sent — so the server can replay',
      (tester) async {
        var prepareCalls = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) {
            prepareCalls++;
            // The lost-response shape: the RPC committed, the HTTP
            // answer did not arrive. The sheet renders
            // "Something went wrong — try again", which is the copy
            // that invites the retry this test drives.
            if (prepareCalls == 1) {
              throw _functionError('INTERNAL_ERROR', 500);
            }
            // The replay: the ORIGINAL session, `created: false`.
            return <String, dynamic>{
              'session_id': _sessionId,
              'revision': 1,
              'created': false,
            };
          },
          'review_context': (_) => _reviewResponse(),
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        // Still on preparation, with the error that invites a retry.
        expect(find.text(kAiSessionStartLabel), findsOneWidget);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();

        final keys = gateway.bodies
            .where((b) => b['command'] == 'prepare')
            .map((b) => b['idempotency_key'] as String)
            .toList();
        expect(keys, hasLength(2));
        expect(
          keys[1],
          keys[0],
          reason: 'the retry must reuse the key, or '
              'prepare_ai_session\'s `v_existing_session IS NOT NULL` '
              'replay branch cannot fire and the slot-limit guard '
              'answers SESSION_LIMIT_REACHED instead',
        );
        // And the replay actually got through: the sheet reached the
        // approval step on the session the FIRST tap created.
        expect(find.text(kAiSessionApproveLabel), findsOneWidget);
      },
    );

    testWidgets('the key is a canonical v4 uuid, not merely v4-SHAPED', (
      tester,
    ) async {
      // The file's own comment at the generator: the key BECOMES the
      // session id and `parsePrepareRequest` runs `isCanonicalUuid`
      // over it, so a v4-shaped string is an invalid session id and
      // INVALID_INPUT on every call. A `??=` holding a hand-rolled
      // string would pass the stability test above and fail every real
      // call.
      final gateway = _FakeSessionGateway({
        'prepare': (_) => _prepareResponse(),
        'review_context': (_) => _reviewResponse(),
      });
      await _pumpSheet(tester, gateway);
      await tester.tap(find.text(kAiSessionStartLabel));
      await tester.pumpAndSettle();

      final key =
          gateway.bodies.firstWhere(
                (b) => b['command'] == 'prepare',
              )['idempotency_key']
              as String;
      expect(
        key,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
    });

    testWidgets(
      'a DELIBERATELY NEW session gets a FRESH key — a second sheet does '
      'NOT replay the first one',
      (tester) async {
        // ANTI-VACUITY for the KEY'S SCOPE. A key held anywhere longer
        // than one `State` — a static, a top-level, a non-autoDispose
        // provider — would pass the retry test above and then replay
        // the previous session forever, reporting `created: false` on
        // a session the user meant to be new.
        //
        // WHAT THIS DOES NOT PROVE, stated rather than implied: it
        // does not exercise the release-on-success inside ONE State,
        // because `choosing` is only the controller's INITIAL phase and
        // nothing returns to it — a successful prepare moves to
        // `reviewing` and the Start button is gone, so a second
        // successful `_start()` from one State is unreachable through
        // the UI today. The release is there for the day a "start
        // over" path is added, and it is honestly unpinned until then;
        // the mutation note in the report records that.
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'end': (_) => <String, dynamic>{'ended': true},
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        final firstKey = gateway.bodies.firstWhere(
          (b) => b['command'] == 'prepare',
        )['idempotency_key'];

        // A fresh sheet is a fresh preparation, which is the path a
        // user takes to a genuinely new session. The UniqueKey in
        // `_pumpSheet` tears the previous controller down.
        await _pumpSheet(tester, gateway);
        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();

        final keys = gateway.bodies
            .where((b) => b['command'] == 'prepare')
            .map((b) => b['idempotency_key'])
            .toList();
        expect(keys, hasLength(2));
        expect(
          keys[1],
          isNot(firstKey),
          reason: 'a new session must not replay the previous one',
        );
      },
    );

    testWidgets(
      'prepare SUCCEEDS but review_context fails: the key is HELD, '
      'because the session exists and the retry must replay it',
      (tester) async {
        // The asymmetry the `??=` has to get right, and the one a
        // naive `try/catch` around `prepare` gets WRONG. `prepare`
        // funnels through the controller's `_run`, which CATCHES the
        // §10 error into `state.error` and returns normally — so
        // nothing throws here on either path, and a try/catch would
        // see success and release the key. But `prepare` and
        // `review_context` are ONE controller call: the prepare half
        // committed a `preparing` session, so releasing the key would
        // put the very lockout Finding 2 describes one step later.
        var prepareCalls = 0;
        var reviewCalls = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) {
            prepareCalls++;
            return _prepareResponse();
          },
          'review_context': (_) {
            reviewCalls++;
            if (reviewCalls == 1) throw _functionError('INTERNAL_ERROR', 500);
            return _reviewResponse();
          },
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        // Still on preparation: the review half failed, so there is
        // nothing to approve.
        expect(find.text(kAiSessionStartLabel), findsOneWidget);
        expect(prepareCalls, 1);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();

        final keys = gateway.bodies
            .where((b) => b['command'] == 'prepare')
            .map((b) => b['idempotency_key'] as String)
            .toList();
        expect(keys, hasLength(2));
        expect(
          keys[1],
          keys[0],
          reason: 'the prepare half COMMITTED, so the second tap must '
              'replay that session rather than ask for a new one — '
              'the slot limit would refuse a new one anyway',
        );
        expect(find.text(kAiSessionApproveLabel), findsOneWidget);
      },
    );

    testWidgets(
      'changing the VISIBILITY rotates the key, because the key is the '
      'session identity and a replay would return the ORIGINAL shape',
      (tester) async {
        var prepareCalls = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) {
            prepareCalls++;
            if (prepareCalls == 1) throw _functionError('INTERNAL_ERROR', 500);
            return _prepareResponse();
          },
          'review_context': (_) => _reviewResponse(),
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        // Now change the intent before retrying.
        await tester.tap(find.text(kAiSessionSharedLabel));
        await tester.pump();
        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();

        final prepares = gateway.bodies
            .where((b) => b['command'] == 'prepare')
            .toList();
        expect(prepares, hasLength(2));
        expect(prepares[0]['visibility'], 'private');
        expect(prepares[1]['visibility'], 'shared');
        expect(
          prepares[1]['idempotency_key'],
          isNot(prepares[0]['idempotency_key']),
          reason: 'detectPrepareKeyConflict compares visibility, so a '
              'held key here would be REQUEST_CONFLICT — a dead end, '
              'not a replay',
        );
      },
    );

    testWidgets(
      'changing the KIND rotates the key — kind is part of the payload '
      'the server compares, so a held key would be REQUEST_CONFLICT',
      (tester) async {
        // The third rotation. Found by mutation: dropping
        // `_rotateIdempotencyKey()` from `onKind` alone survived the
        // whole suite until this test existed, because every other
        // rotation test changes visibility or the window.
        var prepareCalls = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) {
            prepareCalls++;
            if (prepareCalls == 1) throw _functionError('INTERNAL_ERROR', 500);
            return _prepareResponse();
          },
          'review_context': (_) => _reviewResponse(kind: 'nearby'),
        });
        await _pumpSheet(tester, gateway);

        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ChoiceChip),
            matching: find.text(kAiSessionNearbyLabel),
          ),
        );
        await tester.pump();
        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();

        final prepares = gateway.bodies
            .where((b) => b['command'] == 'prepare')
            .toList();
        expect(prepares, hasLength(2));
        expect(prepares[0]['kind'], 'ideas');
        expect(prepares[1]['kind'], 'nearby');
        expect(
          prepares[1]['idempotency_key'],
          isNot(prepares[0]['idempotency_key']),
          reason: 'detectPrepareKeyConflict compares kind, so a held '
              'key here is REQUEST_CONFLICT — a dead end, not a replay',
        );
      },
    );

    testWidgets(
      'changing the RECENT WINDOW rotates the key too — the server does '
      'NOT compare include_window, so only rotation makes the toggle real',
      (tester) async {
        // Load-bearing, and the one rotation the server cannot cover
        // for us: `detectPrepareKeyConflict` compares
        // relationship_id, kind, visibility and the target source — NOT
        // include_window. A held key across this toggle would be
        // silently replayed with the ORIGINAL window setting and
        // reported `created: false`, so the user's toggle would have no
        // effect they could observe.
        var prepareCalls = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) {
            prepareCalls++;
            if (prepareCalls == 1) throw _functionError('INTERNAL_ERROR', 500);
            return _prepareResponse();
          },
          'review_context': (_) => _reviewResponse(visibility: 'shared'),
        });
        await _pumpSheet(tester, gateway);

        // Shared + Ideas + the window capability is the only shape that
        // offers the toggle at all.
        await tester.tap(find.text(kAiSessionSharedLabel));
        await tester.pump();
        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();

        final keyBefore = gateway.bodies.lastWhere(
          (b) => b['command'] == 'prepare',
        )['idempotency_key'];

        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();
        await tester.tap(find.text(kAiSessionStartLabel));
        await tester.pumpAndSettle();

        final prepares = gateway.bodies
            .where((b) => b['command'] == 'prepare')
            .toList();
        expect(prepares, hasLength(2));
        expect(prepares[0]['include_window'], isFalse);
        expect(prepares[1]['include_window'], isTrue);
        expect(prepares[1]['idempotency_key'], isNot(keyBefore));
      },
    );
  });

  group('FINDING 3: generate\'s request_id is stable, and so is the text', () {
    /// prepare -> approve -> active, through the WIDGET, so the
    /// instruction field is real.
    Future<void> activateSheet(
      WidgetTester tester,
      _FakeSessionGateway gateway,
    ) async {
      await _pumpSheet(tester, gateway);
      await tester.tap(find.text(kAiSessionStartLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kAiSessionApproveLabel));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'FIRST-CALL FAILURE: generate fails, the instruction SURVIVES in '
      'the field, and the retry sends the SAME request_id',
      (tester) async {
        var generateCalls = 0;
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{
            'turns': <Map<String, dynamic>>[
              _turn(ordinal: 1, role: 'user'),
              _turn(ordinal: 2, role: 'attune'),
            ],
            'staged': null,
          },
          'generate': (_) {
            generateCalls++;
            if (generateCalls == 1) {
              throw _functionError('INTERNAL_ERROR', 500);
            }
            return _ideasAnswer();
          },
        });
        await activateSheet(tester, gateway);

        await tester.enterText(
          find.byType(TextField),
          'what should we do friday',
        );
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        // THE TEXT IS STILL THERE. Clearing before the await threw it
        // away on every failure, and a retype is a different
        // fingerprint, so even a byte-identical retype could not
        // replay.
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'what should we do friday',
        );

        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        final ids = gateway.bodies
            .where((b) => b['command'] == 'generate')
            .map((b) => b['request_id'] as String)
            .toList();
        expect(ids, hasLength(2));
        expect(
          ids[1],
          ids[0],
          reason: 'a fresh id cannot reach §6.2\'s already_admitted '
              'replay, so a lost response costs two provider leases '
              'for one answer',
        );
        // And the retry sent the SAME instruction, which the
        // fingerprint also covers.
        final instructions = gateway.bodies
            .where((b) => b['command'] == 'generate')
            .map((b) => b['user_instruction'])
            .toSet();
        expect(instructions, <String>{'what should we do friday'});
        // The committed answer cleared the field.
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
      },
    );

    testWidgets(
      'a SECOND, different turn gets a FRESH request_id — the id is '
      'released by a committed answer',
      (tester) async {
        // ANTI-VACUITY for the `??=`: an id held forever would make the
        // second turn a REQUEST_CONFLICT (different instruction, same
        // id), which is a dead end rather than a replay.
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) => <String, dynamic>{
            'turns': <Map<String, dynamic>>[_turn(ordinal: 1, role: 'user')],
            'staged': null,
          },
          'generate': (_) => _ideasAnswer(),
        });
        await activateSheet(tester, gateway);

        await tester.enterText(find.byType(TextField), 'first question');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'second question');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        final generates = gateway.bodies
            .where((b) => b['command'] == 'generate')
            .toList();
        expect(generates, hasLength(2));
        expect(generates[0]['user_instruction'], 'first question');
        expect(generates[1]['user_instruction'], 'second question');
        expect(
          generates[1]['request_id'],
          isNot(generates[0]['request_id']),
        );
      },
    );

    testWidgets(
      'a REDIRECT releases the id and clears the field — the server '
      'spent the attempt, so the next turn is a new request',
      (tester) async {
        // RULING 6 SAFE: this asserts only that the id ROTATED and the
        // field cleared, which happens identically for both redirect
        // shapes. It never asks which shape arrived, and the two paths
        // through `_generate` are the same code with the same
        // `state.error == null`.
        final gateway = _FakeSessionGateway({
          'prepare': (_) => _prepareResponse(),
          'review_context': (_) => _reviewResponse(),
          'approve': (_) => _approveResponse(activated: true),
          'read': (_) =>
              <String, dynamic>{'turns': <Map<String, dynamic>>[], 'staged': null},
          'generate': (_) => _ordinaryRedirect(),
        });
        await activateSheet(tester, gateway);

        await tester.enterText(find.byType(TextField), 'something off topic');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );

        await tester.enterText(find.byType(TextField), 'back on topic');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        final generates = gateway.bodies
            .where((b) => b['command'] == 'generate')
            .toList();
        expect(generates, hasLength(2));
        expect(
          generates[1]['request_id'],
          isNot(generates[0]['request_id']),
        );
      },
    );
  });
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

/// The REAL `FunctionException`, not a stand-in.
///
/// `SupabaseAiAssistantGateway.invokeFunction` only ever raises this
/// concrete type on a non-2xx response, and
/// `AiSessionRepository._mapTransportError` branches on
/// `error is FunctionException` — so a stand-in would fall through to
/// `internalError()` while every test here still passed. Task 1 found
/// exactly that and the repository suite records it.
FunctionException _functionError(String code, int status) {
  return FunctionException(
    status: status,
    details: <String, dynamic>{'code': code},
    reasonPhrase: code,
  );
}

/// Drives prepare -> approve -> active, so a generate/publish test
/// states only what it is actually about.
Future<void> _activate(AiSessionController controller) async {
  await controller.prepare(
    idempotencyKey: 'key',
    relationshipId: 'rel-1',
    kind: AiSessionKind.ideas,
    visibility: AiSessionVisibility.private,
    utcOffsetMinutes: 0,
  );
  await controller.approve();
}

/// A gateway whose `read_state` takes TWELVE SECONDS — longer than two
/// poll intervals — so an overlapping implementation is caught by
/// counting concurrent in-flight calls rather than by inspecting the
/// controller's private state.
///
/// Every other command answers immediately, so the setup this test
/// shares with the others is unaffected.
class _SlowStateGateway implements AiAssistantGateway {
  _SlowStateGateway({required this.onReadState, required this.onReadStateDone});

  final void Function() onReadState;
  final void Function() onReadStateDone;

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    final command = body?['command'] as String?;
    if (command == 'read_state') {
      onReadState();
      await Future<void>.delayed(const Duration(seconds: 12));
      onReadStateDone();
      return <String, dynamic>{'revision': 1, 'state': 'active'};
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return switch (command) {
      'prepare' => _prepareResponse(),
      'review_context' => _reviewResponse(),
      'approve' => _approveResponse(activated: true),
      'read' => <String, dynamic>{'turns': <dynamic>[]},
      _ => throw StateError('no fake handler for command "$command"'),
    };
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) =>
      throw UnimplementedError();
}

/// Runs the prepare+approve setup INSIDE a `testWidgets` FakeAsync zone.
///
/// **`await _activate(controller)` DEADLOCKS under `testWidgets`, and
/// that is not a quirk of this file.** `_FakeSessionGateway` delays each
/// response by 5ms to keep "no premature render" assertions non-vacuous.
/// Inside `testWidgets` the zone's clock does not advance on its own, so
/// that delay never elapses and the `await` never returns — the test
/// hangs rather than failing, which is how I found it.
///
/// So the future is started WITHOUT awaiting it and the clock is pumped
/// until it completes. Every poll test needs this because the poll is a
/// `Timer.periodic`, which only `testWidgets` can drive deterministically
/// — a plain `test()` would have to sleep in real time.
Future<void> _activateUnderFakeAsync(
  WidgetTester tester,
  AiSessionController controller,
) async {
  final done = _activate(controller);
  // Several awaits chain inside prepare() -> _reviewContext() -> approve()
  // -> _read(), each behind its own 5ms delay; pumping past the sum
  // settles them all.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(Duration.zero);
  await done;
}
