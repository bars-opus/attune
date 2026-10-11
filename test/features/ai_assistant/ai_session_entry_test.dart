// test/features/ai_assistant/ai_session_entry_test.dart
//
// Plan D Task 9: the two entry points into `AiSessionSheet`, RULING 24's
// single-sheet invariant, RULING 23's Ask Attune gate, and the
// regression proof for both shared chat widgets this task touches.
//
// ## THE REGRESSION CONSTRAINT IS WHY HALF THIS FILE EXISTS
//
// The six §12 capability flags are OFF in every environment and flip
// only AFTER Plan D ships (the user's own decision). So the DEFAULT
// path through everything wired here must leave chat behaviourally
// identical to the composer and long-press menu on `228a75e0`. Task 6
// set this pattern for `ChatTextField` with a group literally named
// "the capability is OFF: the composer is exactly as it was"; the
// groups below do the same for the two widgets Task 9 touches.
//
// ## RULING 29 IS A PROCESS RULE AND IT SHAPED THIS FILE TOO
//
// Task 8's first sheet wiring was green on all eleven of its own new
// tests and crashed 18 previously-passing ones, because a filtered run
// never instantiated the widget it broke. So these tests never stand in
// for the full suite — and, concretely, the `whenComplete` guard in
// `openAiSessionSheet` is tested against a DISPOSED container here
// rather than only against the happy path, because "the caller is gone
// before the route is" is the exact shape that crashed Task 8.
library;

import 'dart:io';

import 'package:attune/features/ai_assistant/data/models/ai_session_model.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_repository.dart';
import 'package:attune/features/ai_assistant/data/services/ai_session_capabilities.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_session_provider.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ai_session_entry.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ai_session_sheet.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart';
import 'package:attune/features/ai_assistant/presentation/screens/assist_sheet.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

User _testUser(String id) => User(
  id: id,
  appMetadata: const <String, dynamic>{},
  userMetadata: const <String, dynamic>{},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

/// A partner-sent plain-text message, so it is eligible for Ask Attune
/// AND makes Understand available (spec §3: Understand requires
/// `sender_id != auth.uid()`), which is what lets the
/// "Understand is untouched" leg assert something real.
Message _partnerMessage() => Message.optimistic(
  id: 'msg-long-pressed',
  clientMessageId: 'c-long-pressed',
  relationshipId: 'rel-1',
  senderId: 'partner',
  content: 'dinner on friday?',
  createdAt: DateTime.now(),
);

/// Only `assist` on, and every session capability off — so a test that
/// passes cannot be passing because some OTHER flag was on. The §12
/// subcapability independence this pins is the reason
/// `AiSessionCapabilities` exposes no "anything is on" aggregate.
const AiSessionCapabilities _assistOnly = AiSessionCapabilities(
  assist: true,
  sessionsPrivate: false,
  sessionsShared: false,
  sessionsRecentWindow: false,
  sessionsNearby: false,
);

const AiSessionCapabilities _ideasSession = AiSessionCapabilities(
  assist: true,
  sessionsPrivate: true,
  sessionsShared: false,
  sessionsRecentWindow: false,
  sessionsNearby: false,
);

const AiSessionCapabilities _nearbySession = AiSessionCapabilities(
  assist: true,
  sessionsPrivate: true,
  sessionsShared: false,
  sessionsRecentWindow: false,
  sessionsNearby: true,
);

/// A gateway that answers nothing. The sheet's own `prepare` is
/// irrelevant to every test here — these assert WHICH widget got
/// pushed and how many of them, not what the session then did (Task 7's
/// own file owns that). Throwing rather than returning a fixture keeps
/// a test that accidentally depends on a session command loud instead
/// of silently green.
class _UnusedGateway implements AiAssistantGateway {
  Never _refuse(String what) {
    throw StateError(
      'An entry-point test must not reach the network. These tests '
      'assert WHICH widget was pushed and HOW MANY, never what the '
      'session then did (ai_session_sheet_test.dart owns that). '
      'Reached: $what',
    );
  }

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) => _refuse('invokeFunction($functionName, $body)');

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) =>
      _refuse('rpc($function)');

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) =>
      _refuse('selectPlanningLink($messageId)');
}

ProviderContainer _container({
  AiSessionCapabilities capabilities = _ideasSession,
}) {
  final container = ProviderContainer(
    overrides: [
      aiSessionRepositoryProvider.overrideWithValue(
        AiSessionRepository(_UnusedGateway()),
      ),
      aiSessionCapabilitiesProvider.overrideWith(
        (ref) => Future<AiSessionCapabilities>.value(capabilities),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A host with a navigator, so a push has somewhere to land.
Future<NavigatorState> _pumpHost(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('host')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigatorKey.currentState!;
}

bool _open(
  ProviderContainer container,
  NavigatorState navigator, {
  AiSessionKind kind = AiSessionKind.ideas,
  String? targetMessageId,
}) {
  return openAiSessionSheet(
    container: container,
    navigator: navigator,
    relationshipId: 'rel-1',
    initialKind: kind,
    utcOffsetMinutes: 0,
    onShared: (_) {},
    targetMessageId: targetMessageId,
  );
}

void main() {
  // ===================================================================
  // RULING 24 — two sheets must never be mounted at once
  // ===================================================================

  group('RULING 24: a second AiSessionSheet cannot open', () {
    testWidgets('one open attempt mounts exactly one sheet', (tester) async {
      final container = _container();
      final navigator = await _pumpHost(tester, container);

      expect(_open(container, navigator), isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(AiSessionSheet), findsOneWidget);
    });

    testWidgets(
      'a SECOND open attempt while one is mounted pushes nothing and '
      'leaves exactly one sheet',
      (tester) async {
        final container = _container();
        final navigator = await _pumpHost(tester, container);

        expect(_open(container, navigator), isTrue);
        await tester.pumpAndSettle();

        // The second attempt is REFUSED, and the refusal is reported.
        expect(
          _open(container, navigator),
          isFalse,
          reason:
              'RULING 24: Task 7 keys aiSessionControllerProvider by the '
              'SHEET, not the session id (the id does not exist until '
              'prepare returns, and a replay returns the original '
              'session). Two mounted sheets would resolve to the SAME '
              'notifier instance and each would see the other turns.',
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(AiSessionSheet),
          findsOneWidget,
          reason: 'a refused open must not have pushed a second route',
        );
      },
    );

    testWidgets(
      'two SYNCHRONOUS opens in one frame still mount exactly one sheet',
      (tester) async {
        // ADDED AFTER A MUTATION (M3) exposed the gap. Deferring the
        // flag's `true` to a microtask was killed ONLY by the
        // flag-ordering test below — both second-open legs awaited a
        // settle first, so the flag was already set by the time they
        // tried. A real double-tap, and a tap that arrives while the
        // push's route transition is still building, are both
        // synchronous: nothing awaits between them. This is that case.
        final container = _container();
        final navigator = await _pumpHost(tester, container);

        final first = _open(container, navigator);
        final second = _open(container, navigator); // no await between
        await tester.pumpAndSettle();

        expect(first, isTrue);
        expect(
          second,
          isFalse,
          reason:
              'the flag must be set BEFORE the push, not after it '
              'resolves, or a double-tap opens two sheets sharing one '
              'controller',
        );
        expect(find.byType(AiSessionSheet), findsOneWidget);
      },
    );

    testWidgets(
      'a second attempt is refused even when the FIRST was opened from a '
      'different entry point — the guard is container-scoped, not '
      'widget-scoped',
      (tester) async {
        // This is the leg that a `bool` in `_ChatScreenState` could not
        // satisfy: the composer entry point and the long-press entry
        // point sit in subtrees with no common State, so two
        // INDEPENDENT navigators sharing one ProviderScope must still
        // see one invariant.
        final container = _container();
        final firstKey = GlobalKey<NavigatorState>();
        final secondKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Row(
                children: [
                  Expanded(
                    child: Navigator(
                      key: firstKey,
                      onGenerateRoute:
                          (_) => MaterialPageRoute<void>(
                            builder: (_) => const Text('entry A'),
                          ),
                    ),
                  ),
                  Expanded(
                    child: Navigator(
                      key: secondKey,
                      onGenerateRoute:
                          (_) => MaterialPageRoute<void>(
                            builder: (_) => const Text('entry B'),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(_open(container, firstKey.currentState!), isTrue);
        await tester.pumpAndSettle();
        expect(
          _open(container, secondKey.currentState!),
          isFalse,
          reason:
              'a per-State flag would have allowed this: the two entry '
              'points cannot see each other, only the container they '
              'share with the controller',
        );
        await tester.pumpAndSettle();

        expect(find.byType(AiSessionSheet), findsOneWidget);
      },
    );

    testWidgets('after the sheet is popped, a new one can open', (
      tester,
    ) async {
      // The invariant must be a LOCK, not a one-shot fuse: a user who
      // closes a session and starts another must get one.
      final container = _container();
      final navigator = await _pumpHost(tester, container);

      expect(_open(container, navigator), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(AiSessionSheet), findsOneWidget);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AiSessionSheet), findsNothing);
      expect(
        container.read(aiSessionSheetMountedProvider),
        isFalse,
        reason: 'the pop must RELEASE the flag, or the entry point is '
            'dead for the rest of the app session',
      );

      expect(_open(container, navigator), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(AiSessionSheet), findsOneWidget);
    });

    testWidgets('the flag is set while mounted and cleared on pop', (
      tester,
    ) async {
      final container = _container();
      final navigator = await _pumpHost(tester, container);

      expect(container.read(aiSessionSheetMountedProvider), isFalse);
      _open(container, navigator);
      expect(
        container.read(aiSessionSheetMountedProvider),
        isTrue,
        reason:
            'set BEFORE the push completes, so a synchronous second '
            'call in the same frame is already refused',
      );
      await tester.pumpAndSettle();

      navigator.pop();
      await tester.pumpAndSettle();
      expect(container.read(aiSessionSheetMountedProvider), isFalse);
    });

    testWidgets('an unmounted navigator is refused without setting the flag', (
      tester,
    ) async {
      final container = _container();
      final navigator = await _pumpHost(tester, container);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(_open(container, navigator), isFalse);
      expect(
        container.read(aiSessionSheetMountedProvider),
        isFalse,
        reason:
            'a refused-for-navigator open must not leave the flag set, '
            'or the entry point is permanently dead',
      );
    });

    test(
      'the push completion does not throw when the container is disposed '
      'first (RULING 29 shape)',
      () async {
        // The caller being gone before the route is, is the ORDINARY
        // path (a chat screen popped while the sheet is up) and is
        // exactly how Task 8 crashed 18 teardowns by reaching `ref` in
        // `dispose`. Proven here at the container level: disposing and
        // then releasing must be a silent no-op, never a StateError.
        final container = ProviderContainer(
          overrides: [
            aiSessionRepositoryProvider.overrideWithValue(
              AiSessionRepository(_UnusedGateway()),
            ),
          ],
        );
        // Make the provider exist, the way an open does.
        expect(container.read(aiSessionSheetMountedProvider), isFalse);
        container.dispose();

        // MEASURED, NOT ASSUMED, and the measurement corrected me.
        //
        // My first guard probed `container.exists(...)`, on the
        // reasoning that it is the one accessor with no `_disposed`
        // check (container.dart:245). It is — but it returns **TRUE**
        // after dispose, because disposal does not clear the element
        // map it looks in. So `exists` cannot detect a disposed
        // container, and a guard built on it would have been VACUOUS:
        // it would have fallen through to the `read` that throws, in
        // exactly the teardown Task 8 crashed on.
        expect(
          container.exists(aiSessionSheetMountedProvider),
          isTrue,
          reason:
              'pinning the surprise: if a future riverpod makes this '
              'false, the catch below is belt-and-braces rather than '
              'load-bearing — but the catch must not be removed on an '
              'assumption about this',
        );
        expect(
          () => container.read(aiSessionSheetMountedProvider.notifier),
          throwsStateError,
          reason:
              'this is what the try/catch in openAiSessionSheet exists '
              'for, and it is the ONLY thing standing between a '
              'disposed container and a StateError thrown into a '
              'route completion',
        );
      },
    );

    testWidgets('opening invalidates the controller so no state carries over', (
      tester,
    ) async {
      // §1: "no previous assistant result is context for a later call."
      // The controller is autoDispose, but a sheet re-opened moments
      // after the last pop can still find the previous instance alive.
      final container = _container();
      final navigator = await _pumpHost(tester, container);

      _open(container, navigator);
      await tester.pumpAndSettle();
      final first = container.read(aiSessionControllerProvider.notifier);
      navigator.pop();
      await tester.pumpAndSettle();

      _open(container, navigator);
      await tester.pumpAndSettle();
      expect(
        container.read(aiSessionControllerProvider.notifier),
        isNot(same(first)),
        reason:
            'a second open must be a FRESH session, not the previous '
            'one re-entered',
      );
    });
  });

  // ===================================================================
  // RULING 24's structural half: the opener must be the ONLY pusher
  // ===================================================================

  group('RULING 24 structurally: nothing else constructs the sheet', () {
    test(
      'ai_session_entry.dart holds the only AiSessionSheet( construction '
      'in lib/, so no entry point can bypass the invariant',
      () {
        // The behavioural tests above prove the LOCK works. They cannot
        // prove nobody walks around it: a future entry point that
        // pushes `AiSessionSheet` directly would mount a second sheet
        // with the flag untouched, and every test above would still
        // pass. This is that guard.
        //
        // The grep-is-not-evidence trap has fired SIX times in this
        // effort, every time because a hit was prose. So this reads the
        // matching LINES and classifies each, rather than counting.
        // A WORD BOUNDARY, not a substring. My first version matched
        // `AiSessionSheet(` as a plain substring and therefore also
        // matched `openAiSessionSheet(` — the OPENER's own name — so
        // every caller of the opener was reported as a direct push.
        // Caught by the test failing on first run, which is the right
        // way round.
        final construction = RegExp(r'(?<![A-Za-z0-9_])AiSessionSheet\(');
        // ANTI-VACUITY for the pattern itself: it matches a real push
        // and does NOT match the opener's name.
        expect(construction.hasMatch('(_) => AiSessionSheet('), isTrue);
        expect(construction.hasMatch('bool openAiSessionSheet({'), isFalse);

        final hits = <String, List<String>>{};
        for (final file in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
          for (final line in file.readAsLinesSync()) {
            if (!construction.hasMatch(line)) continue;
            final trimmed = line.trim();
            // Comments and the class's own declaration are not pushes.
            if (trimmed.startsWith('//') ||
                trimmed.startsWith('///') ||
                trimmed.startsWith('*') ||
                trimmed.contains('const AiSessionSheet({')) {
              continue;
            }
            (hits[file.path] ??= <String>[]).add(trimmed);
          }
        }

        // ANTI-VACUITY: the scan found the real construction, so a
        // silently-empty scan cannot make this pass.
        expect(
          hits.keys,
          contains(
            'lib/features/ai_assistant/presentation/screens/'
            'ai_session_entry.dart',
          ),
          reason:
              'if the scan cannot even find the one legitimate push, it '
              'is measuring nothing',
        );

        expect(
          hits.keys.toList(),
          <String>[
            'lib/features/ai_assistant/presentation/screens/'
                'ai_session_entry.dart',
          ],
          reason:
              'RULING 24: openAiSessionSheet must be the only way in. A '
              'direct push elsewhere would mount a second sheet sharing '
              "Task 7's single controller instance, with the mounted "
              'flag untouched — and every behavioural test in this file '
              'would still pass. Found: $hits',
        );
      },
    );

    test('both entry points reference the opener in source', () {
      // The complement to the guard above, which would also pass if
      // NOTHING pushed the sheet — i.e. if a refactor unwired an entry
      // point. Plan D has exactly two.
      //
      // **DISCLOSED LIMIT, measured not assumed.** This proves the call
      // EXISTS IN SOURCE, not that it is REACHABLE. Mutation M16
      // wrapped the long-press branch in `if (false && ...)` and this
      // test still passed, because the text is still there inside the
      // dead branch. The behavioural cover for that path is
      // `the long-press "Get ideas" path reaches the session sheet`
      // below; the composer path's is in
      // `chat_screen_message_actions_test.dart`. This test is the
      // cheap "did someone delete a wire" check, and is recorded as
      // exactly that rather than as a reachability proof.
      final callers = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        if (file.path.endsWith('ai_session_entry.dart')) continue;
        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          if (trimmed.contains('openAiSessionSheet(')) {
            callers.add(file.path);
            break;
          }
        }
      }
      expect(
        callers..sort(),
        <String>[
          'lib/features/ai_assistant/presentation/screens/'
              'ask_attune_mode_sheet.dart',
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ],
        reason:
            'the composer button and the long-press "Get ideas" are the '
            "plan's two entry points; losing one is as much a defect as "
            'adding a third that bypasses the opener',
      );
    });
  });

  // ===================================================================
  // The long-press entry point, driven end to end
  // ===================================================================

  group('the long-press "Get ideas" path', () {
    /// `AskAttuneModeSheet` past its consent gate, with [capabilities].
    Future<void> pumpModeSheet(
      WidgetTester tester, {
      required AiSessionCapabilities capabilities,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            aiSessionRepositoryProvider.overrideWithValue(
              AiSessionRepository(_UnusedGateway()),
            ),
            aiAssistantRepositoryProvider.overrideWithValue(
              AiAssistantRepository(_UnusedGateway()),
            ),
            aiSessionCapabilitiesProvider.overrideWith(
              (ref) => Future<AiSessionCapabilities>.value(capabilities),
            ),
            currentUserProvider.overrideWithValue(_testUser('user-a')),
            currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
            aiConsentStatusProvider('rel-1').overrideWith(
              (ref) async => const AiConsentStatus(
                callerGranted: true,
                bothGranted: true,
                policyVersion: 'v1',
              ),
            ),
          ],
          child: MaterialApp(
            home: AskAttuneModeSheet(message: _partnerMessage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'reaches the session sheet with the long-pressed message '
      'pre-attached, when the capability allows it',
      (tester) async {
        // THE REACHABILITY PROOF the source scan cannot give (M16).
        // Drives the real tiles: "Get ideas" -> the Ideas/Nearby picker
        // -> the session sheet.
        await pumpModeSheet(tester, capabilities: _ideasSession);

        await tester.tap(find.byKey(const ValueKey('ask-attune-mode-assist')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('assist-kind-ideas')));
        await tester.pumpAndSettle();

        expect(find.byType(AiSessionSheet), findsOneWidget);
        final sheet = tester.widget<AiSessionSheet>(
          find.byType(AiSessionSheet),
        );
        expect(
          sheet.targetMessageId,
          'msg-long-pressed',
          reason:
              "this plan's Architecture note: the session is pre-seeded "
              'with the selected message, and this is the only entry '
              'point that HAS one',
        );
        expect(sheet.relationshipId, 'rel-1');
        expect(sheet.initialKind, AiSessionKind.ideas);
        // The single-turn sheet must NOT also be on the stack.
        expect(find.byType(AssistSheet), findsNothing);
      },
    );

    testWidgets(
      'falls back to the single-turn AssistSheet when the capability is '
      'off — the regression leg',
      (tester) async {
        // THE REGRESSION PROOF for this entry point. Today, with every
        // flag off, "Get ideas" -> Ideas opens single-turn Assist. An
        // UNCONDITIONAL repoint (which the brief asked for) would have
        // turned that into a FEATURE_DISABLED screen for every user,
        // since checkEligibility CHECK 0 refuses a disabled capability.
        await pumpModeSheet(
          tester,
          capabilities: AiSessionCapabilities.unavailable,
        );

        await tester.tap(find.byKey(const ValueKey('ask-attune-mode-assist')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('assist-kind-ideas')));
        await tester.pumpAndSettle();

        expect(
          find.byType(AiSessionSheet),
          findsNothing,
          reason:
              'a session must not be offered against an off capability',
        );
        expect(
          find.byType(AssistSheet),
          findsOneWidget,
          reason:
              "today's single-turn path must still work — it is what "
              'every environment gets until an operator flips the flags',
        );
      },
    );

    testWidgets(
      'Nearby picks the Nearby SESSION only when sessionsNearby is on, '
      'and single-turn Nearby otherwise',
      (tester) async {
        await pumpModeSheet(tester, capabilities: _nearbySession);
        await tester.tap(find.byKey(const ValueKey('ask-attune-mode-assist')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('assist-kind-nearby')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AiSessionSheet>(find.byType(AiSessionSheet))
              .initialKind,
          AiSessionKind.nearby,
        );

        // The other direction, in the same test so the two fixtures
        // cannot drift apart: Ideas sessions on, Nearby off.
        await pumpModeSheet(tester, capabilities: _ideasSession);
        await tester.tap(find.byKey(const ValueKey('ask-attune-mode-assist')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('assist-kind-nearby')));
        await tester.pumpAndSettle();
        expect(
          find.byType(AiSessionSheet),
          findsNothing,
          reason:
              '§12 forbids inferring sessionsNearby from '
              'sessionsPrivate being on',
        );
        expect(find.byType(AssistSheet), findsOneWidget);
      },
    );

    testWidgets('the Understand branch is untouched', (tester) async {
      // Named explicitly because the dispatch asks what I did NOT
      // change, and "I did not touch it" is better asserted than
      // claimed. A partner-sent message makes Understand available.
      await pumpModeSheet(tester, capabilities: _ideasSession);

      expect(
        find.byKey(const ValueKey('ask-attune-mode-understand')),
        findsOneWidget,
      );
      expect(find.text('Possible ways to read this'), findsOneWidget);
    });
  });

  // ===================================================================
  // The sheet is pushed with what the entry point actually knows
  // ===================================================================

  group('the opened sheet carries the entry point values', () {
    testWidgets('the target message is pre-attached when one is given', (
      tester,
    ) async {
      final container = _container();
      final navigator = await _pumpHost(tester, container);

      _open(container, navigator, targetMessageId: 'msg-7');
      await tester.pumpAndSettle();

      final sheet = tester.widget<AiSessionSheet>(find.byType(AiSessionSheet));
      expect(sheet.targetMessageId, 'msg-7');
      expect(sheet.relationshipId, 'rel-1');
      expect(sheet.initialKind, AiSessionKind.ideas);
    });

    testWidgets('no target message is attached when none is given', (
      tester,
    ) async {
      // The composer entry point names no message, and
      // `target_message_id` must then be ABSENT rather than a
      // placeholder — the same "I did not ask" literalism Ruling 14
      // settled for `request_id`.
      final container = _container();
      final navigator = await _pumpHost(tester, container);

      _open(container, navigator);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<AiSessionSheet>(find.byType(AiSessionSheet))
            .targetMessageId,
        isNull,
      );
    });

    testWidgets('the requested kind reaches the sheet', (tester) async {
      final container = _container(capabilities: _nearbySession);
      final navigator = await _pumpHost(tester, container);

      _open(container, navigator, kind: AiSessionKind.nearby);
      await tester.pumpAndSettle();

      expect(
        tester.widget<AiSessionSheet>(find.byType(AiSessionSheet)).initialKind,
        AiSessionKind.nearby,
      );
    });
  });

  // ===================================================================
  // The displayed offset
  // ===================================================================

  group('displayedUtcOffsetMinutes', () {
    test('reports the offset of the instant it is given, in minutes', () {
      // One function so the two entry points cannot disagree about the
      // civil day. The server REFUSES an out-of-range offset rather
      // than clamping (a clamped offset computes a different civil day
      // than the user saw — §4.2, and the N3 fix), so this must be the
      // real local offset and not a constant.
      final now = DateTime.now();
      expect(
        displayedUtcOffsetMinutes(now),
        now.timeZoneOffset.inMinutes,
      );
      expect(
        displayedUtcOffsetMinutes(),
        DateTime.now().timeZoneOffset.inMinutes,
      );
    });

    test('is within the range the server accepts, and is an integer', () {
      // Transcribed from the server's own validator, read rather than
      // guessed: `isValidUtcOffsetMinutes`
      // (`supabase/functions/_shared/ai_session_context.ts:147-152`)
      // requires a NUMBER that is an INTEGER in [-840, 840]. A value
      // outside it is INVALID_INPUT on every command, and §4.2 forbids
      // the server clamping, because a clamped offset computes a
      // different civil day than the client displayed.
      final offset = displayedUtcOffsetMinutes();
      expect(offset, greaterThanOrEqualTo(-840));
      expect(offset, lessThanOrEqualTo(840));
      // `Duration.inMinutes` truncates toward zero, so this is an int by
      // construction — asserted anyway, because the server rejects a
      // non-integer and the type is the only thing guaranteeing it.
      expect(offset, isA<int>());
    });
  });

  // ===================================================================
  // The per-kind session gate on "Get ideas"
  // ===================================================================

  group('the Get ideas repoint is per-kind and capability-gated', () {
    test('Ideas needs a session visibility, Nearby needs sessionsNearby', () {
      // Asserted on the pure function across every relevant
      // combination, because a widget pump can only reach a few of them
      // and the §12 independence claim is about ALL of them.
      expect(
        debugSessionKindFor(AssistKind.ideas, _ideasSession),
        AiSessionKind.ideas,
      );
      expect(
        debugSessionKindFor(AssistKind.nearby, _ideasSession),
        isNull,
        reason:
            'sessionsNearby is off, so a Nearby SESSION is not '
            'offerable — and §12 forbids inferring it from '
            'sessionsPrivate being on',
      );
      expect(
        debugSessionKindFor(AssistKind.nearby, _nearbySession),
        AiSessionKind.nearby,
      );
      expect(
        debugSessionKindFor(AssistKind.ideas, _nearbySession),
        AiSessionKind.ideas,
      );
    });

    test('assist alone offers NO session of either kind', () {
      // The sharpest independence leg: `assist` gates the single-turn
      // Ask Attune entry point and says nothing about sessions. A gate
      // reading `assist` here would offer a session the sheet would
      // immediately render as unavailable.
      expect(debugSessionKindFor(AssistKind.ideas, _assistOnly), isNull);
      expect(debugSessionKindFor(AssistKind.nearby, _assistOnly), isNull);

      // STRENGTHENED AFTER M13. Substituting `assist` for the
      // visibility disjunction was killed only by the
      // Nearby-without-visibility fixture, via a different test — a
      // right-verdict-wrong-test result of the kind this effort has
      // caught repeatedly. The direct form is: `assist` OFF while a
      // session visibility is ON must still offer a session, because
      // the two capabilities are independent (§12) and a shared-only
      // session rollout with single-turn Assist killed is a legitimate
      // operator state.
      const sessionsWithoutAssist = AiSessionCapabilities(
        assist: false,
        sessionsPrivate: true,
        sessionsShared: false,
        sessionsRecentWindow: false,
        sessionsNearby: true,
      );
      expect(
        debugSessionKindFor(AssistKind.ideas, sessionsWithoutAssist),
        AiSessionKind.ideas,
        reason:
            'a gate reading `assist` instead of the visibility flags '
            'would deny this — but §12 subcapability independence means '
            'killing single-turn Assist must not close sessions',
      );
      expect(
        debugSessionKindFor(AssistKind.nearby, sessionsWithoutAssist),
        AiSessionKind.nearby,
      );
    });

    test('a session needs a visibility even for Nearby', () {
      // `_PreparationView` renders kAiSessionUnavailableMessage when
      // EITHER list is empty, so a Nearby capability with no visibility
      // is not an offerable session.
      const nearbyWithoutVisibility = AiSessionCapabilities(
        assist: true,
        sessionsPrivate: false,
        sessionsShared: false,
        sessionsRecentWindow: false,
        sessionsNearby: true,
      );
      expect(
        debugSessionKindFor(AssistKind.nearby, nearbyWithoutVisibility),
        isNull,
      );
      expect(
        debugSessionKindFor(AssistKind.ideas, nearbyWithoutVisibility),
        isNull,
      );
    });

    test('shared-only is a valid visibility for an Ideas session', () {
      // `_PreparationView` offers Ideas on
      // `sessionsPrivate || sessionsShared`, so SHARED alone must work
      // — a gate testing only sessionsPrivate would deny a legitimate
      // shared-only rollout.
      const sharedOnly = AiSessionCapabilities(
        assist: true,
        sessionsPrivate: false,
        sessionsShared: true,
        sessionsRecentWindow: false,
        sessionsNearby: false,
      );
      expect(
        debugSessionKindFor(AssistKind.ideas, sharedOnly),
        AiSessionKind.ideas,
      );
    });

    test('ALL capabilities off offers no session — today behaviour', () {
      expect(
        debugSessionKindFor(
          AssistKind.ideas,
          AiSessionCapabilities.unavailable,
        ),
        isNull,
      );
      expect(
        debugSessionKindFor(
          AssistKind.nearby,
          AiSessionCapabilities.unavailable,
        ),
        isNull,
      );
    });

    test('an UNRESOLVED capability offers no session, never permission', () {
      // Still loading, or the service failed closed. There must be no
      // path here that turns an unknown into a session.
      expect(debugSessionKindFor(AssistKind.ideas, null), isNull);
      expect(debugSessionKindFor(AssistKind.nearby, null), isNull);
    });
  });
}
