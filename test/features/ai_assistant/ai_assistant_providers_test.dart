// Provider-level tests for the AI Assistant feature's Riverpod surface.
// Exercises the sheet-scoping guarantee spec §1 requires ("no previous
// assistant result is context for a later call") and spec §6.3's
// Understand-clearing rules, against a faked `AiAssistantGateway` —
// the same seam `ai_assistant_repository_test.dart` already fakes,
// so these tests never touch a real `SupabaseClient`.
import 'package:attune/features/ai_assistant/data/models/assist_draft_model.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/assistant_error.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAiAssistantGateway implements AiAssistantGateway {
  Object? nextInvokeError;
  dynamic nextInvokeResult;

  Object? nextRpcError;
  dynamic nextRpcResult;

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    if (nextInvokeError != null) {
      final error = nextInvokeError!;
      nextInvokeError = null;
      throw error;
    }
    return nextInvokeResult;
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    if (nextRpcError != null) {
      final error = nextRpcError!;
      nextRpcError = null;
      throw error;
    }
    return nextRpcResult;
  }
}

Map<String, dynamic> _ideasResponse({String draftId = 'draft-1'}) => {
  'draft_id': draftId,
  'reply_text': 'Try a picnic.',
  'suggested_planning_item': null,
  'expires_at': '2026-09-16T12:15:00.000Z',
};

Map<String, dynamic> _understandOkResponse() => {
  'status': 'ok',
  'possible_readings': ['They might be tired.'],
  'response_options': ['Want to talk about it?'],
  'confidence': 'low',
};

ProviderContainer _makeContainer(_FakeAiAssistantGateway gateway) {
  final container = ProviderContainer(
    overrides: [
      aiAssistantRepositoryProvider.overrideWithValue(
        AiAssistantRepository(gateway),
      ),
    ],
  );
  return container;
}

void main() {
  // understandResultProvider's build() constructs an AppLifecycleListener
  // (to clear on background per spec §6.3), which requires
  // WidgetsBinding to be initialized even outside a widget test.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('assistDraftProvider', () {
    test('starts idle (null) for a freshly-opened sheet instance', () async {
      final container = _makeContainer(_FakeAiAssistantGateway());
      addTearDown(container.dispose);

      final value = await container.read(assistDraftProvider.future);
      expect(value, isNull);
    });

    test(
      'a second, separately-scoped sheet-open sees no trace of a prior '
      "sheet's completed draft — two independent ProviderContainers, "
      'simulating two sequential sheet opens, never share state',
      () async {
        final gateway1 = _FakeAiAssistantGateway()
          ..nextInvokeResult = _ideasResponse(draftId: 'draft-from-sheet-1');
        final container1 = _makeContainer(gateway1);
        addTearDown(container1.dispose);

        await container1
            .read(assistDraftProvider.notifier)
            .requestAssist(
              requestId: 'req-1',
              messageId: 'msg-1',
              assistKind: 'ideas',
            );
        final firstResult = container1.read(assistDraftProvider).value;
        expect(firstResult, isA<AssistDraftIdeas>());
        expect(firstResult!.draftId, 'draft-from-sheet-1');

        // Simulate the first sheet closing (autoDispose tears the
        // instance down once nothing listens) and a second, brand-new
        // sheet opening: a fresh container standing in for a fresh
        // provider scope.
        container1.dispose();

        final gateway2 = _FakeAiAssistantGateway();
        final container2 = _makeContainer(gateway2);
        addTearDown(container2.dispose);

        final secondSheetInitialValue = await container2.read(
          assistDraftProvider.future,
        );
        expect(
          secondSheetInitialValue,
          isNull,
          reason:
              "the second sheet's provider instance must start idle — "
              "it must never see sheet 1's completed draft as its own "
              'initial/build-time value',
        );
      },
    );

    test(
      'disposing the container (simulating sheet dismiss) then '
      'reading the provider on a NEW container never returns the old '
      'draft',
      () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _ideasResponse(draftId: 'draft-x');
        final container = _makeContainer(gateway);
        await container
            .read(assistDraftProvider.notifier)
            .requestAssist(
              requestId: 'req-1',
              messageId: 'msg-1',
              assistKind: 'ideas',
            );
        expect(container.read(assistDraftProvider).value, isNotNull);
        container.dispose();

        final freshContainer = _makeContainer(_FakeAiAssistantGateway());
        addTearDown(freshContainer.dispose);
        final freshValue = await freshContainer.read(assistDraftProvider.future);
        expect(freshValue, isNull);
      },
    );

    test(
      'WITHIN A SINGLE CONTAINER, once the sheet stops listening '
      '(simulating dismiss) and a new sheet opens (simulating a fresh '
      'watch), .autoDispose tears the old notifier down and the new '
      "watch gets a fresh instance — never the old sheet's draft. This "
      'is the actual mechanism (not just separate containers) the '
      'no-leakage guarantee relies on in production, where the whole '
      'app runs inside one container.',
      () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _ideasResponse(draftId: 'draft-from-sheet-1');
        final container = _makeContainer(gateway);
        addTearDown(container.dispose);

        // Sheet 1 opens: something watches the provider (a real sheet's
        // ref.watch), then requests a draft.
        final sub1 = container.listen(assistDraftProvider, (_, __) {});
        await container
            .read(assistDraftProvider.notifier)
            .requestAssist(
              requestId: 'req-1',
              messageId: 'msg-1',
              assistKind: 'ideas',
            );
        expect(container.read(assistDraftProvider).value?.draftId,
            'draft-from-sheet-1');

        // Sheet 1 dismisses: its watch is cancelled. With .autoDispose
        // and no other listener, Riverpod schedules disposal.
        sub1.close();
        // autoDispose teardown happens on a microtask/timer tick.
        await Future<void>.delayed(Duration.zero);

        // Sheet 2 opens: a fresh watch on the SAME container/provider.
        final value = await container.read(assistDraftProvider.future);
        expect(
          value,
          isNull,
          reason:
              "sheet 2's fresh watch must get a brand-new notifier "
              "instance whose build() reruns to idle — not sheet 1's "
              'disposed-but-cached data',
        );
      },
    );

    test(
      'a CONSENT_REQUIRED error surfaces distinctly from a generic/'
      'network-style error, so the UI can render the '
      '"waiting for your partner" copy specifically',
      () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeError = const AssistantError.consentRequired();
        final container = _makeContainer(gateway);
        addTearDown(container.dispose);

        await container
            .read(assistDraftProvider.notifier)
            .requestAssist(
              requestId: 'req-1',
              messageId: 'msg-1',
              assistKind: 'ideas',
            );

        final state = container.read(assistDraftProvider);
        expect(state.hasError, isTrue);
        expect(state.error, isA<AssistantConsentRequiredError>());
      },
    );

    test(
      'an internalError (standing in for a network/transport failure) '
      'surfaces as a distinct subtype from consentRequired',
      () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeError = const AssistantError.internalError();
        final container = _makeContainer(gateway);
        addTearDown(container.dispose);

        await container
            .read(assistDraftProvider.notifier)
            .requestAssist(
              requestId: 'req-1',
              messageId: 'msg-1',
              assistKind: 'ideas',
            );

        final state = container.read(assistDraftProvider);
        expect(state.hasError, isTrue);
        expect(state.error, isA<AssistantInternalError>());
        expect(state.error, isNot(isA<AssistantConsentRequiredError>()));
      },
    );
  });

  group('understandResultProvider', () {
    test('starts idle (null) for a freshly-opened sheet instance', () async {
      final container = _makeContainer(_FakeAiAssistantGateway());
      addTearDown(container.dispose);

      final value = await container.read(understandResultProvider.future);
      expect(value, isNull);
    });

    test(
      'clears itself when its container is disposed (simulating dismiss) '
      '— a fresh container reading the provider again never observes '
      "the disposed instance's completed result",
      () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _understandOkResponse();
        final container = _makeContainer(gateway);
        await container
            .read(understandResultProvider.notifier)
            .requestUnderstand(
              requestId: 'req-1',
              messageId: 'msg-1',
              utcOffsetMinutes: 0,
            );
        expect(container.read(understandResultProvider).value, isNotNull);

        container.dispose();

        final freshContainer = _makeContainer(_FakeAiAssistantGateway());
        addTearDown(freshContainer.dispose);
        final freshValue = await freshContainer.read(
          understandResultProvider.future,
        );
        expect(
          freshValue,
          isNull,
          reason:
              'a disposed instance must never leak its result into a '
              'later, unrelated provider instance',
        );
      },
    );

    test(
      'WITHIN A SINGLE CONTAINER, once the Understand sheet stops '
      'listening (simulating dismiss) and a new sheet opens later in '
      'the same app session (simulating a fresh watch), .autoDispose '
      "tears the old notifier down and the new watch gets a fresh "
      "instance — never the old sheet's private result. Same "
      "reasoning as assistDraftProvider's own same-container test: a "
      'cross-container test alone would pass even if `.autoDispose` '
      'were entirely broken, and Understand is the MORE '
      'privacy-sensitive of the two notifiers (spec §6.3), so this '
      'exact guarantee — not just the weaker cross-container one — '
      'must be exercised for it too.',
      () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _understandOkResponse();
        final container = _makeContainer(gateway);
        addTearDown(container.dispose);

        // Sheet 1 opens: something watches the provider (a real
        // sheet's ref.watch), then requests an Understand result.
        final sub1 = container.listen(understandResultProvider, (_, __) {});
        await container
            .read(understandResultProvider.notifier)
            .requestUnderstand(
              requestId: 'req-1',
              messageId: 'msg-1',
              utcOffsetMinutes: 0,
            );
        expect(container.read(understandResultProvider).value, isNotNull);

        // Sheet 1 dismisses: its watch is cancelled. With .autoDispose
        // and no other listener, Riverpod schedules disposal.
        sub1.close();
        // autoDispose teardown happens on a microtask/timer tick — this
        // notifier's build() does more work (an extra ref.listen plus
        // constructing an AppLifecycleListener) than
        // AssistDraftNotifier's, so give it a full event-queue pump
        // rather than a single Duration.zero tick.
        await pumpEventQueue();

        // Sheet 2 opens later in the SAME app session: a fresh watch
        // on the SAME container/provider.
        final value = await container.read(understandResultProvider.future);
        expect(
          value,
          isNull,
          reason:
              "sheet 2's fresh watch must get a brand-new notifier "
              "instance whose build() reruns to idle — never sheet "
              "1's disposed-but-cached private result",
        );
      },
    );

    test(
      'reading the disposed provider instance itself does not silently '
      'return stale data — the container refuses further reads',
      () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _understandOkResponse();
        final container = _makeContainer(gateway);
        await container
            .read(understandResultProvider.notifier)
            .requestUnderstand(
              requestId: 'req-1',
              messageId: 'msg-1',
              utcOffsetMinutes: 0,
            );
        container.dispose();

        expect(
          () => container.read(understandResultProvider),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'a CONSENT_REQUIRED error surfaces distinctly from a generic '
      'internal error',
      () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeError = const AssistantError.consentRequired();
        final container = _makeContainer(gateway);
        addTearDown(container.dispose);

        await container
            .read(understandResultProvider.notifier)
            .requestUnderstand(
              requestId: 'req-1',
              messageId: 'msg-1',
              utcOffsetMinutes: 0,
            );

        final state = container.read(understandResultProvider);
        expect(state.hasError, isTrue);
        expect(state.error, isA<AssistantConsentRequiredError>());
      },
    );

    test(
      'clear() resets to idle without needing the container disposed',
      () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _understandOkResponse();
        final container = _makeContainer(gateway);
        addTearDown(container.dispose);

        await container
            .read(understandResultProvider.notifier)
            .requestUnderstand(
              requestId: 'req-1',
              messageId: 'msg-1',
              utcOffsetMinutes: 0,
            );
        expect(container.read(understandResultProvider).value, isNotNull);

        container.read(understandResultProvider.notifier).clear();
        expect(container.read(understandResultProvider).value, isNull);
      },
    );

    test(
      'a response that resolves after clear() (a late response) is '
      'discarded rather than resurrecting a cleared result',
      () async {
        final gateway = _FakeAiAssistantGateway();
        final container = _makeContainer(gateway);
        addTearDown(container.dispose);

        final notifier = container.read(understandResultProvider.notifier);
        // Prime the gateway with a result, but race clear() before the
        // await inside requestUnderstand resolves by not awaiting the
        // call itself.
        gateway.nextInvokeResult = _understandOkResponse();
        final future = notifier.requestUnderstand(
          requestId: 'req-1',
          messageId: 'msg-1',
          utcOffsetMinutes: 0,
        );
        notifier.clear();
        await future;

        expect(
          container.read(understandResultProvider).value,
          isNull,
          reason:
              'clear() bumps the request epoch, so the in-flight '
              "request's eventual response must be dropped as stale",
        );
      },
    );
  });

  group('aiConsentStatusProvider', () {
    test('reads consent status through the repository', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextRpcResult = [
          {
            'caller_granted': true,
            'both_granted': false,
            'policy_version': 'v1',
          },
        ];
      final container = _makeContainer(gateway);
      addTearDown(container.dispose);

      final status = await container.read(
        aiConsentStatusProvider('rel-1').future,
      );
      expect(status.callerGranted, isTrue);
      expect(status.bothGranted, isFalse);
    });
  });
}
