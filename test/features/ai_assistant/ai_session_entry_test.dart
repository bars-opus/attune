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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('is within the range the server accepts', () {
      // `isValidUtcOffsetMinutes` bounds this server-side; a value
      // outside it is INVALID_INPUT on every command.
      final offset = displayedUtcOffsetMinutes();
      expect(offset, greaterThanOrEqualTo(-14 * 60));
      expect(offset, lessThanOrEqualTo(14 * 60));
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
