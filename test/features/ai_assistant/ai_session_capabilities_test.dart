// test/features/ai_assistant/ai_session_capabilities_test.dart
//
// Spec §12's capability flags as the client reads them (Plan D Task 5).
//
// The thing this file must actually prove is NOT "five booleans parse".
// PF2's failure mode was a flag the client could never learn the state
// of, so the load-bearing tests here are:
//
//   * every path through `load()` that is not an explicit server `true`
//     yields `false` -- no code path can turn a capability on without
//     the server saying so (the "flags stay OFF" requirement);
//   * the five capabilities are INDEPENDENT, asserted by crossing each
//     one against the other four, so no call site can infer one from
//     another (§12's subcapability independence);
//   * the parsed surface is CLOSED, asserted structurally from source
//     rather than against a hand-written name list -- because a name
//     list cannot catch a member whose author does not know this test
//     exists, which is the gap Task 4's M1b found and fixed.
//
// The flags are all `false` on the server on this branch. Nothing here
// asserts a server value; these are tests of the client's behaviour
// GIVEN a server answer, with the real values proved by
// supabase/tests/ai_session_capability_availability_contracts.sql.

import 'dart:io';

import 'package:attune/features/ai_assistant/data/services/ai_session_capabilities.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what was asked for, so a test can assert the RPC NAME and
/// the absence of any argument -- the parameterless shape is what stops
/// the client being a key-by-key flag oracle.
class _RecordingRpc {
  final List<String> calls = <String>[];
  Object? nextResult;
  Object? nextError;

  Future<Object?> call(String name) async {
    calls.add(name);
    if (nextError != null) throw nextError!;
    return nextResult;
  }
}

/// Every key the RPC reports, set to [value]. Built from
/// [AiSessionCapabilities.wireKeys] so a key added to the contract
/// without a matching field here cannot silently go untested.
Map<String, Object?> _allKeys(bool value) {
  return <String, Object?>{
    for (final key in AiSessionCapabilities.wireKeys) key: value,
  };
}

void main() {
  group('AiSessionCapabilities.fromRpc', () {
    test('maps each wire key to its own field, all five enabled', () {
      final capabilities = AiSessionCapabilities.fromRpc(_allKeys(true));

      expect(capabilities.assist, isTrue);
      expect(capabilities.sessionsPrivate, isTrue);
      expect(capabilities.sessionsShared, isTrue);
      expect(capabilities.sessionsRecentWindow, isTrue);
      expect(capabilities.sessionsNearby, isTrue);
      expect(capabilities.noneAvailable, isFalse);
    });

    test('all five disabled -- the state this branch ships in', () {
      final capabilities = AiSessionCapabilities.fromRpc(_allKeys(false));

      expect(capabilities.assist, isFalse);
      expect(capabilities.sessionsPrivate, isFalse);
      expect(capabilities.sessionsShared, isFalse);
      expect(capabilities.sessionsRecentWindow, isFalse);
      expect(capabilities.sessionsNearby, isFalse);
      expect(capabilities.noneAvailable, isTrue);
    });

    // §12: "Subcapability disable closes affected sessions, not
    // unrelated chat." A parser that wired two keys to one field, or
    // read the wrong key into a field, would pass both tests above --
    // they only ever assert all-true or all-false. Crossing each key
    // against the other four is what makes the five fields provably
    // distinct, and it is why a UI can never justify inferring, say,
    // Nearby's availability from shared Sessions'.
    test('each capability is independent of the other four', () {
      final readers = <String, bool Function(AiSessionCapabilities)>{
        'ai_assist_enabled': (c) => c.assist,
        'ai_sessions_private_enabled': (c) => c.sessionsPrivate,
        'ai_sessions_shared_enabled': (c) => c.sessionsShared,
        'ai_sessions_recent_window_enabled': (c) => c.sessionsRecentWindow,
        'ai_sessions_nearby_enabled': (c) => c.sessionsNearby,
      };

      // Anti-vacuity: the crossing below proves nothing if this map and
      // the contract have drifted apart.
      expect(
        readers.keys.toSet(),
        AiSessionCapabilities.wireKeys,
        reason:
            'this test must cross every reported key; wireKeys and the '
            'readers map have drifted',
      );

      for (final onKey in readers.keys) {
        final payload = _allKeys(false)..[onKey] = true;
        final capabilities = AiSessionCapabilities.fromRpc(payload);

        expect(
          readers[onKey]!(capabilities),
          isTrue,
          reason: '$onKey was true on the wire but its field read false',
        );
        for (final offKey in readers.keys.where((k) => k != onKey)) {
          expect(
            readers[offKey]!(capabilities),
            isFalse,
            reason:
                'enabling $onKey also enabled $offKey — the five §12 '
                'capabilities must be separately killable, so no field '
                'may be wired to another key',
          );
        }
      }
    });

    test('an absent key reads false, matching checkEligibility CHECK 0', () {
      // The server's own rule for the same values: "a NULL, a missing
      // row, an absent key or an unexpected shape all mean disabled."
      final capabilities = AiSessionCapabilities.fromRpc(
        const <String, Object?>{},
      );

      expect(capabilities.noneAvailable, isTrue);
    });

    test('an explicit null reads false, not an exception', () {
      final capabilities = AiSessionCapabilities.fromRpc(<String, Object?>{
        for (final key in AiSessionCapabilities.wireKeys) key: null,
      });

      expect(capabilities.noneAvailable, isTrue);
    });

    // RULING 11: name what could not be read; never a constant typed
    // error. Asserted on the MESSAGE, not just the type, because a
    // FormatException thrown from a different line would satisfy
    // `throwsFormatException` and tell a reader nothing.
    test('a non-boolean raises a FormatException naming the key and type', () {
      expect(
        () => AiSessionCapabilities.fromRpc(<String, Object?>{
          ...(_allKeys(false)),
          'ai_sessions_nearby_enabled': 'true',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('ai_sessions_nearby_enabled'),
              contains('String'),
              contains('get_ai_session_capabilities'),
            ),
          ),
        ),
      );
    });

    test('the string "true" is NOT read as enabled', () {
      // The specific direction that matters: a truthy-looking non-bool
      // must never become `true`. It raises (above); this asserts the
      // service's catch then yields unavailable rather than enabled.
      expect(
        () => AiSessionCapabilities.fromRpc(<String, Object?>{
          'ai_assist_enabled': 'true',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('unavailable has every capability off', () {
      expect(AiSessionCapabilities.unavailable.assist, isFalse);
      expect(AiSessionCapabilities.unavailable.sessionsPrivate, isFalse);
      expect(AiSessionCapabilities.unavailable.sessionsShared, isFalse);
      expect(AiSessionCapabilities.unavailable.sessionsRecentWindow, isFalse);
      expect(AiSessionCapabilities.unavailable.sessionsNearby, isFalse);
      expect(AiSessionCapabilities.unavailable.noneAvailable, isTrue);
    });
  });

  group('AiSessionCapabilitiesService.load', () {
    test('calls get_ai_session_capabilities with no argument', () async {
      final rpc = _RecordingRpc()..nextResult = _allKeys(true);

      final capabilities = await AiSessionCapabilitiesService(rpc.call).load();

      // The NAME, asserted literally: the client and migration
      // 20260953200500 must agree, and a typo would fail closed
      // silently (the catch below yields unavailable) rather than
      // erroring, so nothing else here would notice.
      expect(rpc.calls, <String>['get_ai_session_capabilities']);
      expect(AiSessionCapabilitiesService.rpcName,
          'get_ai_session_capabilities');
      expect(capabilities.assist, isTrue);
    });

    test('exactly one round trip for all five capabilities', () async {
      final rpc = _RecordingRpc()..nextResult = _allKeys(false);

      await AiSessionCapabilitiesService(rpc.call).load();

      // Five providers over this RPC would issue five identical calls
      // and could disagree mid-flight if an operator flipped a flag
      // between them — which a UI would read as two capabilities
      // changing independently when in fact it saw two instants.
      expect(rpc.calls, hasLength(1));
    });

    // The PF2 requirement, from the client's side: a server value of
    // `true` must actually reach the caller. The direct-table-read
    // approach would have failed exactly here — false in, false out,
    // forever.
    test('an enabled server flag reaches the caller', () async {
      final rpc = _RecordingRpc()
        ..nextResult = (_allKeys(false)
          ..['ai_sessions_private_enabled'] = true);

      final capabilities = await AiSessionCapabilitiesService(rpc.call).load();

      expect(capabilities.sessionsPrivate, isTrue);
      expect(capabilities.sessionsShared, isFalse);
    });

    // Every non-answer must be `false`, never an exception into a
    // widget build and never an optimistic default. Each case is a
    // separate expectation so a failure names which shape leaked.
    test('fails closed on every shape that is not the contract', () async {
      final shapes = <String, Object?>{
        'null (no authenticated subject — migration 20260953200500)': null,
        'a list': <Object?>[],
        'a bare bool': true,
        'a string': 'enabled',
        'an int': 1,
        'a map with a non-boolean value': <String, Object?>{
          'ai_assist_enabled': 'true',
        },
      };

      for (final entry in shapes.entries) {
        final rpc = _RecordingRpc()..nextResult = entry.value;
        final capabilities =
            await AiSessionCapabilitiesService(rpc.call).load();

        expect(
          capabilities.noneAvailable,
          isTrue,
          reason:
              'load() must fail closed on ${entry.key}, but it reported at '
              'least one capability as available. A client that cannot read '
              'the answer must offer NOTHING — never everything.',
        );
      }
    });

    test('fails closed when the rpc throws, and does not rethrow', () async {
      final rpc = _RecordingRpc()..nextError = Exception('network down');

      final capabilities = await AiSessionCapabilitiesService(rpc.call).load();

      expect(capabilities.noneAvailable, isTrue);
    });

    test('a nested-typed map still parses (Map<dynamic, dynamic>)', () async {
      // PostgREST hands back `Map<String, dynamic>`, but a jsonb decode
      // elsewhere in the stack can produce `Map<dynamic, dynamic>`; the
      // `is! Map` check plus the key.toString() remap must accept it,
      // or a live client would fail closed forever and look exactly
      // like PF2 again.
      final rpc = _RecordingRpc()
        ..nextResult = <dynamic, dynamic>{
          'ai_assist_enabled': true,
          'ai_sessions_private_enabled': false,
          'ai_sessions_shared_enabled': false,
          'ai_sessions_recent_window_enabled': false,
          'ai_sessions_nearby_enabled': false,
        };

      final capabilities = await AiSessionCapabilitiesService(rpc.call).load();

      expect(capabilities.assist, isTrue);
    });
  });

  group('the disclosed surface is closed', () {
    // A NAME-LIST ASSERTION IS NOT A CLOSED-SURFACE PROOF. Task 4's
    // M1b defeated one: a getter whose author did not update the list
    // passed. So this reads the DECLARATIONS from source, the technique
    // already used by this repo (community_entry_test.dart,
    // android_manifest_test.dart) and by Task 4's redirect test.
    //
    // What it guards: every member of AiSessionCapabilities is
    // capability state that left the server, and §12 plus
    // 20260712150000's finding make adding one a disclosure decision.
    // An `understand` field, or a `rolloutPlan` map, must fail here and
    // be argued rather than inherited.
    const path =
        'lib/features/ai_assistant/data/services/ai_session_capabilities.dart';

    String classBody(String declaration, String nextTopLevel) {
      final source = File(path).readAsStringSync();
      final start = source.indexOf(declaration);
      expect(
        start,
        isNonNegative,
        reason:
            'the declaration "$declaration" moved or was renamed — '
            're-point this test rather than deleting it',
      );
      final afterStart = start + declaration.length;
      final end = source.indexOf(nextTopLevel, afterStart);
      expect(
        end,
        isNonNegative,
        reason: 'expected "$nextTopLevel" after $declaration',
      );
      final body = source.substring(afterStart, end);
      // Anti-vacuity: a runaway or empty slice would make every
      // assertion below pass trivially.
      expect(body, isNotEmpty);
      expect(body.length, lessThan(source.length));
      return body;
    }

    /// Strips comments and string literals, so the long doc comments in
    /// this file — which NAME the keys and the rejected options — cannot
    /// be mistaken for declarations. This trap has fired three times in
    /// this effort and is a ruling in the ledger.
    String strip(String body) {
      return body
          .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
          .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
    }

    test('AiSessionCapabilities declares exactly the expected members', () {
      final body = classBody(
        'class AiSessionCapabilities {',
        '\nclass AiSessionCapabilitiesService',
      );
      expect(body, contains('final bool assist;'));

      final stripped = strip(body);

      // THE STRIPPER IS PROVED WITH TWO PROBES, one per KIND of thing
      // it removes, because one probe was not enough and two mutations
      // proved it.
      //
      // M10 deleted the string-literal regex and the suite stayed
      // GREEN. The single original probe was `ai_understand_enabled`,
      // which appears in this class ONLY inside a `///` line, so it
      // said nothing about string stripping at all — and could not
      // have, since that key is written in BACKTICKS and the regex
      // matches single quotes. A probe that passes for a reason other
      // than the one claimed is Task 4's M1b family, so probe B below
      // is a quoted token on a code line and M10 now dies.
      //
      // DISCLOSED LIMIT, measured rather than assumed: M9 deleted the
      // `///` regex and no probe can kill it, because `^\s*//.*$`
      // already matches `///` lines — the two comment regexes are
      // individually redundant. Confirmed by stripping with each one
      // disabled in turn: the field and getter counts are identical
      // (7 / {noneAvailable}) all three ways. So M9 is an EQUIVALENT
      // MUTANT, not a surviving gap; probe A proves comments are
      // stripped, not which regex did it, and that is the honest
      // claim. Both are kept because a future author removing the
      // `//` regex would then need the `///` one.
      //
      // Probe A — a bare identifier on a comment line, unquoted
      // anywhere, so ONLY comment stripping can remove it.
      expect(
        body,
        contains('aiConsentStatusProvider'),
        reason:
            'probe A must appear in a /// comment in this class body. If '
            'that doc comment changed, re-point it at another bare '
            'identifier that appears only in prose',
      );
      expect(
        body,
        isNot(contains("'aiConsentStatusProvider'")),
        reason:
            'probe A must be UNQUOTED, or the string-literal regex would '
            'also remove it and probe A would stop testing comment '
            'stripping at all — which is how the original single probe '
            'let M10 survive',
      );
      expect(
        stripped,
        isNot(contains('aiConsentStatusProvider')),
        reason:
            'DOC-COMMENT STRIPPING FAILED — the counts below would be '
            'measuring documentation, not declarations',
      );

      // Probe B — a quoted token on CODE lines, which ONLY the
      // string-literal regex can remove. It occurs twice legitimately
      // (wireKeys' set literal and fromRpc's read(...)); what must not
      // happen is an occurrence inside a comment, because comment
      // stripping would then remove it and probe B would stop
      // isolating the string regex. This is the check that makes M10
      // a kill.
      //
      // Why stripping literals matters for the counts below: the field
      // regex matches `final <type> <name> =`, so a declaration-shaped
      // string literal could otherwise be counted as a declaration.
      final probeBLines = body
          .split('\n')
          .where((line) => line.contains("'ai_assist_enabled'"))
          .toList();
      expect(
        probeBLines,
        isNotEmpty,
        reason:
            "probe B vanished from the class body — re-point it at another "
            'quoted token on a code line rather than deleting it',
      );
      for (final line in probeBLines) {
        expect(
          line.trimLeft().startsWith('//'),
          isFalse,
          reason:
              'probe B occurs inside a comment ("${line.trim()}"), so the '
              'comment regex can remove it and probe B no longer isolates '
              'string-literal stripping',
        );
      }
      expect(
        stripped,
        isNot(contains('ai_assist_enabled')),
        reason:
            'STRING-LITERAL STRIPPING FAILED — a declaration-shaped string '
            'literal could now be counted as a declaration',
      );

      // Field declarations: `final <type> <name>;`
      final fields = RegExp(r'^\s*(?:static\s+)?(?:const|final)\s+[\w<>?, ]+\s+(\w+)\s*(?:=|;)',
              multiLine: true)
          .allMatches(stripped)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        fields,
        <String>{
          'assist',
          'sessionsPrivate',
          'sessionsShared',
          'sessionsRecentWindow',
          'sessionsNearby',
          'unavailable',
          'wireKeys',
        },
        reason:
            'AiSessionCapabilities gained or lost a field. Every field here '
            'is §12 capability state leaving the server for a client; '
            'adding one is a disclosure decision (see '
            '20260712150000_dating_flag_defense_in_depth.sql) and must be '
            'argued in the migration and the RPC, not just added here.',
      );

      // Getters: `<type> get <name>`
      final getters = RegExp(r'^\s*[\w<>?, ]+\s+get\s+(\w+)', multiLine: true)
          .allMatches(stripped)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        getters,
        <String>{'noneAvailable'},
        reason:
            'AiSessionCapabilities gained a getter. An aggregate such as '
            '`anyAvailable` is the wrong question under §12 — a call site '
            'must read the specific capability it is about to offer, so a '
            'convenience that lets it avoid doing so must be argued here.',
      );
    });

    test('wireKeys matches the five keys the parser actually reads', () {
      // Both directions, read from source: the declared set and the
      // literals the factory passes to read(). A sixth key parsed but
      // not declared (or declared but not parsed) fails, which a set
      // literal compared against itself could never catch.
      final source = File(path).readAsStringSync();
      final parsed = RegExp(r"read\('(\w+)'\)")
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        parsed,
        isNotEmpty,
        reason: 'the read(...) scan found nothing — re-point this test',
      );
      expect(
        parsed,
        AiSessionCapabilities.wireKeys,
        reason:
            'the keys fromRpc() reads and the keys wireKeys declares have '
            'diverged. wireKeys is what the SQL contract test is compared '
            'against, so a divergence here means the two halves of this '
            'task no longer describe the same contract.',
      );
    });

    test('nothing in the service can write a flag', () {
      // The standing requirement, asserted against the shipped source
      // rather than trusted from review: there is exactly one RPC name
      // and no table write anywhere in this file.
      final stripped = strip(File(path).readAsStringSync());

      expect(
        stripped,
        isNot(contains('feature_flags')),
        reason:
            'this file must not name feature_flags in code — the client '
            'reads capabilities through the RPC precisely because that '
            "table's ai_ rows are hidden from it (PF2)",
      );
      for (final write in <String>['.update(', '.insert(', '.upsert(', '.delete(']) {
        expect(
          stripped,
          isNot(contains(write)),
          reason:
              'this file contains $write — nothing the client can run may '
              'flip a §12 rollout flag; enabling a capability is an '
              'operator act',
        );
      }
    });
  });

  // =================================================================
  // FINDING 5 — the cached `unavailable` is RECOVERABLE
  // =================================================================

  group('aiSessionCapabilitiesProvider: invalidation', () {
    test(
      'a transient failure caches `unavailable` for the whole app '
      'session, and ref.invalidate is what recovers it',
      () async {
        // The two correct decisions whose INTERACTION is the finding:
        // the provider is deliberately NOT autoDispose (these are
        // server rollout flags, so caching for the app session is the
        // point) and `load()` deliberately never throws (it collapses
        // "the server said no" and "I could not ask" to `unavailable`,
        // the fail-closed direction). Together, ONE transient error on
        // the FIRST read hides every AI entry point until relaunch.
        //
        // The provider's own doc promised "`ref.invalidate` or next
        // launch". Before this test, `grep` over `lib/` and `test/`
        // found ZERO invalidate calls on it, so only the second half
        // existed and the first was unverified. This pins it.
        var calls = 0;
        final container = ProviderContainer(
          overrides: [
            aiSessionCapabilitiesServiceProvider.overrideWithValue(
              AiSessionCapabilitiesService((name) async {
                calls++;
                // The transient failure: `load()` swallows the throw
                // and answers `unavailable`.
                if (calls == 1) throw StateError('transient');
                return <String, Object?>{
                  'ai_assist_enabled': true,
                  'ai_sessions_private_enabled': true,
                  'ai_sessions_shared_enabled': false,
                  'ai_sessions_recent_window_enabled': false,
                  'ai_sessions_nearby_enabled': false,
                };
              }),
            ),
          ],
        );
        addTearDown(container.dispose);

        final first = await container.read(
          aiSessionCapabilitiesProvider.future,
        );
        expect(first.noneAvailable, isTrue);
        expect(calls, 1);

        // THE CACHE, demonstrated: a second read does NOT re-ask, so
        // the server having recovered changes nothing.
        final cached = await container.read(
          aiSessionCapabilitiesProvider.future,
        );
        expect(cached.noneAvailable, isTrue);
        expect(
          calls,
          1,
          reason: 'a second read must be served from the cache — if it '
              're-asked, there would be no finding to fix',
        );

        container.invalidate(aiSessionCapabilitiesProvider);
        final recovered = await container.read(
          aiSessionCapabilitiesProvider.future,
        );

        expect(calls, 2);
        // THE SPECIFIC recovered value, not merely "not unavailable":
        // the second answer has `shared` OFF, so an assertion of
        // `noneAvailable == false` alone would also pass for a provider
        // that invented an all-true optimistic value.
        expect(recovered.assist, isTrue);
        expect(recovered.sessionsPrivate, isTrue);
        expect(recovered.sessionsShared, isFalse);
        expect(recovered.sessionsNearby, isFalse);
      },
    );
  });
}
